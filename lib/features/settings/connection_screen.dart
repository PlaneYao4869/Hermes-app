import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/network/gateway_service.dart';
import '../../core/network/connection_state.dart';
import '../../core/models/gateway_config.dart';
import '../../core/theme/app_theme.dart';
import 'mdns_discovery.dart';

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  List<DiscoveredService> _discoveredServices = [];
  bool _isScanning = false;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  void _startDiscovery() {
    setState(() => _isScanning = true);
    MdnsDiscovery.discover().then((services) {
      if (mounted) {
        setState(() {
          _discoveredServices = services;
          _isScanning = false;
        });
      }
    });
    // Also try direct LAN scan as fallback
    _scanTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _isScanning) {
        setState(() => _isScanning = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final connState = ref.watch(connectionStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('连接到 Hermes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current connection status
          if (connState.isConnected)
            _StatusCard(
              icon: Icons.check_circle,
              color: AppTheme.success,
              title: '已连接',
              subtitle: ref.read(gatewayConfigProvider)?.httpUrl ?? '',
              action: TextButton(
                onPressed: () {
                  ref.read(gatewayServiceProvider)?.disconnect();
                  ref.read(connectionStateProvider.notifier).setDisconnected();
                },
                child: const Text('断开'),
              ),
            ),

          const SizedBox(height: 24),

          // QR Code scan button (prominent)
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: () => _openQrScanner(context),
              icon: const Icon(Icons.qr_code_scanner, size: 28),
              label: const Text('扫码连接', style: TextStyle(fontSize: 18)),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),

          const SizedBox(height: 8),
          const Text(
            '在 Hermes Studio 或终端中生成 QR 码，手机扫码即可连接',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),

          const SizedBox(height: 32),

          // mDNS auto-discovery section
          Row(
            children: [
              const Icon(Icons.radar, size: 20, color: Colors.grey),
              const SizedBox(width: 8),
              const Text('局域网自动发现', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_isScanning)
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _startDiscovery,
              ),
            ],
          ),

          const SizedBox(height: 8),

          if (_discoveredServices.isEmpty && !_isScanning)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '未发现设备\n请确保手机和 PC 在同一局域网，且 Hermes Gateway 已启动',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            )
          else
            ..._discoveredServices.map((service) => _DiscoveredDeviceCard(
              service: service,
              onTap: () => _connectToService(service),
            )),

          const SizedBox(height: 32),

          // Manual input (collapsible)
          ExpansionTile(
            leading: const Icon(Icons.edit, color: Colors.grey),
            title: const Text('手动输入'),
            children: [
              _ManualConnectForm(onConnect: (config) => _connect(config)),
            ],
          ),
        ],
      ),
    );
  }

  void _openQrScanner(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _QrScanPage(onScanned: (config) {
        Navigator.pop(context);
        _connect(config);
      })),
    );
  }

  void _connectToService(DiscoveredService service) {
    final config = GatewayConfig(
      host: service.host,
      port: service.port,
    );
    _connect(config);
  }

  void _connect(GatewayConfig config) {
    // Just set config — the provider auto-creates service and connects
    ref.read(gatewayConfigProvider.notifier).configure(config);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在连接 \${config.host}:\${config.port}...')),
    );

    // Listen for connection result
    late final ProviderSubscription sub;
    sub = ref.listenManual(connectionStateProvider, (prev, next) {
      if (next.isConnected) {
        sub.close();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('连接成功!')),
          );
          Navigator.pop(context);
        }
      } else if (next.status == ConnectionStatus.error) {
        sub.close();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('连接失败: \${next.errorMessage ?? "未知错误"}'), backgroundColor: Colors.red),
          );
        }
      }
    });
  }
}

// === QR Scan Page ===
class _QrScanPage extends StatefulWidget {
  final ValueChanged<GatewayConfig> onScanned;
  const _QrScanPage({required this.onScanned});

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      try {
        final config = _parseQrData(raw);
        if (config != null) {
          _handled = true;
          widget.onScanned(config);
          return;
        }
      } catch (_) {}
    }
  }

  GatewayConfig? _parseQrData(String data) {
    // Try JSON format: {"ws":"ws://host:port/api/ws","token":"...","name":"..."}
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final wsUrl = json['ws'] as String? ?? json['url'] as String?;
      if (wsUrl != null) {
        final uri = Uri.parse(wsUrl);
        return GatewayConfig(
          host: uri.host,
          port: uri.port,
          token: json['token'] as String?,
        );
      }
      // Also try: {"host":"...","port":8642,"token":"..."}
      final host = json['host'] as String?;
      if (host != null) {
        return GatewayConfig(
          host: host,
          port: json['port'] as int? ?? 8642,
          token: json['token'] as String?,
        );
      }
    } catch (_) {}

    // Try plain URL: ws://host:port/api/ws or http://host:port
    if (data.startsWith('ws://') || data.startsWith('wss://') ||
        data.startsWith('http://') || data.startsWith('https://')) {
      final uri = Uri.parse(data);
      return GatewayConfig(
        host: uri.host,
        port: uri.port,
      );
    }

    // Try host:port format
    if (data.contains(':') && !data.contains('{')) {
      final parts = data.split(':');
      if (parts.length == 2) {
        final port = int.tryParse(parts[1]);
        if (port != null) {
          return GatewayConfig(host: parts[0], port: port);
        }
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描 QR 码'),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: _onDetect,
              overlayBuilder: (context, constraints) {
                return Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.primaryDark, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            color: Colors.black,
            child: const Text(
              '将 QR 码对准扫描框\n支持 Hermes Studio 生成的配对码',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// === Discovered Device Card ===
class _DiscoveredDeviceCard extends StatelessWidget {
  final DiscoveredService service;
  final VoidCallback onTap;

  const _DiscoveredDeviceCard({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.success.withOpacity(0.2),
          child: const Icon(Icons.computer, color: AppTheme.success, size: 20),
        ),
        title: Text(service.name, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text('${service.host}:${service.port}', style: const TextStyle(fontSize: 12)),
        trailing: FilledButton.tonal(
          onPressed: onTap,
          child: const Text('连接'),
        ),
      ),
    );
  }
}

// === Manual Connect Form ===
class _ManualConnectForm extends StatefulWidget {
  final ValueChanged<GatewayConfig> onConnect;
  const _ManualConnectForm({required this.onConnect});

  @override
  State<_ManualConnectForm> createState() => _ManualConnectFormState();
}

class _ManualConnectFormState extends State<_ManualConnectForm> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '8642');
  final _tokenController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: '主机地址',
              hintText: '192.168.1.100 或 tailscale-ip',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portController,
            decoration: const InputDecoration(labelText: '端口'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            decoration: const InputDecoration(labelText: 'Token (可选)'),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final config = GatewayConfig(
                  host: _hostController.text.trim(),
                  port: int.tryParse(_portController.text) ?? 8642,
                  token: _tokenController.text.isNotEmpty ? _tokenController.text : null,
                );
                widget.onConnect(config);
              },
              child: const Text('连接'),
            ),
          ),
        ],
      ),
    );
  }
}

// === Status Card ===
class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? action;

  const _StatusCard({
    required this.icon, required this.color,
    required this.title, required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}
