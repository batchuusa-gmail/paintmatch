class UserProject {
  final String id;
  final String userId;
  final String projectName;
  final String? roomImageUrl;
  final String? renderedImageUrl;
  final String? selectedHex;
  final List<Map<String, dynamic>> vendorPicks;
  final DateTime createdAt;

  const UserProject({
    required this.id,
    required this.userId,
    required this.projectName,
    this.roomImageUrl,
    this.renderedImageUrl,
    this.selectedHex,
    this.vendorPicks = const [],
    required this.createdAt,
  });

  factory UserProject.fromJson(Map<String, dynamic> json) => UserProject(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        projectName: json['project_name'] as String? ?? 'My Room',
        roomImageUrl: json['room_image_url'] as String?,
        renderedImageUrl: json['rendered_image_url'] as String?,
        selectedHex: json['selected_hex'] as String?,
        vendorPicks: (json['vendor_picks'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [],
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
