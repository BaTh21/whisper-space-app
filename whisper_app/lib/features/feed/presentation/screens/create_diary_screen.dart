import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';
import 'package:whisper_space_flutter/features/feed/data/datasources/feed_api_service.dart';
import 'package:whisper_space_flutter/features/feed/presentation/providers/feed_provider.dart';

class CreateDiaryScreen extends StatefulWidget {
  final FeedApiService feedApiService;
  final Function(DiaryModel)? onDiaryCreated;

  const CreateDiaryScreen({
    super.key,
    required this.feedApiService,
    this.onDiaryCreated,
  });

  @override
  State<CreateDiaryScreen> createState() => _CreateDiaryScreenState();
}

class _CreateDiaryScreenState extends State<CreateDiaryScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  String _shareType = 'personal';
  final List<int> _selectedGroupIds = [];
  final List<File> _selectedImages = [];
  final List<File> _selectedVideos = [];

  bool _isLoading = false;
  bool _uploadingMedia = false;
  bool _showGroupSelection = false;
  bool _loadingGroups = false;

  List<Group> _availableGroups = [];
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUserGroups();
  }

  Future<void> _loadUserGroups() async {
    if (_loadingGroups) return;

    setState(() => _loadingGroups = true);

    try {
      final groups = await widget.feedApiService.getUserGroups();
      if (mounted) {
        setState(() {
          _availableGroups = groups;
        });
      }
    } catch (e) {
      // Use debugPrint instead of print
      debugPrint('Failed to load groups: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingGroups = false);
      }
    }
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile>? pickedFiles = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFiles != null && pickedFiles.isNotEmpty && mounted) {
        setState(() {
          for (final xfile in pickedFiles) {
            if (_selectedImages.length < 10) {
              _selectedImages.add(File(xfile.path));
            }
          }
        });
        _showSnackBar('Added ${pickedFiles.length} image(s)', isError: false);
      }
    } catch (e) {
      _showSnackBar('Failed to pick images: $e', isError: true);
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (pickedFile != null && mounted) {
        final file = File(pickedFile.path);
        final fileSize = await file.length();
        if (fileSize > 50 * 1024 * 1024) {
          _showSnackBar('Video file too large. Maximum size is 50MB.', isError: true);
          return;
        }

        setState(() {
          if (_selectedVideos.length < 3) {
            _selectedVideos.add(file);
          } else {
            _showSnackBar('Maximum 3 videos allowed', isError: true);
          }
        });
      }
    } catch (e) {
      _showSnackBar('Failed to pick video: $e', isError: true);
    }
  }

  Future<void> _submitDiary() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please fix the errors in the form', isError: true);
      return;
    }

    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty || content.isEmpty) {
      _showSnackBar('Please enter both title and content', isError: true);
      return;
    }

    if (title.length < 3) {
      _showSnackBar('Title must be at least 3 characters', isError: true);
      return;
    }

    if (content.length < 10) {
      _showSnackBar('Content must be at least 10 characters', isError: true);
      return;
    }

    if (_shareType == 'group') {
      if (_selectedGroupIds.isEmpty) {
        _showSnackBar('Please select at least one group', isError: true);
        return;
      }

      if (_availableGroups.isEmpty) {
        _showSnackBar('No groups available. Create a group first.', isError: true);
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      List<String> imageUrls = [];
      List<String> videoUrls = [];

      if (_selectedImages.isNotEmpty || _selectedVideos.isNotEmpty) {
        if (mounted) setState(() => _uploadingMedia = true);

        for (final image in _selectedImages) {
          try {
            final url = await widget.feedApiService.uploadMedia(image, isVideo: false);
            imageUrls.add(url);
          } catch (e) {
            debugPrint('Failed to upload image: $e');
          }
        }

        for (final video in _selectedVideos) {
          try {
            final url = await widget.feedApiService.uploadMedia(video, isVideo: true);
            videoUrls.add(url);
          } catch (e) {
            debugPrint('Failed to upload video: $e');
          }
        }

        if (mounted) setState(() => _uploadingMedia = false);
      }

      final feedProvider = Provider.of<FeedProvider>(context, listen: false);

      // Use FeedProvider.createDiary (which handles API + optimistic UI update)
      final diary = await feedProvider.createDiary(
        title: title,
        content: content,
        shareType: _shareType,
        groupIds: _selectedGroupIds,
        imageUrls: imageUrls,
        videoUrls: videoUrls,
      );

      _showSnackBar('✅ Diary created successfully!', isError: false);

      if (widget.onDiaryCreated != null) {
        widget.onDiaryCreated!(diary);
      }

      if (mounted) {
        Navigator.of(context).pop(diary);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _uploadingMedia = false;
        });
        _showSnackBar('Failed to create diary: ${e.toString()}', isError: true);
      }
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildGroupSelectionSection() {
    if (!_showGroupSelection) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Select Groups:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (_loadingGroups)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _loadUserGroups,
                tooltip: 'Refresh groups',
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (_availableGroups.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                const Icon(Icons.group, size: 48, color: Colors.grey),
                const SizedBox(height: 8),
                Text(
                  'No groups available',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Create a group first or join existing ones',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableGroups.map((group) {
                  final isSelected = _selectedGroupIds.contains(group.id);
                  return FilterChip(
                    label: Text(group.name),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedGroupIds.add(group.id);
                        } else {
                          _selectedGroupIds.remove(group.id);
                        }
                      });
                    },
                    selectedColor: Theme.of(context).colorScheme.primaryContainer,
                    checkmarkColor: Theme.of(context).colorScheme.primary,
                    avatar: CircleAvatar(
                      backgroundColor: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      radius: 12,
                      child: Text(
                        group.name.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              if (_selectedGroupIds.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Selected: ${_selectedGroupIds.length} group(s)',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Diary'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _isLoading ? null : () {
            if (_titleController.text.isNotEmpty ||
                _contentController.text.isNotEmpty ||
                _selectedImages.isNotEmpty ||
                _selectedVideos.isNotEmpty) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Discard Diary?'),
                  content: const Text('You have unsaved changes. Are you sure you want to discard?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pop(context);
                      },
                      child: Text(
                        'Discard',
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ],
                ),
              );
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Title *',
                      hintText: 'Give your diary a title',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    maxLength: 255,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a title';
                      }
                      if (value.trim().length < 3) {
                        return 'Title must be at least 3 characters';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _contentController,
                    decoration: InputDecoration(
                      labelText: 'Content *',
                      hintText: 'Write your thoughts here...',
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    maxLines: 8,
                    minLines: 4,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter some content';
                      }
                      if (value.trim().length < 10) {
                        return 'Content must be at least 10 characters';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Privacy:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(context).colorScheme.outline),
                          borderRadius: BorderRadius.circular(8),
                          color: Theme.of(context).colorScheme.surfaceContainerLowest,
                        ),
                        child: Column(
                          children: [
                            RadioListTile<String>(
                              title: const Row(
                                children: [
                                  Icon(Icons.lock, size: 20, color: Colors.redAccent),
                                  SizedBox(width: 8),
                                  Text('Private'),
                                ],
                              ),
                              subtitle: const Text('Only you can see this'),
                              value: 'personal',
                              groupValue: _shareType,
                              onChanged: _isLoading
                                  ? null
                                  : (value) {
                                      if (value != null && mounted) {
                                        setState(() {
                                          _shareType = value;
                                          _showGroupSelection = false;
                                        });
                                      }
                                    },
                              activeColor: Theme.of(context).colorScheme.primary,
                            ),
                            Divider(height: 1, color: Theme.of(context).colorScheme.outline),
                            RadioListTile<String>(
                              title: const Row(
                                children: [
                                  Icon(Icons.public, size: 20, color: Colors.teal),
                                  SizedBox(width: 8),
                                  Text('Public'),
                                ],
                              ),
                              subtitle: const Text('Everyone can see this'),
                              value: 'public',
                              groupValue: _shareType,
                              onChanged: _isLoading
                                  ? null
                                  : (value) {
                                      if (value != null && mounted) {
                                        setState(() {
                                          _shareType = value;
                                          _showGroupSelection = false;
                                        });
                                      }
                                    },
                              activeColor: Theme.of(context).colorScheme.primary,
                            ),
                            Divider(height: 1, color: Theme.of(context).colorScheme.outline),
                            RadioListTile<String>(
                              title: const Row(
                                children: [
                                  Icon(Icons.people, size: 20, color: Colors.blue),
                                  SizedBox(width: 8),
                                  Text('Friends'),
                                ],
                              ),
                              subtitle: const Text('Only your friends can see this'),
                              value: 'friends',
                              groupValue: _shareType,
                              onChanged: _isLoading
                                  ? null
                                  : (value) {
                                      if (value != null && mounted) {
                                        setState(() {
                                          _shareType = value;
                                          _showGroupSelection = false;
                                        });
                                      }
                                    },
                              activeColor: Theme.of(context).colorScheme.primary,
                            ),
                            Divider(height: 1, color: Theme.of(context).colorScheme.outline),
                            RadioListTile<String>(
                              title: const Row(
                                children: [
                                  Icon(Icons.group, size: 20, color: Colors.deepPurple),
                                  SizedBox(width: 8),
                                  Text('Selected Groups'),
                                ],
                              ),
                              subtitle: const Text('Only selected groups can see this'),
                              value: 'group',
                              groupValue: _shareType,
                              onChanged: _isLoading
                                  ? null
                                  : (value) {
                                      if (value != null && mounted) {
                                        setState(() {
                                          _shareType = value;
                                          _showGroupSelection = true;
                                        });
                                      }
                                    },
                              activeColor: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  _buildGroupSelectionSection(),

                  const SizedBox(height: 16),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Media (optional):',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _pickImages,
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Add Photos'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _pickVideo,
                              icon: const Icon(Icons.video_library),
                              label: const Text('Add Video'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                                foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (_selectedImages.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('Selected Images:', style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _selectedImages.asMap().entries.map((entry) {
                            final index = entry.key;
                            final image = entry.value;
                            return Stack(
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Image.file(
                                    image,
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    onTap: () {
                                      if (mounted) {
                                        setState(() {
                                          _selectedImages.removeAt(index);
                                        });
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.error,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ],

                      if (_selectedVideos.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('Selected Videos:', style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
                        const SizedBox(height: 8),
                        Column(
                          children: _selectedVideos.asMap().entries.map((entry) {
                            final index = entry.key;
                            final video = entry.value;
                            return Card(
                              color: Theme.of(context).colorScheme.surfaceContainer,
                              child: ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(Icons.videocam, color: Theme.of(context).colorScheme.secondary),
                                ),
                                title: Text(
                                  video.path.split('/').last,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                                ),
                                subtitle: Text(
                                  'Video',
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                                trailing: IconButton(
                                  icon: Icon(Icons.close, color: Theme.of(context).colorScheme.error),
                                  onPressed: () {
                                    if (mounted) {
                                      setState(() {
                                        _selectedVideos.removeAt(index);
                                      });
                                    }
                                  },
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitDiary,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Create Diary', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_isLoading || _uploadingMedia)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      _uploadingMedia ? 'Uploading media...' : 'Creating diary...',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }
}