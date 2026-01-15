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

  FeedProvider({required this.feedApiService}) {
    _initWebSocket();
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
        final currentUserId = _getCurrentUserId();
        if (newDiary.author.id == currentUserId) {
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
    
    // Update in diaries list
    final diaryIndex = _diaries.indexWhere((d) => d.id == diaryId);
    if (diaryIndex != -1) {
      final diary = _diaries[diaryIndex];
      
      // Check if user already liked
      final existingLikeIndex = diary.likes.indexWhere((like) => like.user.id == userId);
      if (existingLikeIndex == -1) {
        // Create new like
        final newLike = DiaryLike(
          id: DateTime.now().millisecondsSinceEpoch, // Temporary ID
          user: Author(
            id: userId,
            username: username,
            avatarUrl: null,
          ),
        );
        
        final updatedLikes = List<DiaryLike>.from(diary.likes)..add(newLike);
        
        // Create updated diary with new like
        final updatedDiary = _createUpdatedDiary(diary, likes: updatedLikes);
        _diaries[diaryIndex] = updatedDiary;
        notifyListeners();
      }
    }
    
    // Update in myDiaries list
    final myDiaryIndex = _myDiaries.indexWhere((d) => d.id == diaryId);
    if (myDiaryIndex != -1) {
      final diary = _myDiaries[myDiaryIndex];
      
      final existingLikeIndex = diary.likes.indexWhere((like) => like.user.id == userId);
      if (existingLikeIndex == -1) {
        final newLike = DiaryLike(
          id: DateTime.now().millisecondsSinceEpoch,
          user: Author(
            id: userId,
            username: username,
            avatarUrl: null,
          ),
        );
        
        final updatedLikes = List<DiaryLike>.from(diary.likes)..add(newLike);
        final updatedDiary = _createUpdatedDiary(diary, likes: updatedLikes);
        _myDiaries[myDiaryIndex] = updatedDiary;
        notifyListeners();
      }
    }
  }

  void _handleIncomingComment(Map<String, dynamic> commentData) {
    final diaryId = commentData['diary_id'];
    final commentMap = commentData['comment'];
    
    try {
      // Convert Map to Comment object
      final comment = Comment.fromJson(commentMap);
      
      // Update in diaries list
      final diaryIndex = _diaries.indexWhere((d) => d.id == diaryId);
      if (diaryIndex != -1) {
        final diary = _diaries[diaryIndex];
        final comments = List<Comment>.from(diary.comments);
        
        // Check if comment already exists
        if (!comments.any((c) => c.content == comment.content && 
            c.user.id == comment.user.id)) {
          comments.add(comment);
          final updatedDiary = _createUpdatedDiary(diary, comments: comments);
          _diaries[diaryIndex] = updatedDiary;
          notifyListeners();
        }
      }
      
      // Update in myDiaries list
      final myDiaryIndex = _myDiaries.indexWhere((d) => d.id == diaryId);
      if (myDiaryIndex != -1) {
        final diary = _myDiaries[myDiaryIndex];
        final comments = List<Comment>.from(diary.comments);
        
        if (!comments.any((c) => c.content == comment.content && 
            c.user.id == comment.user.id)) {
          comments.add(comment);
          final updatedDiary = _createUpdatedDiary(diary, comments: comments);
          _myDiaries[myDiaryIndex] = updatedDiary;
          notifyListeners();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling incoming comment: $e');
      }
    }
  }

  void _handleIncomingDelete(Map<String, dynamic> deleteData) {
    final diaryId = deleteData['diary_id'];
    
    _diaries.removeWhere((d) => d.id == diaryId);
    _myDiaries.removeWhere((d) => d.id == diaryId);
    notifyListeners();
  }

  bool _shouldShowDiary(DiaryModel diary) {
    final currentUserId = _getCurrentUserId();
    
    // Always show user's own diaries
    if (diary.author.id == currentUserId) return true;
    
    // Check share type
    switch (diary.shareType) {
      case 'public':
        return true;
      case 'friends':
        // TODO: Check friendship
        return true;
      case 'group':
        // Check if diary has groups and if user is in any of them
        if (diary.groups.isNotEmpty) {
          // TODO: Check group membership
          return true;
        }
        return false;
      case 'private':
      default:
        return false;
    }
  }

  int _getCurrentUserId() {
    // TODO: Get current user ID from your auth system
    // This should come from your UserProvider or AuthProvider
    return 0; // Replace with actual user ID
  }

  // Helper method to create updated diary since DiaryModel doesn't have copyWith
  DiaryModel _createUpdatedDiary(
    DiaryModel diary, {
    List<DiaryLike>? likes,
    List<Comment>? comments,
    List<int>? favoritedUserIds,
  }) {
    return DiaryModel(
      id: diary.id,
      author: diary.author,
      title: diary.title,
      content: diary.content,
      shareType: diary.shareType,
      groups: diary.groups,
      images: diary.images,
      videos: diary.videos,
      videoThumbnails: diary.videoThumbnails,
      mediaType: diary.mediaType,
      likes: likes ?? diary.likes,
      isDeleted: diary.isDeleted,
      createdAt: diary.createdAt,
      updatedAt: diary.updatedAt,
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
        // Merge with existing, avoiding duplicates
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
      
      // Add to both lists
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

  Future<void> likeDiary(int diaryId) async {
    try {
      await feedApiService.likeDiary(diaryId);
      
      // Update in all diaries list
      final diaryIndex = _diaries.indexWhere((d) => d.id == diaryId);
      if (diaryIndex != -1) {
        final diary = _diaries[diaryIndex];
        final currentUserId = _getCurrentUserId();
        
        // Check if user already liked
        final existingLikeIndex = diary.likes.indexWhere((like) => like.user.id == currentUserId);
        if (existingLikeIndex == -1) {
          // Add like locally
          final newLike = DiaryLike(
            id: DateTime.now().millisecondsSinceEpoch,
            user: Author(
              id: currentUserId,
              username: 'You', // This should come from user data
              avatarUrl: null,
            ),
          );
          
          final updatedLikes = List<DiaryLike>.from(diary.likes)..add(newLike);
          final updatedDiary = _createUpdatedDiary(diary, likes: updatedLikes);
          _diaries[diaryIndex] = updatedDiary;
          notifyListeners();
        }
      }
      
      // Update in my diaries list
      final myDiaryIndex = _myDiaries.indexWhere((d) => d.id == diaryId);
      if (myDiaryIndex != -1) {
        final diary = _myDiaries[myDiaryIndex];
        final currentUserId = _getCurrentUserId();
        
        final existingLikeIndex = diary.likes.indexWhere((like) => like.user.id == currentUserId);
        if (existingLikeIndex == -1) {
          final newLike = DiaryLike(
            id: DateTime.now().millisecondsSinceEpoch,
            user: Author(
              id: currentUserId,
              username: 'You',
              avatarUrl: null,
            ),
          );
          
          final updatedLikes = List<DiaryLike>.from(diary.likes)..add(newLike);
          final updatedDiary = _createUpdatedDiary(diary, likes: updatedLikes);
          _myDiaries[myDiaryIndex] = updatedDiary;
          notifyListeners();
        }
      }
      
    } catch (e) {
      rethrow;
    }
  }

  Future<void> saveToFavorites(int diaryId) async {
    try {
      await feedApiService.saveToFavorites(diaryId);
      
      // Update in all diaries list
      final diaryIndex = _diaries.indexWhere((d) => d.id == diaryId);
      if (diaryIndex != -1) {
        final diary = _diaries[diaryIndex];
        final currentUserId = _getCurrentUserId();
        
        if (!diary.favoritedUserIds.contains(currentUserId)) {
          final updatedFavorites = List<int>.from(diary.favoritedUserIds)..add(currentUserId);
          final updatedDiary = _createUpdatedDiary(diary, favoritedUserIds: updatedFavorites);
          _diaries[diaryIndex] = updatedDiary;
          notifyListeners();
        }
      }
      
      // Update in my diaries list
      final myDiaryIndex = _myDiaries.indexWhere((d) => d.id == diaryId);
      if (myDiaryIndex != -1) {
        final diary = _myDiaries[myDiaryIndex];
        final currentUserId = _getCurrentUserId();
        
        if (!diary.favoritedUserIds.contains(currentUserId)) {
          final updatedFavorites = List<int>.from(diary.favoritedUserIds)..add(currentUserId);
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
      
      // Update in all diaries list
      final diaryIndex = _diaries.indexWhere((d) => d.id == diaryId);
      if (diaryIndex != -1) {
        final diary = _diaries[diaryIndex];
        final currentUserId = _getCurrentUserId();
        
        if (diary.favoritedUserIds.contains(currentUserId)) {
          final updatedFavorites = List<int>.from(diary.favoritedUserIds)..remove(currentUserId);
          final updatedDiary = _createUpdatedDiary(diary, favoritedUserIds: updatedFavorites);
          _diaries[diaryIndex] = updatedDiary;
          notifyListeners();
        }
      }
      
      // Update in my diaries list
      final myDiaryIndex = _myDiaries.indexWhere((d) => d.id == diaryId);
      if (myDiaryIndex != -1) {
        final diary = _myDiaries[myDiaryIndex];
        final currentUserId = _getCurrentUserId();
        
        if (diary.favoritedUserIds.contains(currentUserId)) {
          final updatedFavorites = List<int>.from(diary.favoritedUserIds)..remove(currentUserId);
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