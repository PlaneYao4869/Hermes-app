import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/network/gateway_service.dart';
import '../../core/models/session.dart';
import '../../core/theme/app_theme.dart';

final sessionsProvider = FutureProvider<List<SessionInfo>>((ref) async {
  final gateway = ref.watch(gatewayServiceProvider);
  if (gateway == null) return [];
  return gateway.getSessions();
});

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('会话历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(sessionsProvider),
          ),
        ],
      ),
      body: sessionsAsync.when(
        data: (sessions) => sessions.isEmpty
            ? const Center(child: Text('暂无会话', style: TextStyle(color: Colors.grey)))
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(sessionsProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: sessions.length,
                  itemBuilder: (context, index) => _SessionTile(session: sessions[index]),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text('加载失败: $e', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(sessionsProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final SessionInfo session;
  const _SessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _platformColor(session.platform).withOpacity(0.2),
          child: Icon(_platformIcon(session.platform), color: _platformColor(session.platform), size: 20),
        ),
        title: Text(
          session.title ?? '会话 ${session.id.substring(0, 8)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${session.platform} · ${session.messageCount} 条消息 · ${_formatTime(session.updatedAt)}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () {
          // TODO: Navigate to session detail and load messages
        },
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return DateFormat('MM/dd HH:mm').format(dt);
  }

  IconData _platformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'telegram': return Icons.telegram;
      case 'discord': return Icons.discord;
      case 'feishu': return Icons.chat;
      case 'cli': return Icons.terminal;
      default: return Icons.devices;
    }
  }

  Color _platformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'telegram': return const Color(0xFF0088cc);
      case 'discord': return const Color(0xFF5865F2);
      case 'feishu': return const Color(0xFF3370FF);
      case 'cli': return Colors.green;
      default: return Colors.grey;
    }
  }
}
