import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/gateway_service.dart';
import '../../core/network/connection_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/models/gateway_config.dart';
import 'connection_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState = ref.watch(connectionStateProvider);
    final config = ref.watch(gatewayConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // Connection section
          _SectionHeader(title: '连接'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    connState.isConnected ? Icons.wifi : Icons.wifi_off,
                    color: connState.isConnected ? AppTheme.success : AppTheme.error,
                  ),
                  title: Text(connState.displayText),
                  subtitle: config != null ? Text('${config.host}:${config.port}') : const Text('未配置'),
                  trailing: const Icon(Icons.edit),
                  onTap: () => _showConnectionDialog(context, ref),
                ),
                if (connState.isConnected)
                  ListTile(
                    leading: const Icon(Icons.health_and_safety, color: Colors.green),
                    title: const Text('健康检查'),
                    onTap: () async {
                      final gateway = ref.read(gatewayServiceProvider);
                      if (gateway != null) {
                        try {
                          final health = await gateway.getHealth();
                          if (context.mounted) {
                            showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Gateway 状态'),
                                content: Text(health.toString()),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('检查失败: $e')),
                            );
                          }
                        }
                      }
                    },
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Appearance section
          _SectionHeader(title: '外观'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dark_mode),
                  title: const Text('深色模式'),
                  trailing: Switch(
                    value: Theme.of(context).brightness == Brightness.dark,
                    onChanged: (v) {
                      // Toggle theme
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // About section
          _SectionHeader(title: '关于'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Hermes Mobile'),
                  subtitle: Text('v1.0.0 · AI Agent 远程控制'),
                ),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('GitHub'),
                  subtitle: const Text('查看源码'),
                  onTap: () {
                    // Launch URL
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showConnectionDialog(BuildContext context, WidgetRef ref) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionScreen()));
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
