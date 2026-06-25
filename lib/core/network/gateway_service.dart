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

// Connection state provider
final connectionStateProvider = StateNotifierProvider<ConnectionStateNotifier, HermesConnectionState>((ref) {
  return ConnectionStateNotifier();
});

// Gateway config provider
final gatewayConfigProvider = StateNotifierProvider<GatewayConfigNotifier, GatewayConfig?>((ref) {
  return GatewayConfigNotifier();
});

class GatewayConfigNotifier extends StateNotifier<GatewayConfig?> {
  GatewayConfigNotifier() : super(null);
  void configure(GatewayConfig config) => state = config;
}

// Gateway service provider
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

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSub;
  bool _connected = false;
  int _msgId = 0;

  Stream<GatewayEvent> get events => _messageController.stream;
  Stream<ApprovalRequest> get approvals => _approvalController.stream;

  GatewayService(this.config, this.ref);

  // === WebSocket Connection ===
  Future<bool> connect() async {
    ref.read(connectionStateProvider.notifier).setConnecting();

    // First test HTTP health
    try {
      final health = await getHealth();
      if (health['status'] != 'ok') {
        ref.read(connectionStateProvider.notifier).setError('Gateway not healthy');
        return false;
      }
    } catch (e) {
      ref.read(connectionStateProvider.notifier).setError('Cannot reach gateway: $e');
      return false;
    }

    // Connect WebSocket to proxy (port = gateway port + 1)
    try {
      final wsPort = config.port + 1; // 8643
      final wsUrl = 'ws://${config.host}:$wsPort/ws';
      debugPrint('[GatewayService] Connecting WebSocket: $wsUrl');

      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Wait for ready signal
      final completer = Completer<bool>();
      _wsSub = _wsChannel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            final type = msg['type'] as String? ?? '';

            if (type == 'ready' && !completer.isCompleted) {
              _connected = true;
              ref.read(connectionStateProvider.notifier).setConnected();
              completer.complete(true);
              debugPrint('[GatewayService] WebSocket connected');
            } else if (type == 'delta') {
              _messageController.add(GatewayEvent(
                type: GatewayEventType.messageDelta,
                data: {'content': msg['content'] as String? ?? ''},
              ));
            } else if (type == 'done') {
              _messageController.add(GatewayEvent(
                type: GatewayEventType.messageComplete,
                data: {'content': msg['content'] as String? ?? ''},
              ));
            } else if (type == 'error') {
              _messageController.add(GatewayEvent(
                type: GatewayEventType.error,
                data: {'message': msg['message'] as String? ?? 'Unknown error'},
              ));
            } else if (type == 'pong') {
              // Heartbeat response
            }
          } catch (e) {
            debugPrint('[GatewayService] WS parse error: $e');
          }
        },
        onError: (error) {
          debugPrint('[GatewayService] WS error: $error');
          _connected = false;
          ref.read(connectionStateProvider.notifier).setError('WebSocket error: $error');
          if (!completer.isCompleted) completer.complete(false);
        },
        onDone: () {
          debugPrint('[GatewayService] WS closed');
          _connected = false;
          if (!completer.isCompleted) completer.complete(false);
        },
      );

      // Timeout
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('[GatewayService] WS timeout, falling back to HTTP mode');
          _connected = true; // Still usable via HTTP
          ref.read(connectionStateProvider.notifier).setConnected();
          return true;
        },
      );
    } catch (e) {
      debugPrint('[GatewayService] WS connect failed: $e, using HTTP mode');
      _connected = true; // Fallback to HTTP
      ref.read(connectionStateProvider.notifier).setConnected();
      return true;
    }
  }

  void disconnect() {
    _wsSub?.cancel();
    _wsChannel?.sink.close();
    _wsChannel = null;
    _connected = false;
    ref.read(connectionStateProvider.notifier).setDisconnected();
  }

  // === Send chat via WebSocket ===
  Future<void> sendChat(String content, {String? sessionId}) async {
    if (_wsChannel != null && _connected) {
      // Send via WebSocket
      final msgId = ++_msgId;
      _wsChannel!.sink.add(jsonEncode({
        'type': 'chat',
        'session_id': sessionId,
        'content': content,
        'id': msgId,
      }));
    } else {
      // Fallback to HTTP SSE
      await _sendChatHttp(content, sessionId: sessionId);
    }
  }

  // === HTTP SSE fallback ===
  Future<void> _sendChatHttp(String content, {String? sessionId}) async {
    try {
      final streamedResponse = await _sendChatRequest(content, sessionId: sessionId);
      String fullContent = '';
      String currentEvent = '';

      await for (final chunk in streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (chunk.startsWith('event: ')) {
          currentEvent = chunk.substring(7).trim();
          continue;
        }
        if (!chunk.startsWith('data: ')) continue;

        final data = chunk.substring(6).trim();
        if (data == '[DONE]') break;
        if (data.isEmpty) continue;

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;

          // OpenAI format
          final choices = json['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            if (delta != null) {
              final c = delta['content'] as String? ?? '';
              if (c.isNotEmpty) {
                fullContent += c;
                _messageController.add(GatewayEvent(
                  type: GatewayEventType.messageDelta,
                  data: {'content': c},
                ));
              }
            }
            continue;
          }

          // Hermes session format
          if (currentEvent == 'assistant.delta') {
            final c = json['delta'] as String? ?? '';
            if (c.isNotEmpty) {
              fullContent += c;
              _messageController.add(GatewayEvent(
                type: GatewayEventType.messageDelta,
                data: {'content': c},
              ));
            }
            continue;
          }

          if (currentEvent == 'assistant.completed') {
            final finalContent = json['content'] as String? ?? '';
            if (finalContent.isNotEmpty) fullContent = finalContent;
            continue;
          }

          if (currentEvent == 'message.started' || currentEvent == 'run.started' || currentEvent == 'run.completed') {
            continue;
          }
        } catch (_) {}
      }

      _messageController.add(GatewayEvent(
        type: GatewayEventType.messageComplete,
        data: {'content': fullContent},
      ));
    } catch (e) {
      _messageController.add(GatewayEvent(
        type: GatewayEventType.error,
        data: {'message': e.toString()},
      ));
    }
  }

  // === REST API Methods ===
  Future<Map<String, dynamic>> getHealth() async {
    return await _get('/health', auth: false);
  }

  Future<List<SessionInfo>> getSessions() async {
    final response = await _get('/api/sessions');
    final list = response['sessions'] as List? ?? response['data'] as List? ?? [];
    return list.map((s) => SessionInfo.fromJson(s as Map<String, dynamic>)).toList();
  }

  Future<List<ChatMessage>> getSessionMessages(String sessionId) async {
    final response = await _get('/api/sessions/$sessionId/messages');
    final list = response['messages'] as List? ?? response['data'] as List? ?? [];
    return list.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>)).toList();
  }

  Future<AgentRun> createRun(String prompt, {String? sessionId}) async {
    final body = <String, dynamic>{'model': 'default', 'input': prompt};
    if (sessionId != null) body['session_id'] = sessionId;
    final response = await _post('/v1/runs', body);
    return AgentRun.fromJson(response);
  }

  Future<void> approveAction(String runId, String approvalId, bool approved) async {
    await _post('/v1/runs/$runId/approval', {'approval_id': approvalId, 'approved': approved});
  }

  Future<Map<String, dynamic>> getCapabilities() async {
    return await _get('/v1/capabilities');
  }

  // === HTTP helpers ===
  http.Client get _client => http.Client();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (config.token != null && config.token!.isNotEmpty)
      'Authorization': 'Bearer ${config.token}',
  };

  Future<http.StreamedResponse> _sendChatRequest(String content, {String? sessionId}) async {
    http.Request request;
    if (sessionId != null) {
      final uri = Uri.parse('${config.httpUrl}/api/sessions/$sessionId/chat/stream');
      request = http.Request('POST', uri);
      request.headers.addAll(_headers);
      request.body = jsonEncode({'message': content, 'stream': true});
    } else {
      final uri = Uri.parse('${config.httpUrl}/v1/chat/completions');
      request = http.Request('POST', uri);
      request.headers.addAll(_headers);
      request.body = jsonEncode({
        'messages': [{'role': 'user', 'content': content}],
        'stream': true,
      });
    }
    return await _client.send(request);
  }

  Future<Map<String, dynamic>> _get(String path, {bool auth = true}) async {
    final uri = Uri.parse('${config.httpUrl}$path');
    final headers = auth ? _headers : {'Content-Type': 'application/json'};
    final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
    if (response.statusCode >= 400) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('${config.httpUrl}$path');
    final response = await http.post(uri, headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
    if (response.statusCode >= 400) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void dispose() {
    _wsSub?.cancel();
    _wsChannel?.sink.close();
    _messageController.close();
    _approvalController.close();
  }
}

// Gateway events
enum GatewayEventType {
  messageDelta, messageComplete,
  toolStart, toolProgress, toolComplete,
  approval, error, ready, unknown,
}

class GatewayEvent {
  final GatewayEventType type;
  final Map<String, dynamic> data;
  const GatewayEvent({required this.type, required this.data});
}
