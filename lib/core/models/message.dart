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

  static String _str(dynamic v) => v?.toString() ?? '';

  static DateTime _parseTime(dynamic v) {
    if (v is double) return DateTime.fromMillisecondsSinceEpoch((v * 1000).toInt());
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v * 1000);
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // Parse role - could be string or int
    MessageRole role;
    final rawRole = json['role'];
    if (rawRole is int) {
      role = MessageRole.values[rawRole.clamp(0, MessageRole.values.length - 1)];
    } else {
      role = MessageRole.values.firstWhere(
        (e) => e.name == _str(rawRole),
        orElse: () => MessageRole.assistant,
      );
    }

    return ChatMessage(
      id: _str(json['id']),
      role: role,
      content: _str(json['content']),
      timestamp: _parseTime(json['timestamp']),
      toolCalls: (json['tool_calls'] as List?)
          ?.map((t) => ToolCall.fromJson(t as Map<String, dynamic>))
          .toList(),
      isStreaming: json['is_streaming'] == true || json['is_streaming'] == 1,
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

  static String _str(dynamic v) => v?.toString() ?? '';

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      id: _str(json['id']),
      name: _str(json['name']),
      arguments: json['arguments'] is Map
          ? Map<String, dynamic>.from(json['arguments'] as Map)
          : {},
      result: json['result'] as String?,
      status: json['status'] as String?,
    );
  }
}
