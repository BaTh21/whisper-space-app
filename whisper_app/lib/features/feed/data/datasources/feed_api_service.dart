// lib/features/feed/data/datasources/feed_api_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:whisper_space_flutter/core/constants/api_constants.dart';
import 'package:whisper_space_flutter/core/services/storage_service.dart';
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';

class FeedApiService {
  final StorageService storageService;
  final String baseUrl;
  
  FeedApiService({
    required this.storageService,
    String? baseUrl,
  }) : baseUrl = baseUrl ?? ApiConstants.baseUrl;

  void _log(String message) {
  }

  // ============ CREATE DIARY ============
  Future<DiaryModel> createDiary({
    required String title,
    required String content,
    String shareType = 'private',
    List<int>? groupIds,
    List<String>? imageUrls,
    List<String>? videoUrls,
  }) async {
    _log('createDiary() - "$title", shareType: $shareType');
    
    try {
      final token = storageService.getToken();
      if (token == null) {
        throw Exception('Not authenticated. Please login again.');
      }

      _log('🔑 Token exists: ${token.length} chars');
      
      // Prepare request
      final request = {
        'title': title,
        'content': content,
        'share_type': shareType,
        if (groupIds != null && groupIds.isNotEmpty) 'group_ids': groupIds,
        if (imageUrls != null && imageUrls.isNotEmpty) 'images': imageUrls,
        if (videoUrls != null && videoUrls.isNotEmpty) 'videos': videoUrls,
      };

      _log('📤 Creating diary...');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/diaries/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(request),
      ).timeout(const Duration(seconds: 30));

      _log('📥 Response: ${response.statusCode}');
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final diary = DiaryModel.fromJson(data);
        
        _log('✅ Diary created with ID: ${diary.id}');
        
        return diary;
      } else {
        _log('❌ API Error: ${response.body}');
        throw Exception('Failed to create diary: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _log('❌ Error creating diary: $e');
      rethrow;
    }
  }

  // ============ GET FEED ============
  Future<List<DiaryModel>> getFeed({
    int limit = 20,
    int offset = 0,
  }) async {
    _log('getFeed() - limit: $limit, offset: $offset');
    
    try {
      final token = storageService.getToken();
      if (token == null) {
        _log('❌ No auth token');
        return [];
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/diaries/feed?limit=$limit&offset=$offset'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      _log('📥 Feed response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final diaries = data.map<DiaryModel>((json) {
          return DiaryModel.fromJson(json);
        }).toList();
        
        _log('✅ Got ${diaries.length} diaries from API');
        return diaries;
      } else {
        _log('❌ API Error ${response.statusCode}: ${response.body}');
        return [];
      }
    } catch (e) {
      _log('❌ Network error: $e');
      return [];
    }
  }

  // ============ GET MY FEED ============
  Future<List<DiaryModel>> getMyFeed({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final token = storageService.getToken();
      if (token == null) return [];
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/diaries/my-feed?limit=$limit&offset=$offset'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map<DiaryModel>((json) => DiaryModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      _log('Error getting my feed: $e');
      return [];
    }
  }

  // ============ GET MY DIARIES COUNT ============
  Future<int> getMyDiariesCount() async {
    try {
      final token = storageService.getToken();
      if (token == null) return 0;
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/diaries/my-feed/count'),
        headers: {'Authorization': 'Bearer $token'},
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['total'] ?? 0;
      }
      return 0;
    } catch (e) {
      _log('Error getting diary count: $e');
      return 0;
    }
  }

  // ============ LIKE DIARY ============
  Future<void> likeDiary(int diaryId) async {
    try {
      final token = storageService.getToken();
      if (token == null) return;
      
      await http.post(
        Uri.parse('$baseUrl/api/v1/diaries/$diaryId/like'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      _log('Error liking diary: $e');
    }
  }

  // ============ SAVE TO FAVORITES ============
  Future<void> saveToFavorites(int diaryId) async {
    try {
      final token = storageService.getToken();
      if (token == null) return;
      
      await http.post(
        Uri.parse('$baseUrl/api/v1/diaries/$diaryId/favorites'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      _log('Error saving favorite: $e');
    }
  }

  // ============ REMOVE FROM FAVORITES ============
  Future<void> removeFromFavorites(int diaryId) async {
    try {
      final token = storageService.getToken();
      if (token == null) return;
      
      await http.delete(
        Uri.parse('$baseUrl/api/v1/diaries/$diaryId/favorites'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      _log('Error removing favorite: $e');
    }
  }

  // ============ UPLOAD MEDIA ============
Future<String> uploadMedia(File file, {bool isVideo = false}) async {
  try {
    final token = storageService.getToken();
    if (token == null) {
      throw Exception('No authentication token');
    }
    
    _log('📤 Uploading ${isVideo ? 'video' : 'image'}...');
    _log('📁 File path: ${file.path}');
    _log('📊 File size: ${await file.length()} bytes');
    
    // Read file as bytes
    final bytes = await file.readAsBytes();
    
    // Convert to base64
    final base64Data = base64Encode(bytes);
    
    // Get file extension
    final extension = file.path.split('.').last.toLowerCase();
    
    // Create proper MIME type
    String mimeType;
    if (isVideo) {
      // Map extensions to proper MIME types
      switch (extension) {
        case 'mp4':
          mimeType = 'video/mp4';
          break;
        case 'mov':
          mimeType = 'video/quicktime';
          break;
        case 'avi':
          mimeType = 'video/x-msvideo';
          break;
        case 'webm':
          mimeType = 'video/webm';
          break;
        case 'mkv':
          mimeType = 'video/x-matroska';
          break;
        default:
          mimeType = 'video/mp4';
      }
    } else {
      switch (extension) {
        case 'jpg':
        case 'jpeg':
          mimeType = 'image/jpeg';
          break;
        case 'png':
          mimeType = 'image/png';
          break;
        case 'gif':
          mimeType = 'image/gif';
          break;
        case 'webp':
          mimeType = 'image/webp';
          break;
        default:
          mimeType = 'image/jpeg';
      }
    }
    
    final dataUrl = 'data:$mimeType;base64,$base64Data';
    
    _log('📋 MIME type: $mimeType');
    _log('📦 Data URL length: ${dataUrl.length}');
    
    // Upload to server
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/upload/media'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'data_url': dataUrl,
        'filename': '${isVideo ? 'video' : 'image'}_${DateTime.now().millisecondsSinceEpoch}.$extension',
        'is_diary': true,
      }),
    );
    
    _log('📥 Upload response: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final url = data['url'] as String;
      final thumbnail = data['thumbnail'] as String?;
      _log('✅ Upload successful: $url');
      _log('📸 Thumbnail: $thumbnail');
      return url;
    } else {
      _log('❌ Upload failed: ${response.body}');
      throw Exception('Upload failed: ${response.statusCode} - ${response.body}');
    }
  } catch (e) {
    _log('❌ Upload error: $e');
    rethrow;
  }
}
}