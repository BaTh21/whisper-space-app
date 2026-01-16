import 'package:equatable/equatable.dart';

class DiaryModel extends Equatable {
  final int id;
  final Author author;
  final String title;
  final String content;
  final String shareType;
  final List<Group> groups;
  final List<String> images;
  final List<String> videos;
  final List<String> videoThumbnails;
  final String mediaType;
  final List<DiaryLike> likes;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<int> favoritedUserIds;
  final List<Comment> comments;

  const DiaryModel({
    required this.id,
    required this.author,
    required this.title,
    required this.content,
    required this.shareType,
    required this.groups,
    required this.images,
    required this.videos,
    required this.videoThumbnails,
    required this.mediaType,
    required this.likes,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
    required this.favoritedUserIds,
    required this.comments,
  });

  // Factory constructor for creating from JSON
  factory DiaryModel.fromJson(Map<String, dynamic> json) {
    try {
      return DiaryModel(
        id: json['id'] as int? ?? 0,
        author: json['author'] is Map<String, dynamic>
            ? Author.fromJson(json['author'] as Map<String, dynamic>)
            : const Author(id: 0, username: 'Unknown', avatarUrl: null),
        title: (json['title'] as String?) ?? '',
        content: (json['content'] as String?) ?? '',
        shareType: (json['share_type'] as String?) ?? 'private',
        groups: json['groups'] is List
            ? (json['groups'] as List)
                .map<Group>((g) => Group.fromJson(g as Map<String, dynamic>))
                .toList()
            : const [],
        images: json['images'] is List
            ? List<String>.from(json['images'] as List)
            : const [],
        videos: json['videos'] is List
            ? List<String>.from(json['videos'] as List)
            : const [],
        videoThumbnails: json['video_thumbnails'] is List
            ? List<String>.from(json['video_thumbnails'] as List)
            : const [],
        mediaType: (json['media_type'] as String?) ?? 'text',
        likes: json['likes'] is List
            ? (json['likes'] as List)
                .map<DiaryLike>((l) => DiaryLike.fromJson(l as Map<String, dynamic>))
                .toList()
            : const [],
        isDeleted: (json['is_deleted'] as bool?) ?? false,
        createdAt: json['created_at'] is String
            ? DateTime.parse(json['created_at'] as String)
            : DateTime.now(),
        updatedAt: json['updated_at'] is String
            ? DateTime.parse(json['updated_at'] as String)
            : DateTime.now(),
        favoritedUserIds: json['favorited_user_ids'] is List
            ? List<int>.from(json['favorited_user_ids'] as List)
            : const [],
        comments: json['comments'] is List
            ? (json['comments'] as List)
                .map<Comment>((c) => Comment.fromJson(c as Map<String, dynamic>))
                .toList()
            : const [],
      );
    } catch (e) {
      return DiaryModel(
        id: 0,
        author: const Author(id: 0, username: 'Error', avatarUrl: null),
        title: 'Error Diary',
        content: 'Could not load this diary',
        shareType: 'private',
        groups: const [],
        images: const [],
        videos: const [],
        videoThumbnails: const [],
        mediaType: 'text',
        likes: const [],
        isDeleted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        favoritedUserIds: const [],
        comments: const [],
      );
    }
  }

  // Convert to JSON - SIMPLIFIED VERSION for local storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'author': {
        'id': author.id,
        'username': author.username,
        'avatar_url': author.avatarUrl,
      },
      'title': title,
      'content': content,
      'share_type': shareType,
      'groups': groups.map((g) => g.toJson()).toList(),
      'images': images,
      'videos': videos,
      'video_thumbnails': videoThumbnails,
      'media_type': mediaType,
      'likes': likes.map((l) => l.toJson()).toList(),
      'is_deleted': isDeleted,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'favorited_user_ids': favoritedUserIds,
      'comments': comments.map((c) => c.toJson()).toList(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        author,
        title,
        content,
        shareType,
        groups,
        images,
        videos,
        videoThumbnails,
        mediaType,
        likes,
        isDeleted,
        createdAt,
        updatedAt,
        favoritedUserIds,
        comments,
      ];
}

class Author extends Equatable {
  final int id;
  final String username;
  final String? avatarUrl;

  const Author({
    required this.id,
    required this.username,
    this.avatarUrl,
  });

  factory Author.fromJson(Map<String, dynamic> json) {
    return Author(
      id: json['id'] as int? ?? 0,
      username: (json['username'] as String?) ?? 'Unknown',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'avatar_url': avatarUrl,
      };

  @override
  List<Object?> get props => [id, username, avatarUrl];
}

class Group extends Equatable {
  final int id;
  final String name;

  const Group({
    required this.id,
    required this.name,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as int? ?? 0,
      name: (json['name'] as String?) ?? 'Unknown Group',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };

  @override
  List<Object?> get props => [id, name];
}

class DiaryLike extends Equatable {
  final int id;
  final Author user;

  const DiaryLike({
    required this.id,
    required this.user,
  });

  factory DiaryLike.fromJson(Map<String, dynamic> json) {
    return DiaryLike(
      id: json['id'] as int? ?? 0,
      user: Author.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user': user.toJson(),
      };

  @override
  List<Object?> get props => [id, user];
}

class Comment extends Equatable {
  final int id;
  final String content;
  final DateTime createdAt;
  final Author user;
  final List<String> images;
  final int? parentId;
  final List<Comment> replies;
  final int diaryId;

  const Comment({
    required this.id,
    required this.diaryId,
    required this.content,
    required this.createdAt,
    required this.user,
    required this.images,
    this.parentId,
    required this.replies,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] as int? ?? 0,
      diaryId: json['diary_id'] as int? ?? 0,
      content: (json['content'] as String?) ?? '',
      createdAt: json['created_at'] is String
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      user: Author.fromJson(json['user'] as Map<String, dynamic>),
      images: json['images'] is List
          ? List<String>.from(json['images'] as List)
          : const [],
      parentId: json['parent_id'] as int?,
      replies: json['replies'] is List
          ? (json['replies'] as List)
              .map<Comment>((r) => Comment.fromJson(r as Map<String, dynamic>))
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'created_at': createdAt.toIso8601String(),
        'user': user.toJson(),
        'images': images,
        'parent_id': parentId,
        'replies': replies.map((r) => r.toJson()).toList(),
      };

  @override
  List<Object?> get props => [
        id,
        content,
        createdAt,
        user,
        images,
        parentId,
        replies,
      ];
}