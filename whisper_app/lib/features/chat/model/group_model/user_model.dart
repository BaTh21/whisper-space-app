class UserModel{
  final int id;
  final String username;
  final String email;
  final String? avatarUrl;

  UserModel({
      required this.id,
      required this.username,
      required this.email,
      this.avatarUrl
  });

  factory UserModel.fromJson(Map<String, dynamic> json){
    return UserModel(
        id: json['id'],
        username: json['username'],
        email: json['email'],
        avatarUrl: json['avatar_url']
    );
  }
}