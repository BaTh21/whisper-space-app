import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userDataKey = 'user_data';
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _userEmailKey = 'user_email';
  
  late SharedPreferences _prefs;
  
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      

      final allKeys = _prefs.getKeys();
      if (getToken() != null) {
      }
    } catch (e) {
      rethrow;
    }
  }

  String? getToken() {
    if (_prefs == null) throw Exception('StorageService not initialized');
    final token = _prefs.getString(_tokenKey);
    return token;
  }
  
  // Token management
  Future<void> saveToken(String token) async {
    if (_prefs == null) throw Exception('StorageService not initialized');
    await _prefs.setString(_tokenKey, token);
  }
  
  Future<void> saveRefreshToken(String refreshToken) async {
    await _prefs.setString(_refreshTokenKey, refreshToken);
  }
  
  String? getRefreshToken() {
    return _prefs.getString(_refreshTokenKey);
  }
  
  // User data
  Future<void> saveUserData(Map<String, dynamic> userData) async {
    await _prefs.setString(_userDataKey, jsonEncode(userData));
  }
  
  Map<String, dynamic>? getUserData() {
    final data = _prefs.getString(_userDataKey);
    if (data != null) {
      try {
        return jsonDecode(data) as Map<String, dynamic>;
      } catch (e) {
        return null;
      }
    }
    return null;
  }
  
  // User email
  Future<void> saveUserEmail(String email) async {
    await _prefs.setString(_userEmailKey, email);
  }
  
  String? getUserEmail() {
    return _prefs.getString(_userEmailKey);
  }
  
  // Login status
  Future<void> setLoggedIn(bool value) async {
    await _prefs.setBool(_isLoggedInKey, value);
  }
  
  bool isLoggedIn() {
    if (_prefs == null) throw Exception('StorageService not initialized');
    final loggedIn = _prefs.getBool(_isLoggedInKey) ?? false;
    return loggedIn;
  }
  
  // Clear all data (logout)
  Future<void> clearAll() async {
    await _prefs.clear();
  }
  
  // Check if first launch
  bool isFirstLaunch() {
    return !_prefs.containsKey(_isLoggedInKey);
  }
  
  int min(int a, int b) => a < b ? a : b;
}