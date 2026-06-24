class SessionInfo {
  final String id;
  final String? title;
  final String platform;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;

  const SessionInfo({
    required this.id,
    this.title,
    required this.platform,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    return SessionInfo(
      id: json['id'] as String? ?? '',
      title: json['title'] as String?,
      platform: json['platform'] as String? ?? 'unknown',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
      messageCount: json['message_count'] as int? ?? 0,
    );
  }
}
