// lib/shared/widgets/diary_card.dart - FINAL FIXED VERSION
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For copy to clipboard
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';
import 'package:whisper_space_flutter/shared/widgets/media_gallery.dart';

class DiaryCard extends StatefulWidget {
  final DiaryModel diary;
  final VoidCallback onLike;
  final VoidCallback onFavorite;
  final Function(int, String, int?, int?) onComment; // Updated to include reply_to_user_id
  final Function(DiaryModel) onEdit;
  final Function(int) onDelete;
  final Function(int, String, List<String>?)? onUpdateComment;
  final Function(int)? onDeleteComment;
  final bool isOwner;

  const DiaryCard({
    super.key,
    required this.diary,
    required this.onLike,
    required this.onFavorite,
    required this.onComment,
    required this.onEdit,
    required this.onDelete,
    this.onUpdateComment,
    this.onDeleteComment,
    required this.isOwner,
  });

  @override
  State<DiaryCard> createState() => _DiaryCardState();
}

class _DiaryCardState extends State<DiaryCard> {
  bool _showFullContent = false;
  final TextEditingController _commentController = TextEditingController();
  bool _isCommenting = false;
  bool _isSubmittingComment = false;
  int? _replyingToCommentId;
  int? _replyingToUserId;
  String? _replyingToUsername;
  final _commentFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _commentFocusNode.addListener(() {
      if (!_commentFocusNode.hasFocus) {
        // Clear reply state when focus is lost
        _clearReplyState();
      }
    });
  }

  void _clearReplyState() {
    if (_replyingToCommentId != null) {
      setState(() {
        _replyingToCommentId = null;
        _replyingToUserId = null;
        _replyingToUsername = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLikedByCurrentUser = widget.diary.likes.any((like) => like.user.id == _getCurrentUserId());
    final isFavoritedByCurrentUser = widget.diary.favoritedUserIds.contains(_getCurrentUserId());

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

              // Reply Indicator (if replying)
              if (_replyingToUsername != null) _buildReplyIndicator(),

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
          onSelected: _handleMenuSelection,
          itemBuilder: (context) {
            return [
              if (widget.isOwner)
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Edit', style: TextStyle(color: Colors.blue)),
                    ],
                  ),
                ),
              if (widget.isOwner)
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              const PopupMenuItem<String>(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share, size: 20, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Share', style: TextStyle(color: Colors.green)),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.report, size: 20, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Report', style: TextStyle(color: Colors.orange)),
                  ],
                ),
              ),
            ];
          },
        ),
      ],
    );
  }

  Widget _buildContent() {
    final textWithMentions = _parseMentions(widget.diary.content);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showFullContent || widget.diary.content.length < 200)
            RichText(
              text: textWithMentions,
              maxLines: _showFullContent ? null : 4,
              overflow: _showFullContent ? TextOverflow.visible : TextOverflow.ellipsis,
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: textWithMentions.children!.sublist(0, textWithMentions.children!.length > 1 ? 1 : 1),
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const Text('...'),
              ],
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
                  _clearReplyState();
                }
                if (_isCommenting) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    FocusScope.of(context).requestFocus(_commentFocusNode);
                  });
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

  Widget _buildReplyIndicator() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Replying to @$_replyingToUsername',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          GestureDetector(
            onTap: _clearReplyState,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.shade100,
              ),
              child: const Icon(
                Icons.close,
                size: 14,
                color: Colors.blue,
              ),
            ),
          ),
        ],
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
                onTap: _viewAllComments,
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
          ...previewComments.map((comment) => _buildCommentItem(comment, false)),
        ],
      ),
    );
  }

  Widget _buildCommentItem(Comment comment, bool isInModal) {
    final isCurrentUser = comment.user.id == _getCurrentUserId();
    final hasReplyTo = comment.replyToUser != null;
    final textWithMentions = _parseMentions(comment.content);

    return Padding(
      padding: EdgeInsets.only(bottom: isInModal ? 12 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: isInModal ? 16 : 14,
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
                        style: TextStyle(fontSize: isInModal ? 12 : 10),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Reply indicator (if this is a reply)
                    if (hasReplyTo)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.reply,
                              size: 12,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Replying to ${comment.replyToUser!.username}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Comment bubble
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
                          // User info
                          Row(
                            children: [
                              Text(
                                comment.user.username,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: isInModal ? 13 : 12,
                                ),
                              ),
                              if (comment.isEdited) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'edited',
                                    style: TextStyle(
                                      fontSize: 8,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          
                          // Comment content with mentions
                          const SizedBox(height: 2),
                          SelectableText.rich(
                            textWithMentions,
                            style: TextStyle(fontSize: isInModal ? 14 : 12),
                          ),
                          
                          // Images in comment
                          if (comment.images.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: SizedBox(
                                height: 80,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: comment.images.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    return ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        comment.images[index],
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 80,
                                          height: 80,
                                          color: Colors.grey.shade200,
                                          child: const Icon(Icons.broken_image),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    // Comment actions
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
                            onTap: () => _replyToComment(
                              comment.id,
                              comment.user.id,
                              comment.user.username,
                            ),
                            child: Text(
                              'Reply',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (isCurrentUser) ...[
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => _editComment(comment),
                              child: Text(
                                'Edit',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => _deleteComment(comment.id),
                              child: Text(
                                'Delete',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red.shade600,
                                  fontWeight: FontWeight.w500,
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
          
          // Nested replies
          if (comment.replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 8),
              child: Column(
                children: comment.replies.map((reply) => _buildCommentItem(reply, isInModal)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCommentInput() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mention hint
          if (_replyingToUsername == null)
            Container(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text(
                'Tip: Use @username to mention someone',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  focusNode: _commentFocusNode,
                  decoration: InputDecoration(
                    hintText: _replyingToUsername != null 
                        ? 'Reply to @$_replyingToUsername...' 
                        : 'Write a comment...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: _replyingToUsername != null
                        ? Colors.blue.shade50
                        : Colors.grey[100],
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    suffixIcon: _commentController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setState(() {
                                _commentController.clear();
                              });
                            },
                          )
                        : null,
                  ),
                  maxLines: 3,
                  minLines: 1,
                  onChanged: (value) {
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _submitComment,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _commentController.text.trim().isEmpty
                        ? Colors.grey.shade400
                        : Theme.of(context).primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: _isSubmittingComment
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 18,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  TextSpan _parseMentions(String text) {
    final mentionRegex = RegExp(r'@(\w+)');
    final parts = text.split(mentionRegex);
    final matches = mentionRegex.allMatches(text).toList();
    
    final spans = <TextSpan>[];
    
    for (int i = 0; i < parts.length; i++) {
      // Add the text part
      spans.add(TextSpan(
        text: parts[i],
        style: const TextStyle(color: Colors.black87),
      ));
      
      // Add the mention if it exists
      if (i < matches.length) {
        final mention = matches[i].group(0)!; // Includes @ symbol
        final username = matches[i].group(1)!; // Just the username
        
        // Use the username variable to avoid unused variable warning
        // In a real app, you might use this for tap handling
        if (username.isNotEmpty) {
          // Username is being used
        }
        
        spans.add(TextSpan(
          text: mention,
          style: const TextStyle(
            color: Colors.blue,
            fontWeight: FontWeight.w500,
          ),
        ));
      }
    }
    
    return TextSpan(children: spans);
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
        _reportDiary();
        break;
    }
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Diary'),
        content: const Text(
            'Are you sure you want to delete this diary? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete(widget.diary.id);
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
              Clipboard.setData(ClipboardData(
                text: 'https://whisperspace.app/diary/${widget.diary.id}',
              ));
              Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Link copied to clipboard!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Copy Link'),
          ),
        ],
      ),
    );
  }

  void _reportDiary() {
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
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Thank you for your report. We will review it shortly.'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Submit Report'),
          ),
        ],
      ),
    );
  }

void _submitComment() async {
  final content = _commentController.text.trim();
  if (content.isEmpty) return;

  try {
    setState(() => _isSubmittingComment = true);
    
    // Convert 0 to null for parent_id
    int? parentId = _replyingToCommentId;
    if (parentId == 0) {
      parentId = null;
    }
    
    // Convert 0 to null for reply_to_user_id
    int? replyToUserId = _replyingToUserId;
    if (replyToUserId == 0) {
      replyToUserId = null;
    }
    
    await widget.onComment(
      widget.diary.id, 
      content,
      parentId,
      replyToUserId,
    );
    
    if (mounted) {
      setState(() {
        _commentController.clear();
        _isCommenting = false;
        _isSubmittingComment = false;
        _clearReplyState();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comment posted!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      setState(() => _isSubmittingComment = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to post comment: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

  void _viewAllComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            // Draggable handle
            Container(
              margin: const EdgeInsets.only(top: 8),
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Header
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
                    
                    // Comments list
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
                              itemCount: widget.diary.comments.length,
                              itemBuilder: (context, index) {
                                final comment = widget.diary.comments[index];
                                return _buildCommentItem(comment, true);
                              },
                            ),
                    ),
                    
                    // Comment input in modal
                    Container(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: Column(
                        children: [
                          if (_replyingToUsername != null) _buildReplyIndicator(),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _commentController,
                                  decoration: InputDecoration(
                                    hintText: _replyingToUsername != null 
                                        ? 'Reply to @$_replyingToUsername...' 
                                        : 'Write a comment...',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                    fillColor: _replyingToUsername != null
                                        ? Colors.blue.shade50
                                        : Colors.grey[100],
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _replyToComment(int commentId, int userId, String username) {
    setState(() {
      _replyingToCommentId = commentId;
      _replyingToUserId = userId;
      _replyingToUsername = username;
      _isCommenting = true;
      _commentController.text = '@$username ';
      _commentController.selection = TextSelection.fromPosition(
        TextPosition(offset: _commentController.text.length),
      );
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_commentFocusNode);
    });
  }

  Future<void> _editComment(Comment comment) async {
    final controller = TextEditingController(text: comment.content);
    
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Comment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Edit your comment...',
                border: OutlineInputBorder(),
              ),
            ),
            if (comment.images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${comment.images.length} image(s) attached',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newContent = controller.text.trim();
              if (newContent.isNotEmpty) {
                Navigator.pop(context, {
                  'content': newContent,
                  'images': comment.images,
                });
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((result) async {
      if (result != null && mounted) {
        try {
          await widget.onUpdateComment?.call(
            comment.id,
            result['content']!,
            result['images'],
          );
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Comment updated!'),
              backgroundColor: Colors.green,
            ),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update comment: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
  }

  Future<void> _deleteComment(int commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Comment'),
        content: const Text('Are you sure you want to delete this comment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    
    if (confirmed == true && mounted) {
      try {
        await widget.onDeleteComment?.call(commentId);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comment deleted!'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete comment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  int _getCurrentUserId() {
    // TODO: Replace with actual user ID from AuthProvider
    return 0;
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
    _commentFocusNode.dispose();
    super.dispose();
  }
}