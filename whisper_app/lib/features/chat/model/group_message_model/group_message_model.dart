class AuthorModel {
  final int id;
  final String username;
  final String? avatar;

  AuthorModel({
    required this.id,
    required this.username,
    this.avatar,
  });

  factory AuthorModel.fromJson(Map<String, dynamic> json) {
    return AuthorModel(
      id: json['id'],
      username: json['username'],
      avatar: json['avatar_url'],
    );
  }
}

class SeenMessageModel {
  final int id;
  final AuthorModel user;
  final DateTime seenAt;

  SeenMessageModel({
    required this.id,
    required this.user,
    required this.seenAt,
  });

  factory SeenMessageModel.fromJson(Map<String, dynamic> json) {
    return SeenMessageModel(
      id: json['id'],
      user: AuthorModel.fromJson(json['user']),
      seenAt: DateTime.parse(json['seen_at']),
    );
  }
}

class ParentMessageModel{
  final int id;
  final AuthorModel sender;
  final String? content;
  final String? callContent;
  final String? fileUrl;
  final String? voiceUrl;

  ParentMessageModel({
      required this.id,
      required this.sender,
      this.content,
      this.callContent,
      this.fileUrl,
      this.voiceUrl
  });

  factory ParentMessageModel.fromJson(Map<String, dynamic> json){
    return ParentMessageModel(
        id: json['id'],
        sender: AuthorModel.fromJson(json['sender']),
        content: json['content'],
        callContent: json['call_content'],
        fileUrl: json['file_url'],
        voiceUrl: json['voice_url']
    );
  }
}

class GroupMessageModel {
  final int id;
  final String? incomingTempId;
  final AuthorModel? forwardedBy;
  final int groupId;
  final String? content;
  final String? callContent;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? fileUrl;
  final String? voiceUrl;
  final SeenMessageModel? seenBy;
  final String? tempId;
  final ParentMessageModel? parentMessage;

  GroupMessageModel({
    required this.id,
    this.incomingTempId,
    this.forwardedBy,
    required this.groupId,
    this.content,
    this.callContent,
    required this.createdAt,
    this.updatedAt,
    this.fileUrl,
    this.voiceUrl,
    this.seenBy,
    this.tempId,
    this.parentMessage
  });

  factory GroupMessageModel.fromJson(Map<String, dynamic> json){
    return GroupMessageModel(
        id: json['id'],
        incomingTempId: json['incoming_temp_id'],
        groupId: json['group_id'],
        forwardedBy: json['forwarded_by'],
        content: json['content'],
        callContent: json['call_content'],
        createdAt: DateTime.parse(json['created_at']),
        fileUrl: json['file_url'],
        voiceUrl: json['voice_url'],
        seenBy:
        json['seen_by'] != null ?
        SeenMessageModel.fromJson(json['seeb_by']) : null,
        tempId: json['temp_id'],
        parentMessage: json['parent_message'] != null
        ? ParentMessageModel.fromJson(json['parent_message']): null
    );
  }
}