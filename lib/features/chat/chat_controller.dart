import 'dart:async';
import 'package:flutter/foundation.dart';
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

// Is sending
final isSendingProvider = StateProvider<bool>((ref) => false);

String _str(dynamic v) => v?.toString() ?? '';

class ChatMessagesNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref ref;
  StreamSubscription? _eventSub;
  StreamSubscription? _approvalSub;

  ChatMessagesNotifier(this.ref) : super([]) {
    _listenToGateway();
    _autoLoadLatestSession();
  }

  Future<void> _autoLoadLatestSession() async {
    // Wait for gateway to be ready (up to 5 seconds)
    for (int i = 0; i < 25; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      final gateway = ref.read(gatewayServiceProvider);
      final connState = ref.read(connectionStateProvider);
      if (gateway != null && connState.isConnected) {
        try {
          final sessions = await gateway.getSessions();
          if (sessions.isNotEmpty) {
            ref.read(currentSessionIdProvider.notifier).state = sessions.first.id;
            final messages = await gateway.getSessionMessages(sessions.first.id);
            state = messages;
            debugPrint('[Chat] Auto-loaded session: ${sessions.first.id} with ${messages.length} messages');
          }
        } catch (e) {
          debugPrint('[Chat] Failed to auto-load session: $e');
          // Don't treat this as fatal — user can send a new message
        }
        return;
      }
    }
    debugPrint('[Chat] Gateway not ready after 5s, skipping auto-load');
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _approvalSub?.cancel();
    super.dispose();
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

  String? _streamingMessageId;

  void _handleMessageDelta(Map<String, dynamic> data) {
    final content = _str(data['content']);
    if (content.isEmpty) return;

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
        final finalContent = _str(data['content']).isEmpty ? state[idx].content : _str(data['content']);
        state = [...state.sublist(0, idx),
          state[idx].copyWith(content: finalContent, isStreaming: false),
          ...state.sublist(idx + 1)];
      }
      _streamingMessageId = null;
    }
  }

  void _handleToolStart(Map<String, dynamic> data) {
    final toolCall = ToolCall(
      id: _str(data['id']).isEmpty ? 'tool_${DateTime.now().millisecondsSinceEpoch}' : _str(data['id']),
      name: _str(data['name']).isEmpty ? 'unknown' : _str(data['name']),
      arguments: data['arguments'] is Map
          ? Map<String, dynamic>.from(data['arguments'] as Map)
          : <String, dynamic>{},
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
    final toolId = _str(data['id']);
    if (toolId.isEmpty) return;
    final idx = state.indexWhere((m) => m.toolCalls?.any((t) => t.id == toolId) ?? false);
    if (idx >= 0) {
      final oldCall = state[idx].toolCalls!.firstWhere((t) => t.id == toolId);
      final updatedCall = ToolCall(
        id: oldCall.id, name: oldCall.name,
        arguments: oldCall.arguments,
        result: _str(data['result']),
        status: 'complete',
      );
      state = [...state.sublist(0, idx),
        state[idx].copyWith(toolCalls: [updatedCall], content: _str(data['summary']).isEmpty ? state[idx].content : _str(data['summary'])),
        ...state.sublist(idx + 1)];
    }
  }

  void _handleError(Map<String, dynamic> data) {
    state = [...state, ChatMessage(
      id: 'error_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.system,
      content: '错误: ${_str(data['message']).isEmpty ? "未知错误" : _str(data['message'])}',
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

  Future<void> sendMessage(String content) async {
    final gateway = ref.read(gatewayServiceProvider);
    if (gateway == null) return;

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

    // Send via REST API (streaming)
    ref.read(isSendingProvider.notifier).state = true;
    try {
      final sessionId = ref.read(currentSessionIdProvider);
      await gateway.sendChat(content, sessionId: sessionId);
    } catch (e) {
      ref.read(chatMessagesProvider.notifier).state = [
        ...ref.read(chatMessagesProvider),
        ChatMessage(
          id: 'error_${DateTime.now().millisecondsSinceEpoch}',
          role: MessageRole.system,
          content: '发送失败: $e',
          timestamp: DateTime.now(),
        ),
      ];
    } finally {
      ref.read(isSendingProvider.notifier).state = false;
    }
  }

  void newSession() {
    ref.read(chatMessagesProvider.notifier).state = [];
    ref.read(currentSessionIdProvider.notifier).state = null;
  }

  Future<void> loadSession(String sessionId) async {
    final gateway = ref.read(gatewayServiceProvider);
    if (gateway == null) return;

    ref.read(currentSessionIdProvider.notifier).state = sessionId;
    ref.read(isSendingProvider.notifier).state = true;
    try {
      // Load messages in batches (50 per batch, 30s timeout per batch)
      // This handles large sessions over slow connections like Tailscale.
      final messages = await gateway.getSessionMessagesAll(sessionId, batchSize: 50);
      ref.read(chatMessagesProvider.notifier).state = messages;
    } catch (e) {
      ref.read(chatMessagesProvider.notifier).state = [
        ChatMessage(
          id: 'error_${DateTime.now().millisecondsSinceEpoch}',
          role: MessageRole.system,
          content: '加载会话消息失败: $e',
          timestamp: DateTime.now(),
        ),
      ];
    } finally {
      ref.read(isSendingProvider.notifier).state = false;
    }
  }
}
