import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:whisper_space_flutter/core/constants/api_constants.dart';

import '../../../../../core/services/auth_service.dart';
import '../../../../../core/services/storage_service.dart';
import '../../../data/models/user_model.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService authService;
  final StorageService storageService;
  
  User? _currentUser;
  bool _isLoading = false;
  String? _error;
  
  AuthProvider({
    required this.authService,
    required this.storageService,
  }) {
    _loadUserFromStorage();
  }
  
  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get savedEmail => storageService.getUserEmail();
  
  Future<void> _loadUserFromStorage() async {
    if (storageService.isLoggedIn()) {
      final userData = storageService.getUserData();
      if (userData != null) {
        try {
          _currentUser = User.fromJson(userData);
          notifyListeners();
        } catch (e) {
          await storageService.clearAll();
        }
      }
    }
  }
  
  Future<LoginResponse> login(String email, String password) async {
    _setLoading(true);
    _error = null;
    
    try {
      final result = await authService.login(email, password);
      
      if (result.success) {
        _currentUser = result.user;
        notifyListeners();
      } else {
        _error = result.message;
      }
      
      return result;
    } catch (e) {
      _error = 'An unexpected error occurred';
      return LoginResponse.error(message: _error!);
    } finally {
      _setLoading(false);
    }
  }
  
Future<RegisterResponse> register(
  String username, 
  String email, 
  String password
) async {
  _setLoading(true);
  _error = null;
  
  try {
    final result = await authService.register(username, email, password);
    
    if (result.success) {
      // Save email for verification screen
      await storageService.saveUserEmail(email);
    } else {
      _error = result.message;
    }
    
    return result;
  } catch (e) {
    _error = 'An unexpected error occurred';
    return RegisterResponse.error(message: _error!);
  } finally {
    _setLoading(false);
  }
}
  
  Future<VerifyResponse> verifyEmail(String email, String code) async {
    _setLoading(true);
    _error = null;
    
    try {
      final result = await authService.verifyEmail(email, code);
      
      if (result.success) {
        // Load user after verification
        final user = await authService.getCurrentUser(result.token!.accessToken);
        _currentUser = user;
        await storageService.saveUserData(user.toJson());
        notifyListeners();
      } else {
        _error = result.message;
      }
      
      return result;
    } catch (e) {
      _error = 'An unexpected error occurred';
      return VerifyResponse.error(message: _error!);
    } finally {
      _setLoading(false);
    }
  }
  
  Future<ForgotPasswordResponse> forgotPassword(String email) async {
    _setLoading(true);
    _error = null;
    
    try {
      final result = await authService.forgotPassword(email);
      
      if (!result.success) {
        _error = result.message;
      }
      
      return result;
    } catch (e) {
      _error = 'An unexpected error occurred';
      return ForgotPasswordResponse.error(message: _error!);
    } finally {
      _setLoading(false);
    }
  }
  
  Future<ResendVerificationResponse> resendVerification(String email) async {
    _setLoading(true);
    _error = null;
    
    try {
      final result = await authService.resendVerification(email);
      
      if (!result.success) {
        _error = result.message;
      }
      
      return result;
    } catch (e) {
      _error = 'An unexpected error occurred';
      return ResendVerificationResponse.error(message: _error!);
    } finally {
      _setLoading(false);
    }
  }
  
  Future<void> logout() async {
    _setLoading(true);
    try {
      await authService.logout();
      _currentUser = null;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Logout failed';
    } finally {
      _setLoading(false);
    }
  }
  Future<bool> uploadAvatar(File imageFile) async {
  _setLoading(true);
  try {
    final dio = Dio();
    
    // Get token
    final token = await storageService.getToken();
    if (token == null) {
      _error = 'Not authenticated';
      _setLoading(false);
      return false;
    }
    
    // Create form data
    final formData = FormData.fromMap({
      'avatar': await MultipartFile.fromFile(
        imageFile.path,
        filename: 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ),
    });
    
    // Make request
    final response = await dio.post(
      '${ApiConstants.baseUrl}/api/v1/avatars/upload',
      data: formData,
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'multipart/form-data',
        },
      ),
    );
    
    if (response.statusCode == 200) {
      // Update current user with new avatar URL
      final avatarUrl = response.data['avatar_url'];
      if (_currentUser != null && avatarUrl != null) {
        _currentUser = _currentUser!.copyWith(avatarUrl: avatarUrl);
        
        // Save updated user to storage
        await storageService.saveUserData(_currentUser!.toJson());
        
        notifyListeners();
      }
      
      _setLoading(false);
      return true;
    }
    
    _error = 'Failed to upload avatar';
    _setLoading(false);
    return false;
  } catch (e) {
    _error = 'Error uploading avatar: $e';
    _setLoading(false);
    return false;
  }
}

Future<bool> deleteAvatar() async {
  _setLoading(true);
  try {
    final dio = Dio();
    
    // Get token
    final token = await storageService.getToken();
    if (token == null) {
      _error = 'Not authenticated';
      _setLoading(false);
      return false;
    }
    
    // Make request
    final response = await dio.delete(
      '${ApiConstants.baseUrl}/api/v1/avatars/delete',
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
        },
      ),
    );
    
    if (response.statusCode == 200) {
      // Update current user to remove avatar URL
      if (_currentUser != null) {
        _currentUser = _currentUser!.copyWith(avatarUrl: null);
        
        // Save updated user to storage
        await storageService.saveUserData(_currentUser!.toJson());
        
        notifyListeners();
      }
      
      _setLoading(false);
      return true;
    }
    
    _error = 'Failed to delete avatar';
    _setLoading(false);
    return false;
  } catch (e) {
    _error = 'Error deleting avatar: $e';
    _setLoading(false);
    return false;
  }
}
Future<void> getCurrentUser() async {
  try {
    final token = await storageService.getToken();
    if (token != null) {
      final user = await authService.getCurrentUser(token);
      _currentUser = user;
      await storageService.saveUserData(user.toJson());
      notifyListeners();
    }
  } catch (e) {
    print('Error fetching user: $e');
  }
}


  
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

}