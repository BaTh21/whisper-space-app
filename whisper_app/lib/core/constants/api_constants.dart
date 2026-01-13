import 'dart:io';

import 'package:flutter/foundation.dart';  // Add this

class ApiConstants {
  // Dynamic base URL based on platform
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8000';
    } else if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    } else {
      return 'http://localhost:8000';
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

  static const String diaries = '/api/v1/diaries';
  static const String diariesFeed = '/api/v1/diaries/feed';
  static const String myDiaries = '/api/v1/diaries/my-feed';
  
  static const String uploadMedia = '/api/v1/upload/media';
  static const String uploadAvatar = '/api/v1/avatars/upload';
  
  // User endpoints
  static const String getUserProfile = '/api/v1/users/me';
  
  // Headers - FOR JSON REQUESTS (register, verify, etc.)
  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
  
  // Headers - FOR FORM LOGIN REQUESTS
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