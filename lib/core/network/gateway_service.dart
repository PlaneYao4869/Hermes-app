import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/gateway_config.dart';
import '../models/message.dart';
import '../models/session.dart';
import '../models/agent_run.dart';
import '../models/approval.dart';
import 'connection_state.dart';

final connectionStateProvider = StateNotifierProvider<ConnectionStateNotifier, HermesConnectionState>((ref) {
  return ConnectionStateNotifier();
});

final gatewayConfigProvider = StateNotifierProvider<GatewayConfigNotifier, GatewayConfig?>((ref) {
  return GatewayConfigNotifier();
});

class GatewayConfigNotifier extends StateNotifier<GatewayConfig?> {
  GatewayConfigNotifier() : super(null);
  void configure(GatewayConfig config) => state = config;
}

final gatewayServiceProvider = StateNotifierProvider<GatewayServiceNotifier, GatewayService?>((ref) {
  return GatewayServiceNotifier(ref);
});

class GatewayServiceNotifier extends StateNotifier<GatewayService?> {
  final Ref ref;
  GatewayServiceNotifier(this.ref) : super(null) {
    ref.listen<GatewayConfig?>(gatewayConfigProvider, (prev, next) {
      if (next != null && next != prev) {
        _createAndConnect(next);
      }
    });
  }

  Future<void> _createAndConnect(GatewayConfig config) async {
    state?.dispose();
    final service = GatewayService(config, ref);
    state = service;
    await service.connect();
  }
}

class GatewayService {
  final GatewayConfig config;
  final Ref ref;

  final _messageController = StreamController<GatewayEvent>.broadcast();
  final _approvalController = StreamController<ApprovalRequest>.broadcast();

  WebSocketChannel? _ws;
  bool _wsReady = false;

  // Subscription state for real-time message sync
  String? _subscribedSessionId;
  int? _lastMessageId;

  Stream<GatewayEvent> get events => _messageController.stream;
  Stream<ApprovalRequest> get approvals => _approvalController.stream;

  /// Whether a WS subscription is currently active.
  bool get isSubscribed => _subscribedSessionId != null;

  /// The session ID currently subscribed via WS, if any.
  String? get subscribedSessionId => _subscribedSessionId;

  /// The last known message ID from the subscribed session.
  int? get lastMessageId => _lastMessageId;

  GatewayService(this.config, this.ref);

  Future<bool> connect() async {
    ref.read(connectionStateProvider.notifier).setConnecting();

    // Try WebSocket on port 8643
    try {
      final wsUrl = config.wsUrl;
      debugPrint('[Gateway] Connecting WS: $wsUrl');

      _ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      final completer = Completer<bool>();

      _ws!.stream.listen(
        (data) {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          final type = msg['type'] as String? ?? '';

          if (type == 'ready') {
            _wsReady = true;
            if (!completer.isCompleted) {
              ref.read(connectionStateProvider.notifier).setConnected();
              completer.complete(true);
              debugPrint('[Gateway] WS connected');
            }
          } else if (type == 'delta') {
            _messageController.add(GatewayEvent(type: GatewayEventType.messageDelta, data: {'content': msg['content'] as String? ?? ''}));
          } else if (type == 'done') {
            _messageController.add(GatewayEvent(type: GatewayEventType.messageComplete, data: {'content': msg['content'] as String? ?? ''}));
          } else if (type == 'message') {
            // Incoming message from WS subscription (e.g. from CLI or other sources)
            final message = msg['message'] as Map<String, dynamic>?;
            if (message != null) {
              final msgId = message['id'];
              if (msgId is int) {
                _lastMessageId = msgId;
              } else if (msgId is String) {
                _lastMessageId = int.tryParse(msgId);
              }
              final role = message['role'] as String? ?? 'assistant';
              final content = message['content'] as String? ?? '';
              debugPrint('[Gateway] WS subscribed message: role=$role, id=$_lastMessageId');
              // Emit as a delta for incremental display, then complete
              _messageController.add(GatewayEvent(
                type: GatewayEventType.messageDelta,
                data: {'content': content, 'role': role, 'message_id': msgId},
              ));
              _messageController.add(GatewayEvent(
                type: GatewayEventType.messageComplete,
                data: {'content': content, 'role': role, 'message_id': msgId},
              ));
            }
          } else if (type == 'subscribed') {
            _subscribedSessionId = msg['session_id'] as String?;
            debugPrint('[Gateway] WS subscribed to session: $_subscribedSessionId');
          } else if (type == 'unsubscribed') {
            _subscribedSessionId = null;
            debugPrint('[Gateway] WS unsubscribed from session');
          } else if (type == 'error') {
            _messageController.add(GatewayEvent(type: GatewayEventType.error, data: {'message': msg['message'] as String? ?? 'Error'}));
          } else if (type == 'pong') {
            // heartbeat
          }
        },
        onError: (e) {
          debugPrint('[Gateway] WS error: $e');
          _wsReady = false;
          if (!completer.isCompleted) completer.complete(false);
        },
        onDone: () {
          debugPrint('[Gateway] WS closed');
          _wsReady = false;
          _subscribedSessionId = null;
        },
      );

      final ok = await completer.future.timeout(const Duration(seconds: 3), onTimeout: () { debugPrint('[Gateway] WS timeout'); return false; });
      if (ok) return true;

      // WS failed, close and fall back
      _ws?.sink.close();
      _ws = null;
    } catch (e) {
      debugPrint('[Gateway] WS connect failed: $e');
      _ws?.sink.close();
      _ws = null;
    }

    // Fallback: HTTP health check
    try {
      final health = await getHealth();
      if (health['status'] == 'ok') {
        ref.read(connectionStateProvider.notifier).setConnected();
        debugPrint('[Gateway] HTTP connected');
        return true;
      }
    } catch (e) {
      ref.read(connectionStateProvider.notifier).setError('Cannot reach gateway: $e');
      return false;
    }

    ref.read(connectionStateProvider.notifier).setError('Connection failed');
    return false;
  }

