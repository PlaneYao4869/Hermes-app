class GatewayConfig {
  final String host;
  final int port;
  final String? token;
  final bool useTls;
  final String? tailscaleIp;

  const GatewayConfig({
    required this.host,
    this.port = 8642,
    this.token,
    this.useTls = false,
    this.tailscaleIp,
  });

  String get wsUrl {
    final scheme = useTls ? 'wss' : 'ws';
    final actualHost = tailscaleIp ?? host;
    return '$scheme://$actualHost:$port/api/ws';
  }

  String get httpUrl {
    final scheme = useTls ? 'https' : 'http';
    final actualHost = tailscaleIp ?? host;
    return '$scheme://$actualHost:$port';
  }
}
