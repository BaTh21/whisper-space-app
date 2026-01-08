import '../../../../core/services/auth_service.dart';
import '../models/user_model.dart';

class AuthRepository {
  final AuthService authService;
  
  AuthRepository({required this.authService});
  
  Future<LoginResponse> login(String email, String password) async {
    return await authService.login(email, password);
  }
  
  Future<RegisterResponse> register(
    String username, 
    String email, 
    String password
  ) async {
    return await authService.register(username, email, password);
  }
  
  Future<VerifyResponse> verifyEmail(String email, String code) async {
    return await authService.verifyEmail(email, code);
  }
  
  Future<ForgotPasswordResponse> forgotPassword(String email) async {
    return await authService.forgotPassword(email);
  }
  
  Future<User> getCurrentUser(String token) async {
    return await authService.getCurrentUser(token);
  }
  
  Future<void> logout() async {
    await authService.logout();
  }
  
  Future<ResendVerificationResponse> resendVerification(String email) async {
    return await authService.resendVerification(email);
  }
}