  void disconnect() {
    _ws?.sink.close();
    _ws = null;
    _wsReady = false;
    _subscribedSessionId = null;
    ref.read(connectionStateProvider.notifier).setDisconnected();
  }

  // === Send chat ===
  Future<void> sendChat(String content, {String? sessionId}) async {
    if (_ws != null && _wsReady) {
      _ws!.sink.add(jsonEncode({'type': 'chat', 'session_id': sessionId, 'content': content}));
      // After sending, subscribe to the session so we receive messages from other sources
      if (sessionId != null) {
        subscribeToSession(sessionId, afterId: _lastMessageId);
      }
      return;
    }
    await _sendChatHttp(content, sessionId: sessionId);
  }

  // === WS subscription for real-time message sync ===

  /// Subscribe to receive new messages for [sessionId] via WS.
  /// If [afterId] is provided, only messages with ID > afterId are sent.
  /// This allows real-time sync when other clients (e.g. CLI) send messages.
  void subscribeToSession(String sessionId, {int? afterId}) {
    if (_ws == null || !_wsReady) {
      debugPrint('[Gateway] Cannot subscribe: WS not connected');
      return;
    }
    // Unsubscribe from previous session if different
    if (_subscribedSessionId != null && _subscribedSessionId != sessionId) {
      unsubscribeFromSession();
    }
    final payload = <String, dynamic>{
      'type': 'subscribe',
      'session_id': sessionId,
    };
    if (afterId != null) {
      payload['after_id'] = afterId;
    }
    debugPrint('[Gateway] Subscribing to session $sessionId (afterId=$afterId)');
    _ws!.sink.add(jsonEncode(payload));
  }

  /// Unsubscribe from the current session subscription.
  void unsubscribeFromSession() {
    if (_ws == null || !_wsReady) return;
    if (_subscribedSessionId == null) return;
    debugPrint('[Gateway] Unsubscribing from session $_subscribedSessionId');
    _ws!.sink.add(jsonEncode({'type': 'unsubscribe'}));
    _subscribedSessionId = null;
  }

  /// Update the last known message ID (call this when loading messages).
  void setLastMessageId(int id) {
    if (_lastMessageId == null || id > _lastMessageId!) {
      _lastMessageId = id;
    }
  }

  // === HTTP REST API ===
  Future<Map<String, dynamic>> getHealth() async => await _get('/health', auth: false);

  Future<List<SessionInfo>> getSessions() async {
    final response = await _get('/api/sessions');
    final list = response['data'] as List? ?? [];
    return list.map((s) => SessionInfo.fromJson(s as Map<String, dynamic>)).toList();
  }

