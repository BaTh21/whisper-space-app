import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../../features/auth/data/models/token_model.dart';
import '../../features/auth/data/models/user_model.dart';
import 'storage_service.dart';

class AuthService {
  final StorageService storageService;
  final String baseUrl;
  
  AuthService({
    required this.storageService,
    String? baseUrl,
  }) : baseUrl = baseUrl ?? ApiConstants.baseUrl;
  
  // Login with email and password
Future<LoginResponse> login(String email, String password) async {
  try {

    final response = await http.post(
      Uri.parse('$baseUrl${ApiConstants.login}'),
      headers: ApiConstants.formLoginHeaders,  // Use form headers, not defaultHeaders
      body: 'username=${Uri.encodeComponent(email)}&password=${Uri.encodeComponent(password)}',
    );
    
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final token = Token.fromJson(data);
      
      // Save tokens
      await storageService.saveToken(token.accessToken);
      await storageService.saveRefreshToken(token.refreshToken);
      await storageService.setLoggedIn(true);
      
      // Fetch user data
      final user = await getCurrentUser(token.accessToken);
      await storageService.saveUserData(user.toJson());
      await storageService.saveUserEmail(user.email);
      
      return LoginResponse.success(user: user, token: token);
    } else {
      // Handle error response
      return _handleLoginError(response);
    }
  } catch (e) {
    return LoginResponse.error(
      message: 'Connection error: ${e.toString()}',
    );
  }
}
LoginResponse _handleLoginError(http.Response response) {
  try {
    final error = jsonDecode(response.body);
    String errorMessage;
    
    if (error['detail'] is List) {
      // Handle list of validation errors
      final errors = error['detail'] as List;
      errorMessage = errors.map((e) {
        if (e is Map && e.containsKey('msg')) {
          return e['msg'];
        }
        return 'Validation error';
      }).join(', ');
    } else if (error['detail'] is String) {
      errorMessage = error['detail'];
    } else {
      errorMessage = 'Login failed (Status: ${response.statusCode})';
    }
    
    return LoginResponse.error(message: errorMessage);
  } catch (e) {
    return LoginResponse.error(
      message: 'Login failed with status ${response.statusCode}',
    );
  }
}
  
  // Register new user
  Future<RegisterResponse> register(
    String username, 
    String email, 
    String password
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl${ApiConstants.register}'),
        headers: ApiConstants.defaultHeaders,
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
        }),
      );
      
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await storageService.saveUserEmail(email);
        return RegisterResponse.success(
          message: data['msg'] ?? 'Registration successful! Please check your email for verification code.',
          email: email,
        );
      } else if (response.statusCode == 409) {
        final error = jsonDecode(response.body);
        return RegisterResponse.error(
          message: error['detail'] ?? 'Email or username already exists.',
        );
      } else {
        return RegisterResponse.error(
          message: 'Registration failed. Please try again.',
        );
      }
    } catch (e) {
      return RegisterResponse.error(
        message: 'Network error. Please check your internet connection.',
      );
    }
  }
  
  // Verify email with code
  Future<VerifyResponse> verifyEmail(String email, String code) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl${ApiConstants.verifyCode}'),
        headers: ApiConstants.defaultHeaders,
        body: jsonEncode({
          'email': email,
          'code': code,
        }),
      );
      
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = Token.fromJson(data);
        
        // Save tokens
        await storageService.saveToken(token.accessToken);
        await storageService.saveRefreshToken(token.refreshToken);
        await storageService.setLoggedIn(true);
        
        return VerifyResponse.success(token: token);
      } else {
        final error = jsonDecode(response.body);
        return VerifyResponse.error(
          message: error['detail'] ?? 'Invalid or expired verification code.',
        );
      }
    } catch (e) {
      return VerifyResponse.error(
        message: 'Network error. Please check your internet connection.',
      );
    }
  }
  
  // Forgot password
  Future<ForgotPasswordResponse> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl${ApiConstants.forgotPassword}'),
        headers: ApiConstants.defaultHeaders,
        body: jsonEncode({
          'email': email,
        }),
      );
      
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ForgotPasswordResponse.success(
          message: data['msg'] ?? 'If the email is registered, a reset code has been sent.',
        );
      } else {
        return ForgotPasswordResponse.error(
          message: 'Failed to process request. Please try again.',
        );
      }
    } catch (e) {
      return ForgotPasswordResponse.error(
        message: 'Network error. Please check your internet connection.',
      );
    }
  }
  
  // Get current user
  Future<User> getCurrentUser(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConstants.getUserProfile}'),
        headers: {
          ...ApiConstants.defaultHeaders,
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return User.fromJson(data);
      } else {
        throw Exception('Failed to load user profile');
      }
    } catch (e) {
      throw Exception('Failed to load user: $e');
    }
  }
  
  // Logout
  Future<void> logout() async {
    final refreshToken = storageService.getRefreshToken();
    if (refreshToken != null) {
      try {
        await http.post(
          Uri.parse('$baseUrl${ApiConstants.logout}'),
          headers: ApiConstants.defaultHeaders,
          body: jsonEncode({'refresh_token': refreshToken}),
        );
      } catch (e) {
        // Continue with local logout even if API fails
      }
    }
    
    await storageService.clearAll();
  }
  
  // Resend verification code
  Future<ResendVerificationResponse> resendVerification(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl${ApiConstants.resendVerification}'),
        headers: ApiConstants.defaultHeaders,
        body: jsonEncode({'email': email}),
      );
      
      if (response.statusCode == 200) {
        return ResendVerificationResponse.success(
          message: 'Verification code sent successfully.',
        );
      } else {
        final error = jsonDecode(response.body);
        return ResendVerificationResponse.error(
          message: error['detail'] ?? 'Failed to resend verification code.',
        );
      }
    } catch (e) {
      return ResendVerificationResponse.error(
        message: 'Network error. Please check your internet connection.',
      );
    }
  }
}

