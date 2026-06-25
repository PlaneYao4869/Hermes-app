class GatewayConfig {
  final String host;
  final int httpPort;
  final int wsPort;
  final String? token;
  final bool useTls;
  final String? tailscaleIp;

  const GatewayConfig({
    required this.host,
    this.httpPort = 8642,
    this.wsPort = 8643,
    this.token,
    this.useTls = false,
    this.tailscaleIp,
  });

  String get wsUrl {
    final scheme = useTls ? 'wss' : 'ws';
    final actualHost = tailscaleIp ?? host;
    return '$scheme://$actualHost:$wsPort/ws';
  }

  String get httpUrl {
    final scheme = useTls ? 'https' : 'http';
    final actualHost = tailscaleIp ?? host;
    return '$scheme://$actualHost:$httpPort';
  }
}
