// lib/features/feed/presentation/providers/feed_provider.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:whisper_space_flutter/core/services/websocket_manager.dart';
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';
import 'package:whisper_space_flutter/features/feed/data/datasources/feed_api_service.dart';

class FeedProvider with ChangeNotifier {
  final FeedApiService feedApiService;
  final WebSocketManager _wsManager = WebSocketManager();
  
  List<DiaryModel> _diaries = [];
  List<DiaryModel> _myDiaries = [];
  bool _isLoading = false;
  String? _error;
  bool _isWsConnected = false;
  bool _isWsConnecting = false;
  
  List<DiaryModel> get diaries => _diaries;
  List<DiaryModel> get myDiaries => _myDiaries;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get myDiariesCount => _myDiaries.length;
  bool get isWsConnected => _isWsConnected;
  bool get isWsConnecting => _isWsConnecting;

  // Stream subscriptions
  StreamSubscription<DiaryModel>? _diarySubscription;
  StreamSubscription<Map<String, dynamic>>? _likeSubscription;
  StreamSubscription<Map<String, dynamic>>? _commentSubscription;
  StreamSubscription<Map<String, dynamic>>? _deleteSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  // Store current user ID (to be set from auth)
  int _currentUserId = 0;

  FeedProvider({required this.feedApiService}) {
    _initWebSocket();
  }

  void setCurrentUserId(int userId) {
    _currentUserId = userId;
  }

