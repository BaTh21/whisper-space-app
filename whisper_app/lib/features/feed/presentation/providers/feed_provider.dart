// lib/features/feed/presentation/providers/feed_provider.dart
import 'package:flutter/foundation.dart';
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';
import 'package:whisper_space_flutter/features/feed/data/datasources/feed_api_service.dart';

class FeedProvider with ChangeNotifier {
  final FeedApiService feedApiService;
  
  List<DiaryModel> _diaries = [];
  List<DiaryModel> _myDiaries = [];
  bool _isLoading = false;
  String? _error;
  
  List<DiaryModel> get diaries => _diaries;
  List<DiaryModel> get myDiaries => _myDiaries;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get myDiariesCount => _myDiaries.length;

  FeedProvider({required this.feedApiService});

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
        _diaries.addAll(newDiaries);
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
        // Update likes logic here
        notifyListeners();
      }
      
      // Update in my diaries list
      final myDiaryIndex = _myDiaries.indexWhere((d) => d.id == diaryId);
      if (myDiaryIndex != -1) {
        notifyListeners();
      }
      
    } catch (e) {
      rethrow;
    }
  }

  Future<void> saveToFavorites(int diaryId) async {
    try {
      await feedApiService.saveToFavorites(diaryId);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> removeFromFavorites(int diaryId) async {
    try {
      await feedApiService.removeFromFavorites(diaryId);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}