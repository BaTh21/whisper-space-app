// lib/features/feed/data/repositories/feed_repository_impl.dart
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';
import '../datasources/feed_api_service.dart';

abstract class FeedRepository {
  Future<List<DiaryModel>> getFeed({int limit, int offset});
  Future<List<DiaryModel>> getMyFeed({int limit, int offset});
  Future<int> getMyDiariesCount();
  Future<void> likeDiary(int diaryId);
  Future<void> saveToFavorites(int diaryId);
  Future<void> removeFromFavorites(int diaryId);
}

class FeedRepositoryImpl implements FeedRepository {
  final FeedApiService apiService;

  FeedRepositoryImpl({required this.apiService});

  @override
  Future<List<DiaryModel>> getFeed({int limit = 25, int offset = 0}) async {
    return await apiService.getFeed(limit: limit, offset: offset);
  }

  @override
  Future<List<DiaryModel>> getMyFeed({int limit = 25, int offset = 0}) async {
    return await apiService.getMyFeed(limit: limit, offset: offset);
  }

  @override
  Future<int> getMyDiariesCount() async {
    return await apiService.getMyDiariesCount();
  }

  @override
  Future<void> likeDiary(int diaryId) async {
    await apiService.likeDiary(diaryId);
  }

  @override
  Future<void> saveToFavorites(int diaryId) async {
    await apiService.saveToFavorites(diaryId);
  }

  @override
  Future<void> removeFromFavorites(int diaryId) async {
    await apiService.removeFromFavorites(diaryId);
  }
}