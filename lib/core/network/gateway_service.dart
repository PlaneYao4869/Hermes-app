import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
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
  WebSocketChannel? _channel;
  Timer? _heartbeat;
  Timer? _reconnect;
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 10;

  final _messageController = StreamController<GatewayEvent>.broadcast();
  final _approvalController = StreamController<ApprovalRequest>.broadcast();

  Stream<GatewayEvent> get events => _messageController.stream;
  Stream<ApprovalRequest> get approvals => _approvalController.stream;

  GatewayService(this.config, this.ref);

  // === WebSocket Connection ===
  Future<void> connect() async {
    ref.read(connectionStateProvider.notifier).setConnecting();
    try {
      final uri = Uri.parse(config.wsUrl);
      final headers = <String, String>{};
      if (config.token != null) {
        headers['Authorization'] = 'Bearer ${config.token}';
      }

      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (data) {
          _reconnectAttempts = 0;
          ref.read(connectionStateProvider.notifier).setConnected();
          _handleMessage(data);
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          ref.read(connectionStateProvider.notifier).setError(error.toString());
          _scheduleReconnect();
        },
        onDone: () {
          ref.read(connectionStateProvider.notifier).setDisconnected();
          _scheduleReconnect();
        },
      );

      _startHeartbeat();
    } catch (e) {
      ref.read(connectionStateProvider.notifier).setError(e.toString());
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String);
      final event = json['event'] as String? ?? json['method'] as String?;

      switch (event) {
        case 'message.delta':
          _messageController.add(GatewayEvent(
            type: GatewayEventType.messageDelta,
            data: json['params'] ?? json,
          ));
          break;
        case 'message.complete':
          _messageController.add(GatewayEvent(
            type: GatewayEventType.messageComplete,
            data: json['params'] ?? json,
          ));
          break;
        case 'tool.start':
          _messageController.add(GatewayEvent(
            type: GatewayEventType.toolStart,
            data: json['params'] ?? json,
          ));
          break;
        case 'tool.progress':
          _messageController.add(GatewayEvent(
            type: GatewayEventType.toolProgress,
            data: json['params'] ?? json,
          ));
          break;
        case 'tool.complete':
          _messageController.add(GatewayEvent(
            type: GatewayEventType.toolComplete,
            data: json['params'] ?? json,
          ));
          break;
        case 'approval.request':
          final approval = ApprovalRequest.fromJson(json['params'] ?? json);
          _approvalController.add(approval);
          break;
        case 'error':
          _messageController.add(GatewayEvent(
            type: GatewayEventType.error,
            data: json['params'] ?? json,
          ));
          break;
        case 'gateway.ready':
          _messageController.add(GatewayEvent(
            type: GatewayEventType.ready,
            data: json,
          ));
          break;
        default:
          _messageController.add(GatewayEvent(
            type: GatewayEventType.unknown,
            data: json,
          ));
      }
    } catch (e) {
      debugPrint('Failed to parse message: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      try {
        _channel?.sink.add(jsonEncode({'method': 'ping'}));
      } catch (_) {}
    });
  }

  void _scheduleReconnect() {
    _heartbeat?.cancel();
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      ref.read(connectionStateProvider.notifier).setError('Max reconnect attempts reached');
      return;
    }
    final delay = Duration(seconds: (1 << _reconnectAttempts).clamp(1, 60));
    _reconnectAttempts++;
    _reconnect?.cancel();
    _reconnect = Timer(delay, () => connect());
  }

  // === REST API Methods ===

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

  Future<void> approveAction(String runId, String approvalId, bool approved) async {
    await _post('/v1/runs/$runId/approval', {
      'approval_id': approvalId,
      'approved': approved,
    });
  }

  Future<void> stopRun(String runId) async {
    await _post('/v1/runs/$runId/stop', {});
  }

  Future<Map<String, dynamic>> getHealth() async {
    return await _get('/health');
  }

  // === Chat via WebSocket ===
  void sendChatMessage(String content, {String? sessionId}) {
    final msg = {
      'method': 'chat.send',
      'params': {
        'content': content,
        if (sessionId != null) 'session_id': sessionId,
      },
    };
    _channel?.sink.add(jsonEncode(msg));
  }

  // === HTTP helpers ===
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (config.token != null) 'Authorization': 'Bearer ${config.token}',
  };

  Future<Map<String, dynamic>> _get(String path) async {
    final uri = Uri.parse('${config.httpUrl}$path');
    final response = await http.get(uri, headers: _headers);
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

  void disconnect() {
    _heartbeat?.cancel();
    _reconnect?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
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
