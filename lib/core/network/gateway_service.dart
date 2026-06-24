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

// Main gateway service provider
final gatewayServiceProvider = Provider<GatewayService?>((ref) {
  final config = ref.watch(gatewayConfigProvider);
  if (config == null) return null;
  return GatewayService(config, ref);
});

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
        return true;
      }
      ref.read(connectionStateProvider.notifier).setError('Gateway not healthy');
      return false;
    } catch (e) {
      ref.read(connectionStateProvider.notifier).setError(e.toString());
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

  /// Send a chat message via the streaming endpoint. Returns a stream of events.
  Future<String> sendChat(String content, {String? sessionId}) async {
    final body = <String, dynamic>{
      'messages': [
        {'role': 'user', 'content': content}
      ],
      'stream': true,
    };
    if (sessionId != null) body['session_id'] = sessionId;

    final uri = Uri.parse('${config.httpUrl}/v1/chat/completions');
    final request = http.Request('POST', uri);
    request.headers.addAll(_headers);
    request.body = jsonEncode(body);

    final streamedResponse = await _client.send(request);
    String fullContent = '';
    String? runId;

    await for (final chunk in streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (chunk.startsWith('data: ')) {
        final data = chunk.substring(6).trim();
        if (data == '[DONE]') break;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            if (delta != null) {
              final content = delta['content'] as String? ?? '';
              if (content.isNotEmpty) {
                fullContent += content;
                _messageController.add(GatewayEvent(
                  type: GatewayEventType.messageDelta,
                  data: {'content': content},
                ));
              }
            }
          }
          // Check for run_id in response
          if (json.containsKey('run_id')) {
            runId = json['run_id'] as String?;
          }
        } catch (_) {}
      }
    }

    _messageController.add(GatewayEvent(
      type: GatewayEventType.messageComplete,
      data: {'content': fullContent},
    ));

    return fullContent;
  }

  /// Start a run (async agent task)
  Future<AgentRun> createRun(String prompt, {String? sessionId}) async {
    final body = <String, dynamic>{
      'model': 'default',
      'input': prompt,
    };
    if (sessionId != null) body['session_id'] = sessionId;
    final response = await _post('/v1/runs', body);
    return AgentRun.fromJson(response);
  }

  Future<AgentRun> getRun(String runId) async {
    final response = await _get('/v1/runs/$runId');
    return AgentRun.fromJson(response);
  }

  /// Stream run events via SSE
  Stream<AgentEvent> streamRunEvents(String runId) async* {
    final uri = Uri.parse('${config.httpUrl}/v1/runs/$runId/events');
    final request = http.Request('GET', uri);
    request.headers.addAll(_headers);

    final streamedResponse = await _client.send(request);

    await for (final chunk in streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (chunk.startsWith('data: ')) {
        final data = chunk.substring(6).trim();
        if (data.isEmpty) continue;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          yield AgentEvent.fromJson(json);
        } catch (_) {}
      }
    }
  }

  Future<void> approveAction(String runId, String approvalId, bool approved) async {
    await _post('/v1/runs/$runId/approval', {
      'approval_id': approvalId,
      'approved': approved,
    });
  }

  Future<void> stopRun(String runId) async {
    await _post('/v1/runs/$runId/stop', {});
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

  Future<Map<String, dynamic>> _get(String path, {bool auth = true}) async {
    final uri = Uri.parse('${config.httpUrl}$path');
    final headers = auth ? _headers : {'Content-Type': 'application/json'};
    final response = await http.get(uri, headers: headers);
    if (response.statusCode >= 400) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('${config.httpUrl}$path');
    final response = await http.post(uri, headers: _headers, body: jsonEncode(body));
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
