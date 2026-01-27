class ChatCreator {
  final int id;
  final String username;
  final String? avatar;

  ChatCreator({
    required this.id,
    required this.username,
    this.avatar,
  });

  factory ChatCreator.fromJson(Map<String, dynamic> json) {
    return ChatCreator(
      id: json['id'],
      username: json['username'],
      avatar: json['avatar_url'],
    );
  }
}

class ChatListItemModel {
  final int id;
  final String type;
  final String name;
  final String? avatar;
  final String? lastMessage;
  final DateTime updatedAt;
  final ChatCreator? creator;

  ChatListItemModel({
    required this.id,
    required this.type,
    required this.name,
    this.avatar,
    this.lastMessage,
    required this.updatedAt,
    this.creator, // optional
  });

  factory ChatListItemModel.fromJson(Map<String, dynamic> json) {
    return ChatListItemModel(
      id: json['id'],
      type: json['type'],
      name: json['name'],
      avatar: json['avatar'],
      lastMessage: json['last_message'],
      updatedAt: DateTime.parse(json['updated_at']),
      creator: json['creator'] != null
          ? ChatCreator.fromJson(json['creator'])
          : null,
    );
  }
}
