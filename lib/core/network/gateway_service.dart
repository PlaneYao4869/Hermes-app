import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
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

  bool _connected = false;

  Stream<GatewayEvent> get events => _messageController.stream;
  Stream<ApprovalRequest> get approvals => _approvalController.stream;

  GatewayService(this.config, this.ref);

  // === HTTP Connection ===
  Future<bool> connect() async {
    ref.read(connectionStateProvider.notifier).setConnecting();

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

    // Connected via HTTP (REST + SSE) — no WebSocket needed
    _connected = true;
    ref.read(connectionStateProvider.notifier).setConnected();
    debugPrint('[GatewayService] HTTP connected to ${config.httpUrl}');
    return true;
  }

  void disconnect() {
    _connected = false;
    ref.read(connectionStateProvider.notifier).setDisconnected();
  }

  // === Send chat via HTTP SSE ===
  Future<void> sendChat(String content, {String? sessionId}) async {
    await _sendChatHttp(content, sessionId: sessionId);
  }

  // === HTTP SSE streaming ===
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
    final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 1));
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
