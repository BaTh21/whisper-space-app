
// lib/core/constants/api_constants.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart';  
class ApiConstants {
  // Dynamic base URL based on platform
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8000';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000';
      case TargetPlatform.iOS:
        return 'http://localhost:8000';
      default:
        return 'http://localhost:8000';
    }
  }
  
  // WebSocket URL
  static String get wsBaseUrl {
    if (kIsWeb) {
      return 'ws://localhost:8000';
    } else if (Platform.isAndroid) {
      return 'ws://10.0.2.2:8000';
    } else {
      return 'ws://localhost:8000';
    }
  }
  
  // Auth endpoints
  static const String login = '/api/v1/auth/login';
  static const String register = '/api/v1/auth/register';
  static const String verifyCode = '/api/v1/auth/verify-code';
  static const String resendVerification = '/api/v1/auth/resend-verification';
  static const String forgotPassword = '/api/v1/auth/forgot-password';
  static const String resetPassword = '/api/v1/auth/reset-password';
  static const String refreshToken = '/api/v1/auth/refresh';
  static const String logout = '/api/v1/auth/logout';

  // Diary endpoints
  static const String diaries = '/api/v1/diaries';
  static const String diariesFeed = '/api/v1/diaries/feed';
  static const String myDiaries = '/api/v1/diaries/my-feed';
  static const String diaryComments = '/api/v1/diaries'; // /{id}/comments
  static const String updateComment = '/api/v1/diaries/comments'; // /{id}
  static const String deleteComment = '/api/v1/diaries/comments'; // /{id}
  static const String likeDiary = '/api/v1/diaries'; // /{id}/like
  static const String favorites = '/api/v1/diaries'; // /{id}/favorites
  static const String favoriteList = '/api/v1/diaries/favorite-list';
  
  // User endpoints
  static const String getUserProfile = '/api/v1/users/me';
  static const String userSearch = '/api/v1/users/search';
  
  // Group endpoints
  static const String userGroups = '/api/v1/groups/my';
  
  // Upload endpoints
  static const String uploadMedia = '/api/v1/upload/media';
  static const String uploadAvatar = '/api/v1/avatars/upload';
  
  // WebSocket endpoints
  static const String feedWebSocket = '/api/v1/diaries/ws/feed';
  
  // Headers
  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
  
  // Headers for form login
  static Map<String, String> get formLoginHeaders {
    return {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
    };
  }
  
  // Timeouts
  static const int connectTimeout = 30000;
  static const int receiveTimeout = 30000;
}