  Future<List<ChatMessage>> getSessionMessages(String sessionId, {int? offset, int? limit}) async {
    final queryParams = <String, String>{};
    if (offset != null) queryParams['offset'] = offset.toString();
    if (limit != null) queryParams['limit'] = limit.toString();
    final response = await _get(
      '/api/sessions/$sessionId/messages',
      timeoutSeconds: 30,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
    final list = response['data'] as List? ?? [];
    return list.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>)).toList();
  }

  Future<List<ChatMessage>> getSessionMessagesAll(String sessionId, {int batchSize = 50}) async {
    final allMessages = <ChatMessage>[];
    int offset = 0;

    while (true) {
      final batch = await getSessionMessages(sessionId, offset: offset, limit: batchSize);
      if (batch.isEmpty) break;

      // Deduplicate: if the API doesn't support pagination, it may return
      // all messages on every call. Track seen IDs to avoid duplicates.
      final existingIds = allMessages.map((m) => m.id).toSet();
      final newMessages = batch.where((m) => !existingIds.contains(m.id)).toList();
      if (newMessages.isEmpty) break;

      allMessages.addAll(newMessages);

      // If we got fewer than requested, we've reached the end.
      if (batch.length < batchSize) break;
      offset += batchSize;
    }

    return allMessages;
  }

  Future<Map<String, dynamic>> getCapabilities() async => await _get('/v1/capabilities');

  // === HTTP SSE fallback ===
  Future<void> _sendChatHttp(String content, {String? sessionId}) async {
    try {
      final streamedResponse = await _sendChatRequest(content, sessionId: sessionId);
      String fullContent = '';
      String currentEvent = '';

      await for (final chunk in streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (chunk.startsWith('event: ')) { currentEvent = chunk.substring(7).trim(); continue; }
        if (!chunk.startsWith('data: ')) continue;
        final data = chunk.substring(6).trim();
        if (data == '[DONE]' || data.isEmpty) continue;

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final c = choices[0]['delta']?['content'] as String? ?? '';
            if (c.isNotEmpty) { fullContent += c; _messageController.add(GatewayEvent(type: GatewayEventType.messageDelta, data: {'content': c})); }
            continue;
          }
          if (currentEvent == 'assistant.delta') {
            final c = json['delta'] as String? ?? '';
            if (c.isNotEmpty) { fullContent += c; _messageController.add(GatewayEvent(type: GatewayEventType.messageDelta, data: {'content': c})); }
          } else if (currentEvent == 'assistant.completed') {
            final f = json['content'] as String? ?? '';
            if (f.isNotEmpty) fullContent = f;
          }
        } catch (_) {}
      }
      _messageController.add(GatewayEvent(type: GatewayEventType.messageComplete, data: {'content': fullContent}));
    } catch (e) {
      _messageController.add(GatewayEvent(type: GatewayEventType.error, data: {'message': e.toString()}));
    }
  }

  Future<void> approveAction(String runId, String approvalId, bool approved) async {
    await _post('/v1/runs/$runId/approval', {'approval_id': approvalId, 'approved': approved});
  }

  // === HTTP helpers ===
  http.Client get _client => http.Client();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (config.token != null && config.token!.isNotEmpty) 'Authorization': 'Bearer ${config.token}',
  };

  Future<http.StreamedResponse> _sendChatRequest(String content, {String? sessionId}) async {
    final uri = sessionId != null
        ? Uri.parse('${config.httpUrl}/api/sessions/$sessionId/chat/stream')
        : Uri.parse('${config.httpUrl}/v1/chat/completions');
    final body = sessionId != null ? jsonEncode({'message': content, 'stream': true}) : jsonEncode({'messages': [{'role': 'user', 'content': content}], 'stream': true});
    final request = http.Request('POST', uri)..headers.addAll(_headers)..body = body;
    return await _client.send(request);
  }

  Future<Map<String, dynamic>> _get(String path, {bool auth = true, int timeoutSeconds = 10, Map<String, String>? queryParams}) async {
    var uri = Uri.parse('${config.httpUrl}$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }
    final headers = auth ? _headers : {'Content-Type': 'application/json'};
    final response = await http.get(uri, headers: headers).timeout(Duration(seconds: timeoutSeconds));
    if (response.statusCode >= 400) throw Exception('HTTP ${response.statusCode}: ${response.body}');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('${config.httpUrl}$path');
    final response = await http.post(uri, headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
    if (response.statusCode >= 400) throw Exception('HTTP ${response.statusCode}: ${response.body}');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void dispose() {
    _ws?.sink.close();
    _subscribedSessionId = null;
    _messageController.close();
    _approvalController.close();
  }
}

enum GatewayEventType { messageDelta, messageComplete, toolStart, toolProgress, toolComplete, approval, error, ready, unknown }

class GatewayEvent {
  final GatewayEventType type;
  final Map<String, dynamic> data;
  const GatewayEvent({required this.type, required this.data});
}
