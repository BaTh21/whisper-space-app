// lib/features/feed/presentation/screens/edit_diary_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';

class EditDiaryScreen extends StatefulWidget {
  final DiaryModel diary;
  final Function(DiaryModel) onUpdate;

  const EditDiaryScreen({
    super.key,
    required this.diary,
    required this.onUpdate,
  });

  @override
  State<EditDiaryScreen> createState() => _EditDiaryScreenState();
}

class _EditDiaryScreenState extends State<EditDiaryScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late String _shareType;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.diary.title);
    _contentController = TextEditingController(text: widget.diary.content);
    _shareType = widget.diary.shareType;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Diary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoading ? null : _saveChanges,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                    maxLength: 255,
                  ),
                  const SizedBox(height: 16),

                  // Content
                  TextFormField(
                    controller: _contentController,
                    decoration: const InputDecoration(
                      labelText: 'Content',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 10,
                    minLines: 5,
                  ),
                  const SizedBox(height: 16),

                  // Share Type
                  const Text('Privacy:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Column(
                    children: [
                      RadioListTile<String>(
                        title: const Text('Private'),
                        value: 'private',
                        groupValue: _shareType,
                        onChanged: (value) => setState(() => _shareType = value!),
                      ),
                      RadioListTile<String>(
                        title: const Text('Public'),
                        value: 'public',
                        groupValue: _shareType,
                        onChanged: (value) => setState(() => _shareType = value!),
                      ),
                      RadioListTile<String>(
                        title: const Text('Friends'),
                        value: 'friends',
                        groupValue: _shareType,
                        onChanged: (value) => setState(() => _shareType = value!),
                      ),
                    ],
                  ),

                  // Media Preview
                  if (widget.diary.images.isNotEmpty || widget.diary.videos.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        const Text('Current Media:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        // Show thumbnail preview of media
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ...widget.diary.images.map((image) => _buildMediaPreview(image, false)),
                            ...widget.diary.videos.map((video) => _buildMediaPreview(video, true)),
                          ],
                        ),
                      ],
                    ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildMediaPreview(String url, bool isVideo) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          if (isVideo)
            const Center(
              child: Icon(Icons.videocam, size: 32),
            )
          else
            // For images, you could show a thumbnail here
            const Center(
              child: Icon(Icons.image, size: 32),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () {
                // Handle media removal
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Remove Media'),
                    content: const Text('Are you sure you want to remove this media?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          // Implement media removal logic
                          Navigator.pop(context);
                        },
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
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
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (_titleController.text.trim().isEmpty ||
        _contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedDiary = DiaryModel(
        id: widget.diary.id,
        author: widget.diary.author,
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        shareType: _shareType,
        groups: widget.diary.groups,
        images: widget.diary.images,
        videos: widget.diary.videos,
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
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }
}