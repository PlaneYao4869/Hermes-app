import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/gateway_service.dart';
import '../../core/models/message.dart';
import '../../core/models/approval.dart';

// Messages state
final chatMessagesProvider = StateNotifierProvider<ChatMessagesNotifier, List<ChatMessage>>((ref) {
  return ChatMessagesNotifier(ref);
});

// Pending approval
final pendingApprovalProvider = StateProvider<ApprovalRequest?>((ref) => null);

// Current session
final currentSessionIdProvider = StateProvider<String?>((ref) => null);

class ChatMessagesNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref ref;
  StreamSubscription? _eventSub;
  StreamSubscription? _approvalSub;
  String? _streamingMessageId;

  ChatMessagesNotifier(this.ref) : super([]) {
    _listenToGateway();
  }

  void _listenToGateway() {
    ref.listen(gatewayServiceProvider, (prev, next) {
      if (next == null) return;
      _eventSub?.cancel();
      _approvalSub?.cancel();

      _eventSub = next.events.listen((event) {
        switch (event.type) {
          case GatewayEventType.messageDelta:
            _handleMessageDelta(event.data);
            break;
          case GatewayEventType.messageComplete:
            _handleMessageComplete(event.data);
            break;
          case GatewayEventType.toolStart:
            _handleToolStart(event.data);
            break;
          case GatewayEventType.toolComplete:
            _handleToolComplete(event.data);
            break;
          case GatewayEventType.error:
            _handleError(event.data);
            break;
          default:
            break;
        }
      });

      _approvalSub = next.approvals.listen((approval) {
        ref.read(pendingApprovalProvider.notifier).state = approval;
      });
    });
  }

  void _handleMessageDelta(Map<String, dynamic> data) {
    final content = data['content'] as String? ?? data['delta'] as String? ?? '';
    if (_streamingMessageId == null) {
      _streamingMessageId = 'stream_${DateTime.now().millisecondsSinceEpoch}';
      state = [...state, ChatMessage(
        id: _streamingMessageId!,
        role: MessageRole.assistant,
        content: content,
        timestamp: DateTime.now(),
        isStreaming: true,
      )];
    } else {
      final idx = state.indexWhere((m) => m.id == _streamingMessageId);
      if (idx >= 0) {
        final updated = state[idx].copyWith(content: state[idx].content + content);
        state = [...state.sublist(0, idx), updated, ...state.sublist(idx + 1)];
      }
    }
  }

  void _handleMessageComplete(Map<String, dynamic> data) {
    if (_streamingMessageId != null) {
      final idx = state.indexWhere((m) => m.id == _streamingMessageId);
      if (idx >= 0) {
        final finalContent = data['content'] as String? ?? state[idx].content;
        state = [...state.sublist(0, idx), state[idx].copyWith(content: finalContent, isStreaming: false), ...state.sublist(idx + 1)];
      }
      _streamingMessageId = null;
    }
  }

  void _handleToolStart(Map<String, dynamic> data) {
    final toolCall = ToolCall(
      id: data['id'] as String? ?? 'tool_${DateTime.now().millisecondsSinceEpoch}',
      name: data['name'] as String? ?? 'unknown',
      arguments: data['arguments'] as Map<String, dynamic>? ?? {},
      status: 'running',
    );
    state = [...state, ChatMessage(
      id: 'tool_${toolCall.id}',
      role: MessageRole.tool,
      content: '调用工具: ${toolCall.name}',
      timestamp: DateTime.now(),
      toolCalls: [toolCall],
    )];
  }

  void _handleToolComplete(Map<String, dynamic> data) {
    final toolId = data['id'] as String?;
    if (toolId == null) return;
    final idx = state.indexWhere((m) => m.toolCalls?.any((t) => t.id == toolId) ?? false);
    if (idx >= 0) {
      final oldCall = state[idx].toolCalls!.firstWhere((t) => t.id == toolId);
      final updatedCall = ToolCall(
        id: oldCall.id, name: oldCall.name,
        arguments: oldCall.arguments,
        result: data['result'] as String?,
        status: 'complete',
      );
      state = [...state.sublist(0, idx),
        state[idx].copyWith(toolCalls: [updatedCall], content: data['summary'] as String? ?? state[idx].content),
        ...state.sublist(idx + 1)];
    }
  }

  void _handleError(Map<String, dynamic> data) {
    state = [...state, ChatMessage(
      id: 'error_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.system,
      content: '错误: ${data['message'] as String? ?? "未知错误"}',
      timestamp: DateTime.now(),
    )];
  }
}

// Chat controller for sending messages
final chatControllerProvider = StateNotifierProvider<ChatController, void>((ref) {
  return ChatController(ref);
});

class ChatController extends StateNotifier<void> {
  final Ref ref;
  ChatController(this.ref) : super(null);

  void sendMessage(String content) {
    // Add user message to state
    final userMsg = ChatMessage(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.user,
      content: content,
      timestamp: DateTime.now(),
    );
    ref.read(chatMessagesProvider.notifier).state = [
      ...ref.read(chatMessagesProvider),
      userMsg,
    ];

    // Send via gateway
    final gateway = ref.read(gatewayServiceProvider);
    if (gateway != null) {
      final sessionId = ref.read(currentSessionIdProvider);
      gateway.sendChatMessage(content, sessionId: sessionId);
    }
  }

  void newSession() {
    ref.read(chatMessagesProvider.notifier).state = [];
    ref.read(currentSessionIdProvider.notifier).state = null;
  }
}