  void _initWebSocket() {
    // Listen for connection state
    _connectionSubscription = _wsManager.connectionState.listen((isConnected) {
      _isWsConnected = isConnected;
      notifyListeners();
    });

    // Check connecting state periodically
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_wsManager.isConnecting != _isWsConnecting) {
        _isWsConnecting = _wsManager.isConnecting;
        notifyListeners();
      }
    });

    // Listen for new diaries
    _diarySubscription = _wsManager.diaryUpdates.listen((newDiary) {
      _handleIncomingDiary(newDiary);
    });

    // Listen for likes
    _likeSubscription = _wsManager.likeUpdates.listen((likeData) {
      _handleIncomingLike(likeData);
    });

    // Listen for comments
    _commentSubscription = _wsManager.commentUpdates.listen((commentData) {
      _handleIncomingComment(commentData);
    });

    // Listen for deletions
    _deleteSubscription = _wsManager.deleteUpdates.listen((deleteData) {
      _handleIncomingDelete(deleteData);
    });

    // Connect to WebSocket
    _wsManager.connect();
  }

  void _handleIncomingDiary(DiaryModel newDiary) {
    // Check if diary should be shown
    if (_shouldShowDiary(newDiary)) {
      // Avoid duplicates
      final existingIndex = _diaries.indexWhere((d) => d.id == newDiary.id);
      if (existingIndex == -1) {
        _diaries.insert(0, newDiary);
        
        // If it's user's own diary, add to myDiaries too
        if (newDiary.author.id == _currentUserId) {
          final myExistingIndex = _myDiaries.indexWhere((d) => d.id == newDiary.id);
          if (myExistingIndex == -1) {
            _myDiaries.insert(0, newDiary);
          }
        }
        
        notifyListeners();
      }
    }
  }

  void _handleIncomingLike(Map<String, dynamic> likeData) {
    final diaryId = likeData['diary_id'];
    final userId = likeData['user_id'];
    final username = likeData['user_username'] ?? 'Unknown';
    final action = likeData['action'] ?? 'add';
    final userAvatarUrl = likeData['user_avatar_url'];
    
    // Update in diaries list
    final diaryIndex = _diaries.indexWhere((d) => d.id == diaryId);
    if (diaryIndex != -1) {
      final diary = _diaries[diaryIndex];
      
      if (action == 'add') {
        // Check if user already liked
        final existingLikeIndex = diary.likes.indexWhere((like) => like.user.id == userId);
        if (existingLikeIndex == -1) {
          final newLike = DiaryLike(
            id: DateTime.now().millisecondsSinceEpoch,
            user: Author(
              id: userId,
              username: username,
              avatarUrl: userAvatarUrl,
            ),
          );
          
          final updatedLikes = List<DiaryLike>.from(diary.likes)..add(newLike);
          final updatedDiary = _createUpdatedDiary(diary, likes: updatedLikes);
          _diaries[diaryIndex] = updatedDiary;
          notifyListeners();
        }
      } else if (action == 'remove') {
        final updatedLikes = List<DiaryLike>.from(diary.likes)
          ..removeWhere((like) => like.user.id == userId);
        final updatedDiary = _createUpdatedDiary(diary, likes: updatedLikes);
        _diaries[diaryIndex] = updatedDiary;
        notifyListeners();
      }
    }
    
    // Update in myDiaries list
    final myDiaryIndex = _myDiaries.indexWhere((d) => d.id == diaryId);
    if (myDiaryIndex != -1) {
      final diary = _myDiaries[myDiaryIndex];
      
      if (action == 'add') {
        final existingLikeIndex = diary.likes.indexWhere((like) => like.user.id == userId);
        if (existingLikeIndex == -1) {
          final newLike = DiaryLike(
            id: DateTime.now().millisecondsSinceEpoch,
            user: Author(
              id: userId,
              username: username,
              avatarUrl: userAvatarUrl,
            ),
          );
          
          final updatedLikes = List<DiaryLike>.from(diary.likes)..add(newLike);
          final updatedDiary = _createUpdatedDiary(diary, likes: updatedLikes);
          _myDiaries[myDiaryIndex] = updatedDiary;
          notifyListeners();
        }
      } else if (action == 'remove') {
        final updatedLikes = List<DiaryLike>.from(diary.likes)
          ..removeWhere((like) => like.user.id == userId);
        final updatedDiary = _createUpdatedDiary(diary, likes: updatedLikes);
        _myDiaries[myDiaryIndex] = updatedDiary;
        notifyListeners();
      }
    }
  }

  void _handleIncomingComment(Map<String, dynamic> commentData) {
    final diaryId = commentData['diary_id'];
    final commentMap = commentData['comment'];
    final action = commentData['action'] ?? 'add';
    final commentId = commentData['comment_id'];
    
    try {
      if (action == 'add' || action == 'update') {
        final comment = Comment.fromJson(commentMap);
        
        // Update in diaries list
        final diaryIndex = _diaries.indexWhere((d) => d.id == diaryId);
        if (diaryIndex != -1) {
          final diary = _diaries[diaryIndex];
          final comments = List<Comment>.from(diary.comments);
          
          if (action == 'add') {
            comments.add(comment);
          } else if (action == 'update') {
            final commentIndex = comments.indexWhere((c) => c.id == commentId);
            if (commentIndex != -1) {
              comments[commentIndex] = comment;
            } else {
              _updateCommentInReplies(comments, commentId, comment);
            }
          }
          
          final updatedDiary = _createUpdatedDiary(diary, comments: comments);
          _diaries[diaryIndex] = updatedDiary;
          notifyListeners();
        }
        
        // Update in myDiaries list
        final myDiaryIndex = _myDiaries.indexWhere((d) => d.id == diaryId);
        if (myDiaryIndex != -1) {
          final diary = _myDiaries[myDiaryIndex];
          final comments = List<Comment>.from(diary.comments);
          
          if (action == 'add') {
            comments.add(comment);
          } else if (action == 'update') {
            final commentIndex = comments.indexWhere((c) => c.id == commentId);
            if (commentIndex != -1) {
              comments[commentIndex] = comment;
            } else {
              _updateCommentInReplies(comments, commentId, comment);
            }
          }
          
          final updatedDiary = _createUpdatedDiary(diary, comments: comments);
          _myDiaries[myDiaryIndex] = updatedDiary;
          notifyListeners();
        }
      } else if (action == 'delete') {
        _deleteCommentFromDiaries(diaryId, commentId);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling incoming comment: $e');
      }
    }
  }

  void _updateCommentInReplies(List<Comment> comments, int commentId, Comment updatedComment) {
    for (int i = 0; i < comments.length; i++) {
      if (comments[i].id == commentId) {
        comments[i] = updatedComment;
        return;
      }
      if (comments[i].replies.isNotEmpty) {
        _updateCommentInReplies(comments[i].replies, commentId, updatedComment);
      }
    }
  }

  void _deleteCommentFromDiaries(int diaryId, int commentId) {
    // Update in diaries list
    final diaryIndex = _diaries.indexWhere((d) => d.id == diaryId);
    if (diaryIndex != -1) {
      final diary = _diaries[diaryIndex];
      final comments = List<Comment>.from(diary.comments);
      final updatedComments = _removeCommentById(comments, commentId);
      final updatedDiary = _createUpdatedDiary(diary, comments: updatedComments);
      _diaries[diaryIndex] = updatedDiary;
      notifyListeners();
    }
    
    // Update in myDiaries list
    final myDiaryIndex = _myDiaries.indexWhere((d) => d.id == diaryId);
    if (myDiaryIndex != -1) {
      final diary = _myDiaries[myDiaryIndex];
      final comments = List<Comment>.from(diary.comments);
      final updatedComments = _removeCommentById(comments, commentId);
      final updatedDiary = _createUpdatedDiary(diary, comments: updatedComments);
      _myDiaries[myDiaryIndex] = updatedDiary;
      notifyListeners();
    }
  }

  List<Comment> _removeCommentById(List<Comment> comments, int commentId) {
    final updatedComments = <Comment>[];
    for (final comment in comments) {
      if (comment.id != commentId) {
        final updatedReplies = _removeCommentById(comment.replies, commentId);
        updatedComments.add(Comment(
          id: comment.id,
          diaryId: comment.diaryId,
          content: comment.content,
          createdAt: comment.createdAt,
          user: comment.user,
          images: comment.images,
          parentId: comment.parentId,
          replies: updatedReplies,
        ));
      }
    }
    return updatedComments;
  }

  void _handleIncomingDelete(Map<String, dynamic> deleteData) {
    final diaryId = deleteData['diary_id'];
    
    _diaries.removeWhere((d) => d.id == diaryId);
    _myDiaries.removeWhere((d) => d.id == diaryId);
    notifyListeners();
  }

  bool _shouldShowDiary(DiaryModel diary) {
    if (diary.author.id == _currentUserId) return true;
    
    switch (diary.shareType) {
      case 'public':
        return true;
      case 'friends':
        // TODO: Implement friendship check when you have friend system
        return true;
      case 'group':
        if (diary.groups.isNotEmpty) {
          // TODO: Implement group membership check
          return true;
        }
        return false;
      case 'private':
      default:
        return false;
    }
  }

  DiaryModel _createUpdatedDiary(
    DiaryModel diary, {
    String? title,
    String? content,
    String? shareType,
    List<Group>? groups,
    List<String>? images,
    List<String>? videos,
    List<String>? videoThumbnails,
    String? mediaType,
    List<DiaryLike>? likes,
    bool? isDeleted,
    DateTime? updatedAt,
    List<int>? favoritedUserIds,
    List<Comment>? comments,
  }) {
    return DiaryModel(
      id: diary.id,
      author: diary.author,
      title: title ?? diary.title,
      content: content ?? diary.content,
      shareType: shareType ?? diary.shareType,
      groups: groups ?? diary.groups,
      images: images ?? diary.images,
      videos: videos ?? diary.videos,
      videoThumbnails: videoThumbnails ?? diary.videoThumbnails,
      mediaType: mediaType ?? diary.mediaType,
      likes: likes ?? diary.likes,
      isDeleted: isDeleted ?? diary.isDeleted,
      createdAt: diary.createdAt,
      updatedAt: updatedAt ?? diary.updatedAt,
      favoritedUserIds: favoritedUserIds ?? diary.favoritedUserIds,
      comments: comments ?? diary.comments,
    );
  }

  Future<void> reconnectWebSocket() async {
    await _wsManager.disconnect();
    _wsManager.connect();
  }

  Future<void> loadInitialFeed() async {
    await loadFeed(refresh: true);
  }

  Future<void> loadFeed({bool refresh = false}) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();
      
      final newDiaries = await feedApiService.getFeed();
      
      if (refresh) {
        _diaries = newDiaries;
      } else {
        final existingIds = _diaries.map((d) => d.id).toSet();
        for (final diary in newDiaries) {
          if (!existingIds.contains(diary.id)) {
            _diaries.add(diary);
          }
        }
      }
      
      _isLoading = false;
      notifyListeners();
      
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to load feed: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> refreshFeed() async {
    await loadFeed(refresh: true);
  }

  Future<void> loadMoreFeed() async {
    if (_isLoading) return;
    await loadFeed();
  }

  Future<void> loadMyDiaries() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();
      
      _myDiaries = await feedApiService.getMyFeed();
      
      _isLoading = false;
      notifyListeners();
      
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to load my diaries: $e';
      notifyListeners();
    }
  }

  Future<DiaryModel> createDiary({
    required String title,
    required String content,
    String shareType = 'private',
    List<int>? groupIds,
    List<String>? imageUrls,
    List<String>? videoUrls,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final newDiary = await feedApiService.createDiary(
        title: title,
        content: content,
        shareType: shareType,
        groupIds: groupIds,
        imageUrls: imageUrls,
        videoUrls: videoUrls,
      );
      
      _diaries.insert(0, newDiary);
      _myDiaries.insert(0, newDiary);
      
      _isLoading = false;
      notifyListeners();
      
      return newDiary;
      
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to create diary: $e';
      notifyListeners();
      rethrow;
    }
  }

  // ============ COMMENT FUNCTIONALITY ============
  Future<Comment> createComment({
    required int diaryId,
    required String content,
    int? parentId,
    List<String>? images,
  }) async {
    try {
      final comment = await feedApiService.createComment(
        diaryId: diaryId,
        content: content,
        parentId: parentId,
        images: images,
      );
      
      final diaryIndex = _diaries.indexWhere((d) => d.id == diaryId);
      if (diaryIndex != -1) {
        final diary = _diaries[diaryIndex];
        final comments = List<Comment>.from(diary.comments);
        
        if (parentId == null) {
          comments.add(comment);
        } else {
          _addCommentToReplies(comments, parentId, comment);
        }
        
        final updatedDiary = _createUpdatedDiary(diary, comments: comments);
        _diaries[diaryIndex] = updatedDiary;
        notifyListeners();
      }
      
      final myDiaryIndex = _myDiaries.indexWhere((d) => d.id == diaryId);
      if (myDiaryIndex != -1) {
        final diary = _myDiaries[myDiaryIndex];
        final comments = List<Comment>.from(diary.comments);
        
        if (parentId == null) {
          comments.add(comment);
        } else {
          _addCommentToReplies(comments, parentId, comment);
        }
        
        final updatedDiary = _createUpdatedDiary(diary, comments: comments);
        _myDiaries[myDiaryIndex] = updatedDiary;
        notifyListeners();
      }
      
      return comment;
    } catch (e) {
      rethrow;
    }
  }

  void _addCommentToReplies(List<Comment> comments, int parentId, Comment newComment) {
    for (int i = 0; i < comments.length; i++) {
      if (comments[i].id == parentId) {
        final updatedReplies = List<Comment>.from(comments[i].replies)..add(newComment);
        comments[i] = Comment(
          id: comments[i].id,
          diaryId: comments[i].diaryId,
          content: comments[i].content,
          createdAt: comments[i].createdAt,
          user: comments[i].user,
          images: comments[i].images,
          parentId: comments[i].parentId,
          replies: updatedReplies,
        );
        return;
      }
      if (comments[i].replies.isNotEmpty) {
        _addCommentToReplies(comments[i].replies, parentId, newComment);
      }
    }
  }

  Future<void> updateComment({
    required int commentId,
    required String content,
    List<String>? images,
  }) async {
    try {
      await feedApiService.updateComment(
        commentId: commentId,
        content: content,
        images: images,
      );
      
      _updateCommentInAllDiaries(commentId, content, images);
      
    } catch (e) {
      rethrow;
    }
  }

  void _updateCommentInAllDiaries(int commentId, String content, List<String>? images) {
    for (int i = 0; i < _diaries.length; i++) {
      final diary = _diaries[i];
      final comments = List<Comment>.from(diary.comments);
      final updatedComments = _updateCommentInList(comments, commentId, content, images);
      if (updatedComments != null) {
        final updatedDiary = _createUpdatedDiary(diary, comments: updatedComments);
        _diaries[i] = updatedDiary;
      }
    }
    
    for (int i = 0; i < _myDiaries.length; i++) {
      final diary = _myDiaries[i];
      final comments = List<Comment>.from(diary.comments);
      final updatedComments = _updateCommentInList(comments, commentId, content, images);
      if (updatedComments != null) {
        final updatedDiary = _createUpdatedDiary(diary, comments: updatedComments);
        _myDiaries[i] = updatedDiary;
      }
    }
    
    notifyListeners();
  }

  List<Comment>? _updateCommentInList(List<Comment> comments, int commentId, String content, List<String>? images) {
    for (int i = 0; i < comments.length; i++) {
      if (comments[i].id == commentId) {
        final updatedComment = Comment(
          id: commentId,
          diaryId: comments[i].diaryId,
          content: content,
          createdAt: comments[i].createdAt,
          user: comments[i].user,
          images: images ?? comments[i].images,
          parentId: comments[i].parentId,
          replies: comments[i].replies,
        );
        final updatedComments = List<Comment>.from(comments);
        updatedComments[i] = updatedComment;
        return updatedComments;
      }
      
      if (comments[i].replies.isNotEmpty) {
        final updatedReplies = _updateCommentInList(comments[i].replies, commentId, content, images);
        if (updatedReplies != null) {
          final updatedComment = Comment(
            id: comments[i].id,
            diaryId: comments[i].diaryId,
            content: comments[i].content,
            createdAt: comments[i].createdAt,
            user: comments[i].user,
            images: comments[i].images,
            parentId: comments[i].parentId,
            replies: updatedReplies,
          );
          final updatedComments = List<Comment>.from(comments);
          updatedComments[i] = updatedComment;
          return updatedComments;
        }
      }
    }
    return null;
  }

  Future<void> deleteComment(int commentId) async {
    try {
      await feedApiService.deleteComment(commentId);
      
      _deleteCommentFromAllDiaries(commentId);
      
    } catch (e) {
      rethrow;
    }
  }

  void _deleteCommentFromAllDiaries(int commentId) {
    for (int i = 0; i < _diaries.length; i++) {
      final diary = _diaries[i];
      final comments = List<Comment>.from(diary.comments);
      final updatedComments = _removeCommentFromList(comments, commentId);
      final updatedDiary = _createUpdatedDiary(diary, comments: updatedComments);
      _diaries[i] = updatedDiary;
    }
    
    for (int i = 0; i < _myDiaries.length; i++) {
      final diary = _myDiaries[i];
      final comments = List<Comment>.from(diary.comments);
      final updatedComments = _removeCommentFromList(comments, commentId);
      final updatedDiary = _createUpdatedDiary(diary, comments: updatedComments);
      _myDiaries[i] = updatedDiary;
    }
    
    notifyListeners();
  }

  List<Comment> _removeCommentFromList(List<Comment> comments, int commentId) {
    final updatedComments = <Comment>[];
    for (final comment in comments) {
      if (comment.id != commentId) {
        final updatedReplies = _removeCommentFromList(comment.replies, commentId);
        updatedComments.add(Comment(
          id: comment.id,
          diaryId: comment.diaryId,
          content: comment.content,
          createdAt: comment.createdAt,
          user: comment.user,
          images: comment.images,
          parentId: comment.parentId,
          replies: updatedReplies,
        ));
      }
    }
    return updatedComments;
  }

  // ============ DIARY UPDATE FUNCTIONALITY ============
  Future<DiaryModel> updateDiary({
    required int diaryId,
    String? title,
    String? content,
    String? shareType,
    List<int>? groupIds,
    List<String>? imageUrls,
    List<String>? videoUrls,
  }) async {
    try {
      final updatedDiary = await feedApiService.updateDiary(
        diaryId: diaryId,
        title: title,
        content: content,
        shareType: shareType,
        groupIds: groupIds,
        imageUrls: imageUrls,
        videoUrls: videoUrls,
      );
      
      final diaryIndex = _diaries.indexWhere((d) => d.id == diaryId);
      if (diaryIndex != -1) {
        _diaries[diaryIndex] = updatedDiary;
      }
      
      final myDiaryIndex = _myDiaries.indexWhere((d) => d.id == diaryId);
      if (myDiaryIndex != -1) {
        _myDiaries[myDiaryIndex] = updatedDiary;
      }
      
      notifyListeners();
      return updatedDiary;
      
    } catch (e) {
      rethrow;
    }
  }

  // ============ DIARY DELETE FUNCTIONALITY ============
  Future<void> deleteDiary(int diaryId) async {
    try {
      await feedApiService.deleteDiary(diaryId);
      
      _diaries.removeWhere((d) => d.id == diaryId);
      _myDiaries.removeWhere((d) => d.id == diaryId);
      
      notifyListeners();
      
    } catch (e) {
      rethrow;
    }
  }

  // ============ LIKE FUNCTIONALITY ============
  Future<void> likeDiary(int diaryId) async {
    try {
      await feedApiService.likeDiary(diaryId);
      
      final diaryIndex = _diaries.indexWhere((d) => d.id == diaryId);
      if (diaryIndex != -1) {
        final diary = _diaries[diaryIndex];
        
        final existingLikeIndex = diary.likes.indexWhere((like) => like.user.id == _currentUserId);
        if (existingLikeIndex == -1) {
          final newLike = DiaryLike(
            id: DateTime.now().millisecondsSinceEpoch,
            user: Author(
              id: _currentUserId,
              username: 'You',
              avatarUrl: null,
            ),
          );
          
          final updatedLikes = List<DiaryLike>.from(diary.likes)..add(newLike);
          final updatedDiary = _createUpdatedDiary(diary, likes: updatedLikes);
          _diaries[diaryIndex] = updatedDiary;
        } else {
          final updatedLikes = List<DiaryLike>.from(diary.likes)
            ..removeAt(existingLikeIndex);
          final updatedDiary = _createUpdatedDiary(diary, likes: updatedLikes);
          _diaries[diaryIndex] = updatedDiary;
        }
        notifyListeners();
      }
      
      final myDiaryIndex = _myDiaries.indexWhere((d) => d.id == diaryId);
      if (myDiaryIndex != -1) {
        final diary = _myDiaries[myDiaryIndex];
        
        final existingLikeIndex = diary.likes.indexWhere((like) => like.user.id == _currentUserId);
        if (existingLikeIndex == -1) {
          final newLike = DiaryLike(
            id: DateTime.now().millisecondsSinceEpoch,
            user: Author(
              id: _currentUserId,
              username: 'You',
              avatarUrl: null,
            ),
          );
          
          final updatedLikes = List<DiaryLike>.from(diary.likes)..add(newLike);
          final updatedDiary = _createUpdatedDiary(diary, likes: updatedLikes);
          _myDiaries[myDiaryIndex] = updatedDiary;
        } else {
          final updatedLikes = List<DiaryLike>.from(diary.likes)
            ..removeAt(existingLikeIndex);
          final updatedDiary = _createUpdatedDiary(diary, likes: updatedLikes);
          _myDiaries[myDiaryIndex] = updatedDiary;
        }
        notifyListeners();
      }
      
    } catch (e) {
      rethrow;
    }
  }

  Future<void> saveToFavorites(int diaryId) async {
    try {
      await feedApiService.saveToFavorites(diaryId);
      
      final diaryIndex = _diaries.indexWhere((d) => d.id == diaryId);
      if (diaryIndex != -1) {
        final diary = _diaries[diaryIndex];
        
        if (!diary.favoritedUserIds.contains(_currentUserId)) {
          final updatedFavorites = List<int>.from(diary.favoritedUserIds)..add(_currentUserId);
          final updatedDiary = _createUpdatedDiary(diary, favoritedUserIds: updatedFavorites);
          _diaries[diaryIndex] = updatedDiary;
          notifyListeners();
        }
      }
      
      final myDiaryIndex = _myDiaries.indexWhere((d) => d.id == diaryId);
      if (myDiaryIndex != -1) {
        final diary = _myDiaries[myDiaryIndex];
        
        if (!diary.favoritedUserIds.contains(_currentUserId)) {
          final updatedFavorites = List<int>.from(diary.favoritedUserIds)..add(_currentUserId);
          final updatedDiary = _createUpdatedDiary(diary, favoritedUserIds: updatedFavorites);
          _myDiaries[myDiaryIndex] = updatedDiary;
          notifyListeners();
        }
      }
      
    } catch (e) {
      rethrow;
    }
  }

  Future<void> removeFromFavorites(int diaryId) async {
    try {
      await feedApiService.removeFromFavorites(diaryId);
      
      final diaryIndex = _diaries.indexWhere((d) => d.id == diaryId);
      if (diaryIndex != -1) {
        final diary = _diaries[diaryIndex];
        
        if (diary.favoritedUserIds.contains(_currentUserId)) {
          final updatedFavorites = List<int>.from(diary.favoritedUserIds)..remove(_currentUserId);
          final updatedDiary = _createUpdatedDiary(diary, favoritedUserIds: updatedFavorites);
          _diaries[diaryIndex] = updatedDiary;
          notifyListeners();
        }
      }
      
      final myDiaryIndex = _myDiaries.indexWhere((d) => d.id == diaryId);
      if (myDiaryIndex != -1) {
        final diary = _myDiaries[myDiaryIndex];
        
        if (diary.favoritedUserIds.contains(_currentUserId)) {
          final updatedFavorites = List<int>.from(diary.favoritedUserIds)..remove(_currentUserId);
          final updatedDiary = _createUpdatedDiary(diary, favoritedUserIds: updatedFavorites);
          _myDiaries[myDiaryIndex] = updatedDiary;
          notifyListeners();
        }
      }
      
    } catch (e) {
      rethrow;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _diarySubscription?.cancel();
    _likeSubscription?.cancel();
    _commentSubscription?.cancel();
    _deleteSubscription?.cancel();
    _connectionSubscription?.cancel();
    _wsManager.dispose();
    super.dispose();
  }
}