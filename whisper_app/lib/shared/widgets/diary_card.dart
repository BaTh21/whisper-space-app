// lib/shared/widgets/diary_card.dart
import 'package:flutter/material.dart';
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';
import 'package:whisper_space_flutter/shared/widgets/media_gallery.dart';

class DiaryCard extends StatefulWidget {
  final DiaryModel diary;
  final VoidCallback onLike;
  final VoidCallback onFavorite;
  final Function(int, String)
      onComment; // Changed to accept diaryId and content
  final Function(DiaryModel) onEdit;
  final Function(int) onDelete;
  final bool isOwner;

  const DiaryCard({
    super.key,
    required this.diary,
    required this.onLike,
    required this.onFavorite,
    required this.onComment,
    required this.onEdit,
    required this.onDelete,
    required this.isOwner,
  });

  @override
  State<DiaryCard> createState() => _DiaryCardState();
}

class _DiaryCardState extends State<DiaryCard> {
  bool _showFullContent = false;
  bool _isMenuDisabled = false;
  final TextEditingController _commentController = TextEditingController();
  bool _isCommenting = false;
  bool _showCommentMenu = false;
  int? _selectedCommentId;

  @override
  Widget build(BuildContext context) {
    final isLikedByCurrentUser =
        widget.diary.likes.any((like) => like.user.id == _getCurrentUserId());
    final isFavoritedByCurrentUser =
        widget.diary.favoritedUserIds.contains(_getCurrentUserId());

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
              // Header with Menu
              _buildHeader(),

              const SizedBox(height: 16),

              // Title
              if (widget.diary.title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    widget.diary.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),

              // Content
              if (widget.diary.content.isNotEmpty) _buildContent(),

              // Media Gallery
              if (widget.diary.images.isNotEmpty ||
                  widget.diary.videos.isNotEmpty)
                Column(
                  children: [
                    const SizedBox(height: 12),
                    MediaGallery(
                      images: widget.diary.images,
                      videos: widget.diary.videos,
                      videoThumbnails: widget.diary.videoThumbnails,
                      height: 250,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ],
                ),

              // Divider
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // Actions
              _buildActionButtons(
                isLikedByCurrentUser: isLikedByCurrentUser,
                isFavoritedByCurrentUser: isFavoritedByCurrentUser,
              ),

              // Comments Preview
              if (widget.diary.comments.isNotEmpty) _buildCommentsPreview(),

              // Comment Input
              if (_isCommenting) _buildCommentInput(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        CircleAvatar(
          backgroundImage: widget.diary.author.avatarUrl != null &&
                  widget.diary.author.avatarUrl!.isNotEmpty
              ? NetworkImage(widget.diary.author.avatarUrl!)
              : null,
          radius: 22,
          child: widget.diary.author.avatarUrl == null ||
                  widget.diary.author.avatarUrl!.isEmpty
              ? Text(
                  widget.diary.author.username.isNotEmpty
                      ? widget.diary.author.username[0].toUpperCase()
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
                widget.diary.author.username,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                _formatDate(widget.diary.createdAt),
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          onSelected: (value) {
            if (_isMenuDisabled) return; // Prevent multiple clicks
            _handleMenuSelection(value);
          },
          itemBuilder: (context) => [
            if (widget.isOwner && !_isMenuDisabled)
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    const Icon(Icons.edit, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text('Edit', style: TextStyle(color: Colors.blue[700])),
                  ],
                ),
              ),
            if (widget.isOwner && !_isMenuDisabled)
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete, size: 20, color: Colors.red),
                    const SizedBox(width: 8),
                    const Text('Delete', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            if (!_isMenuDisabled)
              PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    const Icon(Icons.share, size: 20, color: Colors.green),
                    const SizedBox(width: 8),
                    Text('Share', style: TextStyle(color: Colors.green[700])),
                  ],
                ),
              ),
            if (!_isMenuDisabled)
              PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    const Icon(Icons.report, size: 20, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text('Report', style: TextStyle(color: Colors.orange[700])),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _showFullContent || widget.diary.content.length < 200
                ? widget.diary.content
                : '${widget.diary.content.substring(0, 200)}...',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
          if (widget.diary.content.length > 200)
            GestureDetector(
              onTap: () {
                setState(() {
                  _showFullContent = !_showFullContent;
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _showFullContent ? 'Show less' : 'Show more',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons({
    required bool isLikedByCurrentUser,
    required bool isFavoritedByCurrentUser,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Like Button
        Expanded(
          child: _buildActionButton(
            icon: isLikedByCurrentUser ? Icons.favorite : Icons.favorite_border,
            label: 'Like',
            count: widget.diary.likes.length,
            onPressed: widget.onLike,
            isActive: isLikedByCurrentUser,
            activeColor: Colors.red,
          ),
        ),

        // Comment Button
        Expanded(
          child: _buildActionButton(
            icon: Icons.comment_outlined,
            label: 'Comment',
            count: widget.diary.comments.length,
            onPressed: () {
              setState(() {
                _isCommenting = !_isCommenting;
                if (!_isCommenting) {
                  _commentController.clear();
                }
              });
            },
            isActive: _isCommenting,
            activeColor: Colors.blue,
          ),
        ),

        // Save/Favorite Button
        Expanded(
          child: _buildActionButton(
            icon: isFavoritedByCurrentUser
                ? Icons.bookmark
                : Icons.bookmark_border,
            label: 'Save',
            count: 0,
            onPressed: widget.onFavorite,
            isActive: isFavoritedByCurrentUser,
            activeColor: Colors.amber,
          ),
        ),

        // Share Button
        Expanded(
          child: _buildActionButton(
            icon: Icons.share_outlined,
            label: 'Share',
            count: 0,
            onPressed: _shareDiary,
            isActive: false,
            activeColor: Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required int count,
    required VoidCallback onPressed,
    required bool isActive,
    required Color activeColor,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive ? activeColor : Colors.grey[600],
                ),
                if (count > 0)
                  Positioned(
                    top: -5,
                    right: -5,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: activeColor,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        count > 99 ? '99+' : count.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isActive ? activeColor : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentsPreview() {
    final previewComments = widget.diary.comments.length > 2
        ? widget.diary.comments.take(2).toList()
        : widget.diary.comments;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.diary.comments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => _viewAllComments(),
                child: Text(
                  'View all ${widget.diary.comments.length} comments',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ...previewComments.map((comment) => _buildCommentItem(comment)),
        ],
      ),
    );
  }

  Widget _buildCommentItem(Comment comment) {
    final isCurrentUser = comment.user.id == _getCurrentUserId();

    return GestureDetector(
      onLongPress: () {
        setState(() {
          _selectedCommentId = comment.id;
          _showCommentMenu = true;
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundImage: comment.user.avatarUrl != null &&
                      comment.user.avatarUrl!.isNotEmpty
                  ? NetworkImage(comment.user.avatarUrl!)
                  : null,
              child: comment.user.avatarUrl == null ||
                      comment.user.avatarUrl!.isEmpty
                  ? Text(
                      comment.user.username.isNotEmpty
                          ? comment.user.username[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 10),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          comment.user.username,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          comment.content,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Row(
                      children: [
                        Text(
                          _formatDate(comment.createdAt),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => _replyToComment(comment.id),
                          child: const Text(
                            'Reply',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => _editComment(comment),
                            child: const Text(
                              'Edit',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => _deleteComment(comment.id),
                            child: const Text(
                              'Delete',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ],
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

  Widget _buildCommentInput() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              decoration: InputDecoration(
                hintText: 'Write a comment...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              maxLines: 3,
              minLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _submitComment,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'edit':
        widget.onEdit(widget.diary);
        break;
      case 'delete':
        _showDeleteConfirmation();
        break;
      case 'share':
        _shareDiary();
        break;
      case 'report':
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Report Diary'),
            content: const Text('Why are you reporting this diary?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Thank you for your report. We will review it shortly.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                child: const Text('Submit Report'),
              ),
            ],
          ),
        );
        break;
    }
  }

  void _showDeleteConfirmation() {
    bool isDeleting = false; // Add flag to prevent multiple clicks

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Delete Diary'),
            content: const Text(
                'Are you sure you want to delete this diary? This action cannot be undone.'),
            actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: isDeleting
                    ? null
                    : () async {
                        setState(() => isDeleting = true);
                        await Future.delayed(const Duration(milliseconds: 50));
                        if (context.mounted) {
                          Navigator.pop(context); // Close dialog
                          widget.onDelete(widget.diary.id); // Trigger delete
                        }
                      },
                child: isDeleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _shareDiary() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share Diary'),
        content: const Text('Copy link to share this diary:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Link copied to clipboard!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Copy Link'),
          ),
        ],
      ),
    );
  }

  void _viewAllComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Comments',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: widget.diary.comments.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.comment, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No comments yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                'Be the first to comment!',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: widget.diary.comments.length,
                          itemBuilder: (context, index) {
                            final comment = widget.diary.comments[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildCommentItem(comment),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _replyToComment(int commentId) {
    setState(() {
      _isCommenting = true;
      _commentController.text = '@reply ';
      _commentController.selection = TextSelection.fromPosition(
        TextPosition(offset: _commentController.text.length),
      );
    });
  }

  void _editComment(Comment comment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Comment'),
        content: TextField(
          controller: TextEditingController(text: comment.content),
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Edit your comment...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              // TODO: Implement comment update
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Comment updated!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteComment(int commentId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Comment'),
        content: const Text('Are you sure you want to delete this comment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              // TODO: Implement comment deletion
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Comment deleted!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _submitComment() {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    widget.onComment(widget.diary.id, content);

    setState(() {
      _commentController.clear();
      _isCommenting = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Comment posted!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  int _getCurrentUserId() {
    // TODO: Get from your AuthProvider or UserProvider
    // This should return the actual current user ID
    return 1; // Replace with actual user ID
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

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }
}
