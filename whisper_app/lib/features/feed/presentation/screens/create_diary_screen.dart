// lib/features/feed/presentation/screens/create_diary_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';
import 'package:whisper_space_flutter/features/feed/data/datasources/feed_api_service.dart';

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
  
  String _shareType = 'personal'; // Changed from 'private' to 'personal'
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
      setState(() {
        _availableGroups = groups;
      });
    } catch (e) {
      print('Failed to load groups: $e');
    } finally {
      setState(() => _loadingGroups = false);
    }
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile>? pickedFiles = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (pickedFiles != null && pickedFiles.isNotEmpty) {
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
      
      if (pickedFile != null) {
        final file = File(pickedFile.path);
        
        // Check file size (max 50MB)
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

    // Validate group selection if share type is 'group'
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

    setState(() => _isLoading = true);

    try {
      List<String> imageUrls = [];
      List<String> videoUrls = [];
      
      // Upload media if any
      if (_selectedImages.isNotEmpty || _selectedVideos.isNotEmpty) {
        setState(() => _uploadingMedia = true);
        
        // Upload images
        for (int i = 0; i < _selectedImages.length; i++) {
          final image = _selectedImages[i];
          try {
            final url = await widget.feedApiService.uploadMedia(image, isVideo: false);
            imageUrls.add(url);
          } catch (e) {
            print('Failed to upload image: $e');
            // Continue with other images
          }
        }
        
        // Upload videos
        for (int i = 0; i < _selectedVideos.length; i++) {
          final video = _selectedVideos[i];
          try {
            final url = await widget.feedApiService.uploadMedia(video, isVideo: true);
            videoUrls.add(url);
          } catch (e) {
            print('Failed to upload video: $e');
            // Continue with other videos
          }
        }
        
        setState(() => _uploadingMedia = false);
      }
      
      // Create diary - FIXED: _shareType is already 'personal' for private diaries
      final diary = await widget.feedApiService.createDiary(
        title: title,
        content: content,
        shareType: _shareType, // 'personal', 'public', 'friends', 'group'
        groupIds: _selectedGroupIds,
        imageUrls: imageUrls,
        videoUrls: videoUrls,
      );
      
      // Show success message
      _showSnackBar('✅ Diary created successfully!', isError: false);
      
      // Notify parent and close screen
      if (widget.onDiaryCreated != null) {
        widget.onDiaryCreated!(diary);
      }
      
      // Close the screen and return the created diary
      if (mounted) {
        Navigator.of(context).pop(diary);
      }
      
    } catch (e) {
      setState(() {
        _isLoading = false;
        _uploadingMedia = false;
      });
      
      print('Create diary error: $e');
      _showSnackBar('Failed to create diary: ${e.toString()}', isError: true);
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
            const Text(
              'Select Groups:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                const Text(
                  'No groups available',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Create a group first or join existing ones',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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
                    selectedColor: Colors.blue.shade100,
                    checkmarkColor: Colors.blue,
                    avatar: CircleAvatar(
                      backgroundColor: isSelected ? Colors.blue : Colors.grey.shade300,
                      radius: 12,
                      child: Text(
                        group.name.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected ? Colors.white : Colors.black,
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
                    color: Colors.green.shade700,
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
                      child: const Text(
                        'Discard',
                        style: TextStyle(color: Colors.red),
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
                  // Title
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      hintText: 'Give your diary a title',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
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
                  
                  // Content
                  TextFormField(
                    controller: _contentController,
                    decoration: const InputDecoration(
                      labelText: 'Content *',
                      hintText: 'Write your thoughts here...',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: Colors.white,
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
                  
                  // Share Type - UPDATED: Show "Private" but use value "personal"
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Privacy:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade50,
                        ),
                        child: Column(
                          children: [
                            RadioListTile<String>(
                              title: const Row(
                                children: [
                                  Icon(Icons.lock, size: 20, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Private'), // UI shows "Private"
                                ],
                              ),
                              subtitle: const Text('Only you can see this'),
                              value: 'personal', // But value is 'personal' for backend
                              groupValue: _shareType,
                              onChanged: _isLoading ? null : (value) {
                                setState(() {
                                  _shareType = value!;
                                  _showGroupSelection = false;
                                });
                              },
                            ),
                            Divider(height: 1, color: Colors.grey.shade300),
                            RadioListTile<String>(
                              title: const Row(
                                children: [
                                  Icon(Icons.public, size: 20, color: Colors.green),
                                  SizedBox(width: 8),
                                  Text('Public'),
                                ],
                              ),
                              subtitle: const Text('Everyone can see this'),
                              value: 'public',
                              groupValue: _shareType,
                              onChanged: _isLoading ? null : (value) {
                                setState(() {
                                  _shareType = value!;
                                  _showGroupSelection = false;
                                });
                              },
                            ),
                            Divider(height: 1, color: Colors.grey.shade300),
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
                              onChanged: _isLoading ? null : (value) {
                                setState(() {
                                  _shareType = value!;
                                  _showGroupSelection = false;
                                });
                              },
                            ),
                            Divider(height: 1, color: Colors.grey.shade300),
                            RadioListTile<String>(
                              title: const Row(
                                children: [
                                  Icon(Icons.group, size: 20, color: Colors.purple),
                                  SizedBox(width: 8),
                                  Text('Selected Groups'),
                                ],
                              ),
                              subtitle: const Text('Only selected groups can see this'),
                              value: 'group',
                              groupValue: _shareType,
                              onChanged: _isLoading ? null : (value) {
                                setState(() {
                                  _shareType = value!;
                                  _showGroupSelection = true;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  // Group Selection (only shown when 'group' is selected)
                  _buildGroupSelectionSection(),
                  
                  const SizedBox(height: 16),
                  
                  // Media Section
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Media (optional):',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      // Selected Images
                      if (_selectedImages.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text('Selected Images:', style: TextStyle(fontWeight: FontWeight.w500)),
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
                                    border: Border.all(color: Colors.grey.shade300),
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
                                      setState(() {
                                        _selectedImages.removeAt(index);
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
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
                      
                      // Selected Videos
                      if (_selectedVideos.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text('Selected Videos:', style: TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        Column(
                          children: _selectedVideos.asMap().entries.map((entry) {
                            final index = entry.key;
                            final video = entry.value;
                            return Card(
                              child: ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.videocam, color: Colors.green),
                                ),
                                title: Text(
                                  video.path.split('/').last,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  'Video',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.red),
                                  onPressed: () {
                                    setState(() {
                                      _selectedVideos.removeAt(index);
                                    });
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
                  
                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitDiary,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
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
          
          // Loading overlay
          if (_isLoading || _uploadingMedia)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
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