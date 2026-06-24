import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class HermesConnectionState {
  final ConnectionStatus status;
  final String? errorMessage;
  final DateTime? lastConnected;

  const HermesConnectionState({
    this.status = ConnectionStatus.disconnected,
    this.errorMessage,
    this.lastConnected,
  });

  bool get isConnected => status == ConnectionStatus.connected;
  bool get isConnecting => status == ConnectionStatus.connecting;
  String get displayText {
    switch (status) {
      case ConnectionStatus.connected: return '已连接';
      case ConnectionStatus.connecting: return '连接中...';
      case ConnectionStatus.disconnected: return '未连接';
      case ConnectionStatus.error: return '错误: ${errorMessage ?? "未知"}';
    }
  }
}

class ConnectionStateNotifier extends StateNotifier<HermesConnectionState> {
  ConnectionStateNotifier() : super(const HermesConnectionState());

  void setConnecting() => state = const HermesConnectionState(status: ConnectionStatus.connecting);
  void setConnected() => state = HermesConnectionState(
    status: ConnectionStatus.connected,
    lastConnected: DateTime.now(),
  );
  void setDisconnected() => state = const HermesConnectionState(status: ConnectionStatus.disconnected);
  void setError(String msg) => state = HermesConnectionState(
    status: ConnectionStatus.error,
    errorMessage: msg,
  );
}
