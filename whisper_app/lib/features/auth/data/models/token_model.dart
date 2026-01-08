class Token {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  
  Token({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
  });
  
  factory Token.fromJson(Map<String, dynamic> json) {
    return Token(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      tokenType: json['token_type'] as String,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'token_type': tokenType,
    };
  }
}