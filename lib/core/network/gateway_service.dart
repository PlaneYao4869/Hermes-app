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

  Stream<GatewayEvent> get events => _messageController.stream;
  Stream<ApprovalRequest> get approvals => _approvalController.stream;

  GatewayService(this.config, this.ref);

  Future<bool> connect() async {
    ref.read(connectionStateProvider.notifier).setConnecting();

    // Try WebSocket on port 8643
    try {
      final wsUrl = 'ws://${config.host}:8643/ws';
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
    ref.read(connectionStateProvider.notifier).setDisconnected();
  }

  // === Send chat ===
  Future<void> sendChat(String content, {String? sessionId}) async {
    if (_ws != null && _wsReady) {
      _ws!.sink.add(jsonEncode({'type': 'chat', 'session_id': sessionId, 'content': content}));
      return;
    }
    await _sendChatHttp(content, sessionId: sessionId);
  }

  // === HTTP REST API ===
  Future<Map<String, dynamic>> getHealth() async => await _get('/health', auth: false);

  Future<List<SessionInfo>> getSessions() async {
    final response = await _get('/api/sessions');
    final list = response['data'] as List? ?? [];
    return list.map((s) => SessionInfo.fromJson(s as Map<String, dynamic>)).toList();
  }

  Future<List<ChatMessage>> getSessionMessages(String sessionId) async {
    final response = await _get('/api/sessions/$sessionId/messages');
    final list = response['data'] as List? ?? [];
    return list.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>)).toList();
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

  Future<Map<String, dynamic>> _get(String path, {bool auth = true}) async {
    final uri = Uri.parse('${config.httpUrl}$path');
    final headers = auth ? _headers : {'Content-Type': 'application/json'};
    final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
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
