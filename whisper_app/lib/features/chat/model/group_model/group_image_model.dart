class GroupImage {
  final int id;
  final String url;
  final int uploadedBy;
  final DateTime createdAt;

  GroupImage({
    required this.id,
    required this.url,
    required this.uploadedBy,
    required this.createdAt,
  });

  factory GroupImage.fromJson(Map<String, dynamic> json) {
    return GroupImage(
      id: json['id'],
      url: json['url'],
      uploadedBy: json['uploaded_by'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
