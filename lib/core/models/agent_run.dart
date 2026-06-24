class AgentRun {
  final String id;
  final String? sessionId;
  final String status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? prompt;
  final String? result;

  const AgentRun({
    required this.id,
    this.sessionId,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.prompt,
    this.result,
  });

  factory AgentRun.fromJson(Map<String, dynamic> json) {
    return AgentRun(
      id: json['id'] as String? ?? '',
      sessionId: json['session_id'] as String?,
      status: json['status'] as String? ?? 'unknown',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      completedAt: json['completed_at'] != null ? DateTime.tryParse(json['completed_at'] as String) : null,
      prompt: json['prompt'] as String?,
      result: json['result'] as String?,
    );
  }
}
