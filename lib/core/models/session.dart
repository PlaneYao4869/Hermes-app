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

  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static String _str(dynamic v) => v?.toString() ?? '';

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    return SessionInfo(
      id: _str(json['id']),
      title: json['title'] as String?,
      platform: _str(json['source'] ?? json['platform'] ?? 'api'),
      createdAt: DateTime.tryParse(_str(json['started_at'] ?? json['created_at'])) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(_str(json['last_active'] ?? json['updated_at'])) ?? DateTime.now(),
      messageCount: _toInt(json['message_count']),
    );
  }
}
