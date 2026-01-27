import './group_image_model.dart';

class GroupDetailsModel {
  final int id;
  final String name;
  final int creatorId;
  final String? description;
  List<GroupImage> images;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  GroupDetailsModel({
    required this.id,
    required this.name,
    required this.creatorId,
    this.description,
    List<GroupImage>? images,
    this.createdAt,
    this.updatedAt,
  }) : images = images ?? [];

  factory GroupDetailsModel.fromJson(Map<String, dynamic> json) {
    final imagesRaw = json['images'];
    List<GroupImage> parsedImages = [];

    if (imagesRaw is List) {
      parsedImages = imagesRaw
          .whereType<Map<String, dynamic>>()
          .map(GroupImage.fromJson)
          .toList();
    } else if (imagesRaw is Map<String, dynamic>) {
      // backend inconsistency safeguard
      parsedImages = [GroupImage.fromJson(imagesRaw)];
    }

    return GroupDetailsModel(
      id: json['id'],
      name: json['name'],
      creatorId: json['creator_id'],
      description: json['description'],
      images: parsedImages,
      createdAt: DateTime.tryParse(json['created_at'] ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? ''),
    );
  }

  String? get cover => images.isNotEmpty ? images.first.url : null;
}
