import 'dart:ffi';

class ActorModel{
  final int id;
  final String username;
  final String? avatarUrl;

  ActorModel({required this.id, required this.username, this.avatarUrl});

  factory ActorModel.fromJson(Map<String, dynamic> json){
    return ActorModel(id: json['id'], username: json['username'], avatarUrl: json['avatar_url']);
  }
}

class InboxModel {
  final int id;
  final String type;
  final ActorModel actor;
  final ActorModel recipient;
  final DateTime createdAt;
  final bool isRead;
  final int? postId;
  final int? commentId;
  final int? friendRequestId;
  final int? groupId;
  final String extraData;

  InboxModel({
    required this.id,
    required this.type,
    required this.actor,
    required this.recipient,
    required this.createdAt,
    required this.isRead,
    this.postId,
    this.commentId,
    this.friendRequestId,
    this.groupId,
    required this.extraData,
  });

  factory InboxModel.fromJson(Map<String, dynamic> json) {
    return InboxModel(
      id: json['id'] as int,
      type: json['type'] as String,
      actor: ActorModel.fromJson(json['actor']),
      recipient: ActorModel.fromJson(json['recipient']),
      createdAt: DateTime.parse(json['created_at'] as String),
      isRead: json['is_read'] as bool,
      postId: json['post_id'] as int?,
      commentId: json['comment_id'] as int?,
      friendRequestId: json['friend_request_id'] as int?,
      groupId: json['group_id'] as int?,
      extraData: json['extra_data'] as String,
    );
  }
}
