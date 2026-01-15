// lib/shared/widgets/diary_card.dart
import 'package:flutter/material.dart';
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';
import 'package:whisper_space_flutter/shared/widgets/media_gallery.dart';

class DiaryCard extends StatelessWidget {
  final DiaryModel diary;
  final VoidCallback onLike;
  final VoidCallback onFavorite;
  final VoidCallback onComment;

  const DiaryCard({
    super.key,
    required this.diary,
    required this.onLike,
    required this.onFavorite,
    required this.onComment,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  CircleAvatar(
                    backgroundImage: diary.author.avatarUrl != null &&
                            diary.author.avatarUrl!.isNotEmpty
                        ? NetworkImage(diary.author.avatarUrl!)
                        : null,
                    radius: 22,
                    child: diary.author.avatarUrl == null ||
                            diary.author.avatarUrl!.isEmpty
                        ? Text(
                            diary.author.username.isNotEmpty
                                ? diary.author.username[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          diary.author.username,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          _formatDate(diary.createdAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onPressed: () {},
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Title
              if (diary.title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    diary.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),

              // Content
              if (diary.content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    diary.content,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                ),

              // Media Gallery (UNIFIED - This is the ONLY media section)
              if (diary.images.isNotEmpty || diary.videos.isNotEmpty)
                Column(
                  children: [
                    MediaGallery(
                      images: diary.images,
                      videos: diary.videos,
                      videoThumbnails: diary.videoThumbnails,
                      height: 250,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),

              // Divider
              const Divider(height: 20),

              // Actions
              Row(
                children: [
                  _buildActionButton(
                    icon: diary.likes.isNotEmpty
                        ? Icons.favorite
                        : Icons.favorite_border,
                    count: diary.likes.length,
                    onPressed: onLike,
                    isActive: diary.likes.isNotEmpty,
                  ),
                  const SizedBox(width: 16),
                  _buildActionButton(
                    icon: Icons.comment_outlined,
                    count: diary.comments.length,
                    onPressed: onComment,
                    isActive: false,
                  ),
                  const Spacer(),
                  _buildActionButton(
                    icon: diary.favoritedUserIds.isNotEmpty
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    count: 0,
                    onPressed: onFavorite,
                    isActive: diary.favoritedUserIds.isNotEmpty,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required int count,
    required VoidCallback onPressed,
    required bool isActive,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isActive
              ? Colors.red.withOpacity(0.1)
              : Colors.grey.withOpacity(0.1),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? Colors.red : Colors.grey[600],
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isActive ? Colors.red : Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 365) {
      return '${difference.inDays ~/ 365}y ago';
    } else if (difference.inDays > 30) {
      return '${difference.inDays ~/ 30}mo ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
