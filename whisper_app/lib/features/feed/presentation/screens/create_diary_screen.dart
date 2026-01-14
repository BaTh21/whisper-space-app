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
  
  String _shareType = 'private';
  final List<int> _selectedGroupIds = [];
  final List<File> _selectedImages = [];
  final List<File> _selectedVideos = [];
  
  bool _isLoading = false;
  bool _uploadingMedia = false;
  final ImagePicker _imagePicker = ImagePicker();

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

  setState(() => _isLoading = true);

  try {
    List<String> imageUrls = [];
    List<String> videoUrls = [];
    
    // Upload media if any
    if (_selectedImages.isNotEmpty || _selectedVideos.isNotEmpty) {
      _showSnackBar('Uploading media...', isError: false);
      
      // Upload images
      for (int i = 0; i < _selectedImages.length; i++) {
        final image = _selectedImages[i];
        setState(() => _uploadingMedia = true);
        try {
          _showSnackBar('Uploading image ${i + 1}/${_selectedImages.length}', isError: false);
          final url = await widget.feedApiService.uploadMedia(image, isVideo: false);
          imageUrls.add(url);
        } catch (e) {
          _showSnackBar('Failed to upload image ${i + 1}: $e', isError: true);
          // Continue with other images
        }
      }
      
      // Upload videos
      for (int i = 0; i < _selectedVideos.length; i++) {
        final video = _selectedVideos[i];
        setState(() => _uploadingMedia = true);
        try {
          _showSnackBar('Uploading video ${i + 1}/${_selectedVideos.length}', isError: false);
          final url = await widget.feedApiService.uploadMedia(video, isVideo: true);
          videoUrls.add(url);
        } catch (e) {
          _showSnackBar('Failed to upload video ${i + 1}: $e', isError: true);
          // Continue with other videos
        }
      }
    }
    
    // Create diary
    _showSnackBar('Creating diary...', isError: false);
    final diary = await widget.feedApiService.createDiary(
      title: title,
      content: content,
      shareType: _shareType,
      groupIds: _selectedGroupIds.isNotEmpty ? _selectedGroupIds : null,
      imageUrls: imageUrls.isNotEmpty ? imageUrls : null,
      videoUrls: videoUrls.isNotEmpty ? videoUrls : null,
    );
    
    _showSnackBar('✅ Diary created successfully!', isError: false);
    
    // Notify parent
    if (widget.onDiaryCreated != null) {
      widget.onDiaryCreated!(diary);
    }
    
    // Show success screen
    setState(() {
      _isLoading = false;
      _uploadingMedia = false;
    });
    
  } catch (e) {
    _showSnackBar('Failed to create diary: ${e.toString()}', isError: true);
    setState(() {
      _isLoading = false;
      _uploadingMedia = false;
    });
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
                  
                  // Share Type
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Privacy:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('Private'),
                              value: 'private',
                              groupValue: _shareType,
                              onChanged: _isLoading ? null : (value) {
                                setState(() => _shareType = value!);
                              },
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('Public'),
                              value: 'public',
                              groupValue: _shareType,
                              onChanged: _isLoading ? null : (value) {
                                setState(() => _shareType = value!);
                              },
                            ),
                          ),
                        ],
                      ),
                      RadioListTile<String>(
                        title: const Text('Friends'),
                        value: 'friends',
                        groupValue: _shareType,
                        onChanged: _isLoading ? null : (value) {
                          setState(() => _shareType = value!);
                        },
                      ),
                      RadioListTile<String>(
                        title: const Text('Group'),
                        value: 'group',
                        groupValue: _shareType,
                        onChanged: _isLoading ? null : (value) {
                          setState(() => _shareType = value!);
                        },
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Media Section
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Media (optional):', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : _pickImages,
                            icon: const Icon(Icons.photo),
                            label: const Text('Add Photos'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : _pickVideo,
                            icon: const Icon(Icons.videocam),
                            label: const Text('Add Video'),
                          ),
                        ],
                      ),
                      
                      // Selected Images
                      if (_selectedImages.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text('Selected Images:'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _selectedImages.asMap().entries.map((entry) {
                            final index = entry.key;
                            final image = entry.value;
                            return Stack(
                              children: [
                                Image.file(
                                  image,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
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
                                      color: Colors.red,
                                      child: const Icon(Icons.close, size: 16, color: Colors.white),
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
                        const Text('Selected Videos:'),
                        Column(
                          children: _selectedVideos.asMap().entries.map((entry) {
                            final index = entry.key;
                            final video = entry.value;
                            return ListTile(
                              leading: const Icon(Icons.videocam),
                              title: Text(video.path.split('/').last),
                              trailing: IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setState(() {
                                    _selectedVideos.removeAt(index);
                                  });
                                },
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