// Response classes
class LoginResponse {
  final bool success;
  final String? message;
  final User? user;
  final Token? token;
  
  LoginResponse({
    required this.success,
    this.message,
    this.user,
    this.token,
  });
  
  factory LoginResponse.success({required User user, required Token token}) {
    return LoginResponse(
      success: true,
      user: user,
      token: token,
    );
  }
  
  factory LoginResponse.error({required String message}) {
    return LoginResponse(
      success: false,
      message: message,
    );
  }
}

class RegisterResponse {
  final bool success;
  final String? message;
  final String? email;
  
  RegisterResponse({
    required this.success,
    this.message,
    this.email,
  });
  
  factory RegisterResponse.success({String? message, String? email}) {
    return RegisterResponse(
      success: true,
      message: message,
      email: email,
    );
  }
  
  factory RegisterResponse.error({required String message}) {
    return RegisterResponse(
      success: false,
      message: message,
    );
  }
}

class VerifyResponse {
  final bool success;
  final String? message;
  final Token? token;
  
  VerifyResponse({
    required this.success,
    this.message,
    this.token,
  });
  
  factory VerifyResponse.success({required Token token}) {
    return VerifyResponse(
      success: true,
      token: token,
    );
  }
  
  factory VerifyResponse.error({required String message}) {
    return VerifyResponse(
      success: false,
      message: message,
    );
  }
}

class ForgotPasswordResponse {
  final bool success;
  final String? message;
  
  ForgotPasswordResponse({
    required this.success,
    this.message,
  });
  
  factory ForgotPasswordResponse.success({String? message}) {
    return ForgotPasswordResponse(
      success: true,
      message: message,
    );
  }
  
  factory ForgotPasswordResponse.error({required String message}) {
    return ForgotPasswordResponse(
      success: false,
      message: message,
    );
  }
}

class ResendVerificationResponse {
  final bool success;
  final String? message;
  
  ResendVerificationResponse({
    required this.success,
    this.message,
  });
  
  factory ResendVerificationResponse.success({String? message}) {
    return ResendVerificationResponse(
      success: true,
      message: message,
    );
  }
  
  factory ResendVerificationResponse.error({required String message}) {
    return ResendVerificationResponse(
      success: false,
      message: message,
    );
  }
}