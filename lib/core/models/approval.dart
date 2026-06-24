class ApprovalRequest {
  final String id;
  final String runId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final String? description;
  final DateTime createdAt;

  const ApprovalRequest({
    required this.id,
    required this.runId,
    required this.toolName,
    required this.arguments,
    this.description,
    required this.createdAt,
  });

  factory ApprovalRequest.fromJson(Map<String, dynamic> json) {
    return ApprovalRequest(
      id: json['id'] as String? ?? json['approval_id'] as String? ?? '',
      runId: json['run_id'] as String? ?? '',
      toolName: json['tool_name'] as String? ?? json['tool'] as String? ?? 'unknown',
      arguments: json['arguments'] as Map<String, dynamic>? ?? {},
      description: json['description'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
