import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';
import 'package:whisper_space_flutter/features/feed/data/datasources/feed_api_service.dart';

class EditDiaryFullScreen extends StatefulWidget {
  final DiaryModel diary;
  final Function(DiaryModel) onUpdate;
  final List<Group> availableGroups;
  final FeedApiService? feedApiService;
  final Function(int)? onDelete;

  const EditDiaryFullScreen({
    super.key,
    required this.diary,
    required this.onUpdate,
    this.availableGroups = const [],
    this.feedApiService,
    this.onDelete,
  });

  @override
  State<EditDiaryFullScreen> createState() => _EditDiaryFullScreenState();
}

class _EditDiaryFullScreenState extends State<EditDiaryFullScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late String _shareType;
  bool _isLoading = false;
  
  List<String> _currentImages = [];
  List<String> _currentVideos = [];
  final List<File> _newImages = [];
  final List<File> _newVideos = [];
  
  List<int> _selectedGroupIds = [];
  final ImagePicker _picker = ImagePicker();
  
  List<Group> _availableGroups = [];
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.diary.title);
    _contentController = TextEditingController(text: widget.diary.content);
    _shareType = widget.diary.shareType;
    _currentImages = List.from(widget.diary.images);
    _currentVideos = List.from(widget.diary.videos);
    _selectedGroupIds = widget.diary.groups.map((g) => g.id).toList();
    _availableGroups = widget.availableGroups;
  }

  Future<void> _deleteDiary() async {
    if (_isDeleting || widget.feedApiService == null || widget.onDelete == null) {
      return;
    }
    
    final context = this.context;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Diary'),
        content: const Text('Are you sure you want to delete this diary? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              
              if (mounted) {
                setState(() => _isDeleting = true);
              }
              
              try {
                await widget.feedApiService!.deleteDiary(widget.diary.id);
                
                if (mounted) {
                  widget.onDelete!(widget.diary.id);
                  _showSnackBar('Diary deleted successfully!', false);
                  await Future.delayed(const Duration(milliseconds: 1500));
                  Navigator.pop(context, null);
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _isDeleting = false);
                  _showSnackBar('Failed to delete diary: $e', true);
                }
              }
            },
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Diary'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: (_isLoading || _isDeleting) ? null : () {
            if (_titleController.text != widget.diary.title || 
                _contentController.text != widget.diary.content ||
                _newImages.isNotEmpty ||
                _newVideos.isNotEmpty) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Discard Changes?'),
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
        actions: [
          if (widget.feedApiService != null && widget.onDelete != null)
            IconButton(
              icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              onPressed: (_isLoading || _isDeleting) ? null : _deleteDiary,
              tooltip: 'Delete Diary',
            ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Title *',
                    hintText: 'Give your diary a title',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  maxLength: 255,
                ),
                
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _contentController,
                  decoration: InputDecoration(
                    labelText: 'Content *',
                    hintText: 'Write your thoughts here...',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  maxLines: 8,
                  minLines: 4,
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
                          _buildPrivacyOption(
                            icon: Icons.lock,
                            iconColor: Theme.of(context).colorScheme.error,
                            title: 'Private',
                            subtitle: 'Only you can see this',
                            value: 'personal',
                          ),
                          Divider(height: 1, color: Theme.of(context).colorScheme.outline),
                          _buildPrivacyOption(
                            icon: Icons.public,
                            iconColor: Theme.of(context).colorScheme.secondary,
                            title: 'Public',
                            subtitle: 'Everyone can see this',
                            value: 'public',
                          ),
                          Divider(height: 1, color: Theme.of(context).colorScheme.outline),
                          _buildPrivacyOption(
                            icon: Icons.people,
                            iconColor: Theme.of(context).colorScheme.primary,
                            title: 'Friends Only',
                            subtitle: 'Only your friends can see this',
                            value: 'friends',
                          ),
                          Divider(height: 1, color: Theme.of(context).colorScheme.outline),
                          _buildPrivacyOption(
                            icon: Icons.group,
                            iconColor: Colors.deepPurple,
                            title: 'Selected Groups',
                            subtitle: 'Only selected groups can see this',
                            value: 'group',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                if (_availableGroups.isNotEmpty && _shareType == 'group')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Groups:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _availableGroups.map((group) {
                          final isSelected = _selectedGroupIds.contains(group.id);
                          return FilterChip(
                            label: Text(group.name),
                            selected: isSelected,
                            onSelected: (_isLoading || _isDeleting) ? null : (selected) {
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
                                  : Theme.of(context).colorScheme.surfaceVariant,
                              radius: 12,
                              child: Text(
                                group.name.substring(0, 1).toUpperCase(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected 
                                      ? Theme.of(context).colorScheme.onPrimary 
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
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
                
                const SizedBox(height: 16),
                
                if (_currentImages.isNotEmpty || _currentVideos.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Current Media:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text('${_currentImages.length + _currentVideos.length}'),
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      
                      if (_currentImages.isNotEmpty) ...[
                        Text('Images:', style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _currentImages.asMap().entries.map((entry) {
                            final index = entry.key;
                            final url = entry.value;
                            return _buildCurrentMediaItem(url, false, index);
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                      ],
                      
                      if (_currentVideos.isNotEmpty) ...[
                        Text('Videos:', style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _currentVideos.asMap().entries.map((entry) {
                            final index = entry.key;
                            final url = entry.value;
                            return _buildCurrentMediaItem(url, true, index);
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                
                const SizedBox(height: 16),
                
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add More Media (optional):',
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
                            onPressed: (_isLoading || _isDeleting) ? null : _pickImages,
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
                            onPressed: (_isLoading || _isDeleting) ? null : _pickVideos,
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
                    const SizedBox(height: 8),
                    Text(
                      'Max 10 images total, Max 3 videos total',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    
                    if (_newImages.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text('New Photos:', style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text('${_newImages.length}'),
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            side: BorderSide(color: Theme.of(context).colorScheme.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _newImages.asMap().entries.map((entry) {
                          final index = entry.key;
                          final file = entry.value;
                          return _buildNewMediaItem(file, false, index);
                        }).toList(),
                      ),
                    ],
                    
                    if (_newVideos.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text('New Videos:', style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text('${_newVideos.length}'),
                            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                            side: BorderSide(color: Theme.of(context).colorScheme.secondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _newVideos.asMap().entries.map((entry) {
                          final index = entry.key;
                          final file = entry.value;
                          return _buildNewMediaItem(file, true, index);
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
                    onPressed: (_isLoading || _isDeleting) ? null : _saveChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Update Diary', style: TextStyle(fontSize: 16)),
                  ),
                ),
                
                if (widget.feedApiService != null && widget.onDelete != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: (_isLoading || _isDeleting) ? null : _deleteDiary,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      ),
                      child: _isDeleting
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Delete Diary', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          if (_isLoading || _isDeleting)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Processing...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPrivacyOption({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String value,
  }) {
    return InkWell(
      onTap: (_isLoading || _isDeleting)
          ? null
          : () {
              setState(() => _shareType = value);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Radio<String>(
                        value: value,
                        groupValue: _shareType,
                        onChanged: (_isLoading || _isDeleting)
                            ? null
                            : (newValue) {
                                if (newValue != null) {
                                  setState(() => _shareType = newValue);
                                }
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentMediaItem(String url, bool isVideo, int index) {
    return Stack(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: isVideo
              ? Container(
                  color: Colors.grey.shade100,
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam, size: 24, color: Colors.grey),
                        SizedBox(height: 4),
                        Text('Video', style: TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                )
              : Image.network(
                  url,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey.shade100,
                      child: const Center(
                        child: Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    );
                  },
                ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            onTap: (_isLoading || _isDeleting) ? null : () => _removeMedia(url, isVideo),
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
  }

  Widget _buildNewMediaItem(File file, bool isVideo, int index) {
    return Stack(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            border: Border.all(color: isVideo ? Colors.green : Colors.blue),
            borderRadius: BorderRadius.circular(8),
            color: isVideo ? Colors.green.shade50 : Colors.blue.shade50,
          ),
          child: isVideo
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam, size: 24, color: Colors.green),
                      SizedBox(height: 4),
                      Text('Video', style: TextStyle(fontSize: 10)),
                    ],
                  ),
                )
              : Image.file(
                  file,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: isVideo ? Colors.green.shade50 : Colors.blue.shade50,
                      child: const Center(
                        child: Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    );
                  },
                ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            onTap: (_isLoading || _isDeleting) ? null : () => _removeNewMedia(file, isVideo),
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
  }

  Future<void> _pickImages() async {
    try {
      final pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (pickedFiles != null && pickedFiles.isNotEmpty) {
        setState(() {
          _newImages.addAll(pickedFiles.map((file) => File(file.path)));
        });
        _showSnackBar('Added ${pickedFiles.length} new photo(s)', false);
      }
    } catch (e) {
      _showSnackBar('Failed to pick images: $e', true);
    }
  }

  Future<void> _pickVideos() async {
    try {
      final pickedFile = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 10),
      );
      if (pickedFile != null) {
        setState(() {
          _newVideos.add(File(pickedFile.path));
        });
        _showSnackBar('Added video', false);
      }
    } catch (e) {
      _showSnackBar('Failed to pick video: $e', true);
    }
  }

  void _removeMedia(String url, bool isVideo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Media'),
        content: Text('Remove this ${isVideo ? 'video' : 'image'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                if (isVideo) {
                  _currentVideos.remove(url);
                } else {
                  _currentImages.remove(url);
                }
              });
              Navigator.pop(context);
              _showSnackBar('Removed ${isVideo ? 'video' : 'image'}', false);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _removeNewMedia(File file, bool isVideo) {
    setState(() {
      if (isVideo) {
        _newVideos.remove(file);
      } else {
        _newImages.remove(file);
      }
    });
    _showSnackBar('Removed new ${isVideo ? 'video' : 'image'}', false);
  }

  Future<void> _saveChanges() async {
    if (_titleController.text.trim().isEmpty) {
      _showSnackBar('Please enter a title', true);
      return;
    }

    if (_contentController.text.trim().isEmpty) {
      _showSnackBar('Please enter content', true);
      return;
    }

    if (_shareType == 'group' && _selectedGroupIds.isEmpty) {
      _showSnackBar('Please select at least one group', true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final groups = _availableGroups
          .where((group) => _selectedGroupIds.contains(group.id))
          .toList();

      final updatedDiary = DiaryModel(
        id: widget.diary.id,
        author: widget.diary.author,
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        shareType: _shareType,
        groups: groups,
        images: _currentImages,
        videos: _currentVideos,
        videoThumbnails: widget.diary.videoThumbnails,
        mediaType: widget.diary.mediaType,
        likes: widget.diary.likes,
        isDeleted: widget.diary.isDeleted,
        createdAt: widget.diary.createdAt,
        updatedAt: DateTime.now(),
        favoritedUserIds: widget.diary.favoritedUserIds,
        comments: widget.diary.comments,
      );

      await widget.onUpdate(updatedDiary);
      
      _showSnackBar('Diary updated successfully!', false);
      
      if (mounted) {
        Navigator.pop(context, updatedDiary);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _showSnackBar('Failed to save: $e', true);
    }
  }

  void _showSnackBar(String message, bool isError) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
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