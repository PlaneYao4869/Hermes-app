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

// Gateway service provider - auto-connects when config changes
final gatewayServiceProvider = StateNotifierProvider<GatewayServiceNotifier, GatewayService?>((ref) {
  return GatewayServiceNotifier(ref);
});

class GatewayServiceNotifier extends StateNotifier<GatewayService?> {
  final Ref ref;
  GatewayServiceNotifier(this.ref) : super(null) {
    // Listen to config changes and auto-create + connect
    ref.listen<GatewayConfig?>(gatewayConfigProvider, (prev, next) {
      if (next != null && next != prev) {
        _createAndConnect(next);
      }
    });
  }

  @override
  void dispose() {
    state?.dispose();
    super.dispose();
  }

  Future<void> _createAndConnect(GatewayConfig config) async {
    // Dispose old service before creating new one
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

  Stream<GatewayEvent> get events => _messageController.stream;
  Stream<ApprovalRequest> get approvals => _approvalController.stream;

  GatewayService(this.config, this.ref);

  // === Connection Test ===
  Future<bool> connect() async {
    ref.read(connectionStateProvider.notifier).setConnecting();
    try {
      final health = await getHealth();
      if (health['status'] == 'ok') {
        ref.read(connectionStateProvider.notifier).setConnected();
        debugPrint('[GatewayService] Connected to ${config.httpUrl}');
        return true;
      }
      ref.read(connectionStateProvider.notifier).setError('Gateway not healthy');
      return false;
    } catch (e) {
      ref.read(connectionStateProvider.notifier).setError(e.toString());
      debugPrint('[GatewayService] Connection failed: $e');
      return false;
    }
  }

  void disconnect() {
    ref.read(connectionStateProvider.notifier).setDisconnected();
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

  /// Send a chat message. If sessionId exists, sends to that session (continues conversation).
  /// If no sessionId, uses the general chat completions endpoint.
  Future<String> sendChat(String content, {String? sessionId}) async {
    final streamedResponse = await _sendChatRequest(content, sessionId: sessionId);
    String fullContent = '';
    String currentEvent = '';

    await for (final chunk in streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      // Track SSE event type
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

        // Format 1: OpenAI chat completions — choices[0].delta.content
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

        // Format 2: Hermes session chat — assistant.delta event with delta field
        if (currentEvent == 'assistant.delta') {
          final c = json['delta'] as String? ?? json['content'] as String? ?? '';
          if (c.isNotEmpty) {
            fullContent += c;
            _messageController.add(GatewayEvent(
              type: GatewayEventType.messageDelta,
              data: {'content': c},
            ));
          }
          continue;
        }

        // Format 3: Hermes session chat — assistant.completed (final message)
        if (currentEvent == 'assistant.completed') {
          final finalContent = json['content'] as String? ?? '';
          if (finalContent.isNotEmpty) {
            fullContent = finalContent;
          }
          continue;
        }

        // Format 4: Hermes session chat — message.started, run.started, run.completed (metadata)
        if (currentEvent == 'message.started' || currentEvent == 'run.started' || currentEvent == 'run.completed') {
          continue;
        }

        // Format 5: tool.progress events
        if (currentEvent == 'tool.progress') {
          _messageController.add(GatewayEvent(
            type: GatewayEventType.toolStart,
            data: {
              'id': json['message_id'] as String? ?? '',
              'name': json['tool_name'] as String? ?? '',
              'preview': json['preview'] as String? ?? '',
            },
          ));
          continue;
        }
      } catch (_) {}
    }

    _messageController.add(GatewayEvent(
      type: GatewayEventType.messageComplete,
      data: {'content': fullContent},
    ));

    return fullContent;
  }

  Future<AgentRun> createRun(String prompt, {String? sessionId}) async {
    final body = <String, dynamic>{'model': 'default', 'input': prompt};
    if (sessionId != null) body['session_id'] = sessionId;
    final response = await _post('/v1/runs', body);
    return AgentRun.fromJson(response);
  }

  Future<AgentRun> getRun(String runId) async {
    final response = await _get('/v1/runs/$runId');
    return AgentRun.fromJson(response);
  }

  Future<void> approveAction(String runId, String approvalId, bool approved) async {
    await _post('/v1/runs/$runId/approval', {'approval_id': approvalId, 'approved': approved});
  }

  Future<void> stopRun(String runId) async {
    await _post('/v1/runs/$runId/stop', {});
  }

  Future<Map<String, dynamic>> getCapabilities() async {
    return await _get('/v1/capabilities');
  }

  // === HTTP helpers ===
  Future<http.StreamedResponse> _sendChatRequest(String content, {String? sessionId}) async {
    http.Request request;
    if (sessionId != null) {
      // Continue existing session via session-specific endpoint
      final uri = Uri.parse('${config.httpUrl}/api/sessions/$sessionId/chat/stream');
      request = http.Request('POST', uri);
      request.headers.addAll(_headers);
      request.body = jsonEncode({'message': content, 'stream': true});
    } else {
      // New conversation via general chat completions
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

  http.Client get _client => http.Client();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (config.token != null && config.token!.isNotEmpty)
      'Authorization': 'Bearer ${config.token}',
  };

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
