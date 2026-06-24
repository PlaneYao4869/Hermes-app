enum MessageRole { user, assistant, tool, system }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final List<ToolCall>? toolCalls;
  final bool isStreaming;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.toolCalls,
    this.isStreaming = false,
  });

  ChatMessage copyWith({String? content, bool? isStreaming, List<ToolCall>? toolCalls}) {
    return ChatMessage(
      id: id, role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      toolCalls: toolCalls ?? this.toolCalls,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      role: MessageRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => MessageRole.assistant,
      ),
      content: json['content'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      toolCalls: (json['tool_calls'] as List?)?.map((t) => ToolCall.fromJson(t as Map<String, dynamic>)).toList(),
      isStreaming: json['is_streaming'] as bool? ?? false,
    );
  }
}

class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String? result;
  final String? status;

  const ToolCall({
    required this.id, required this.name,
    required this.arguments, this.result, this.status,
  });

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      arguments: json['arguments'] as Map<String, dynamic>? ?? {},
      result: json['result'] as String?,
      status: json['status'] as String?,
    );
  }
}
