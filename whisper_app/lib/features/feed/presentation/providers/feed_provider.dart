// lib/features/feed/presentation/providers/feed_provider.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';
import 'package:whisper_space_flutter/features/feed/data/datasources/feed_api_service.dart';

class FeedProvider with ChangeNotifier {
  final FeedApiService feedApiService;
  
  List<DiaryModel> _diaries = [];
  List<DiaryModel> _myDiaries = [];
  List<DiaryModel> _favoriteDiaries = [];
  bool _isLoading = false;
  String? _error;
  int _currentUserId = 0;
  
  // WebSocket related properties
  bool _isWsConnected = false;
  bool _isWsConnecting = false;
  
  List<DiaryModel> get diaries => _diaries;
  List<DiaryModel> get myDiaries => _myDiaries;
  List<DiaryModel> get favoriteDiaries => _favoriteDiaries;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isWsConnected => _isWsConnected;
  bool get isWsConnecting => _isWsConnecting;

  FeedProvider({required this.feedApiService});

  void setCurrentUserId(int userId) {
    _currentUserId = userId;
  }

  // ============ WEB SOCKET METHODS ============
  Future<void> reconnectWebSocket() async {
    // For now, just set connected state
    _isWsConnected = true;
    _isWsConnecting = false;
    notifyListeners();
    
    // TODO: Implement actual WebSocket reconnection
    // This is a placeholder for future WebSocket implementation
  }

  void _initWebSocket() {
    // TODO: Initialize WebSocket connection
    // This is a placeholder for future WebSocket implementation
    _isWsConnected = true;
    notifyListeners();
  }

  // ============ DIARY CRUD OPERATIONS ============
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

  Future<void> deleteDiary(int diaryId) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      await feedApiService.deleteDiary(diaryId);
      
      _diaries.removeWhere((d) => d.id == diaryId);
      _myDiaries.removeWhere((d) => d.id == diaryId);
      
      _isLoading = false;
      notifyListeners();
      
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to delete diary: $e';
      notifyListeners();
      rethrow;
    }
  }

  // ============ COMMENT OPERATIONS ============
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
        comments.add(comment);
        
        final updatedDiary = _createUpdatedDiary(diary, comments: comments);
        _diaries[diaryIndex] = updatedDiary;
        notifyListeners();
      }
      
      return comment;
    } catch (e) {
      rethrow;
    }
  }

  Future<Comment> updateComment({
    required int commentId,
    required String content,
    List<String>? images,
  }) async {
    try {
      final updatedComment = await feedApiService.updateComment(
        commentId: commentId,
        content: content,
        images: images,
      );
      
      for (int i = 0; i < _diaries.length; i++) {
        final diary = _diaries[i];
        final comments = List<Comment>.from(diary.comments);
        final updatedComments = _updateCommentInList(comments, updatedComment);
        if (updatedComments != null) {
          final updatedDiary = _createUpdatedDiary(diary, comments: updatedComments);
          _diaries[i] = updatedDiary;
          notifyListeners();
          break;
        }
      }
      
      return updatedComment;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteComment(int commentId) async {
    try {
      await feedApiService.deleteComment(commentId);
      
      for (int i = 0; i < _diaries.length; i++) {
        final diary = _diaries[i];
        final comments = List<Comment>.from(diary.comments);
        final updatedComments = _removeCommentById(comments, commentId);
        final updatedDiary = _createUpdatedDiary(diary, comments: updatedComments);
        _diaries[i] = updatedDiary;
      }
      
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  // ============ LIKE OPERATIONS ============
  Future<Map<String, dynamic>> likeDiary(int diaryId) async {
    try {
      final result = await feedApiService.likeDiary(diaryId);
      
      final diaryIndex = _diaries.indexWhere((d) => d.id == diaryId);
      if (diaryIndex != -1) {
        final diary = _diaries[diaryIndex];
        
        if (result['liked'] == true) {
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
            ..removeWhere((like) => like.user.id == _currentUserId);
          final updatedDiary = _createUpdatedDiary(diary, likes: updatedLikes);
          _diaries[diaryIndex] = updatedDiary;
        }
        notifyListeners();
      }
      
      return result;
    } catch (e) {
      rethrow;
    }
  }

  // ============ FAVORITE OPERATIONS ============
  Future<Map<String, dynamic>> saveToFavorites(int diaryId) async {
    try {
      final result = await feedApiService.saveToFavorites(diaryId);
      
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
      
      return result;
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
    } catch (e) {
      rethrow;
    }
  }

  Future<void> loadFavoriteDiaries() async {
    try {
      _isLoading = true;
      notifyListeners();
      
      _favoriteDiaries = await feedApiService.getFavoriteDiaries();
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to load favorite diaries: $e';
      notifyListeners();
    }
  }

  // ============ FEED OPERATIONS ============
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

  // ============ HELPER METHODS ============
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

  List<Comment>? _updateCommentInList(List<Comment> comments, Comment updatedComment) {
    for (int i = 0; i < comments.length; i++) {
      if (comments[i].id == updatedComment.id) {
        final updatedComments = List<Comment>.from(comments);
        updatedComments[i] = updatedComment;
        return updatedComments;
      }
      
      if (comments[i].replies.isNotEmpty) {
        final updatedReplies = _updateCommentInList(comments[i].replies, updatedComment);
        if (updatedReplies != null) {
          final updatedCommentWithReplies = Comment(
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
          updatedComments[i] = updatedCommentWithReplies;
          return updatedComments;
        }
      }
    }
    return null;
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

  void clearError() {
    _error = null;
    notifyListeners();
  }
}