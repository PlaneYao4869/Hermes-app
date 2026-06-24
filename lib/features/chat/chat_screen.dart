import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/gateway_service.dart';
import '../../core/models/gateway_config.dart';
import '../../core/network/connection_state.dart';
import '../../core/models/message.dart';
import '../../core/models/approval.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/message_bubble.dart';
import 'widgets/approval_sheet.dart';
import 'widgets/voice_input_button.dart';
import 'chat_controller.dart';
import '../settings/connection_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    ref.read(chatControllerProvider.notifier).sendMessage(text);
    _inputController.clear();
    _focusNode.requestFocus();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider);
    final connState = ref.watch(connectionStateProvider);
    final pendingApproval = ref.watch(pendingApprovalProvider);

    // Listen for new messages to auto-scroll
    ref.listen(chatMessagesProvider, (prev, next) {
      if (prev != null && next.length > prev.length) {
        _scrollToBottom();
      }
    });

    // Listen for approval requests
    ref.listen(pendingApprovalProvider, (prev, next) {
      if (next != null) {
        _showApprovalSheet(next);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hermes', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              connState.displayText,
              style: TextStyle(
                fontSize: 12,
                color: connState.isConnected ? AppTheme.success : AppTheme.warning,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () => ref.read(chatControllerProvider.notifier).newSession(),
            tooltip: '新会话',
          ),
          IconButton(
            icon: Icon(
              connState.isConnected ? Icons.wifi : Icons.wifi_off,
              color: connState.isConnected ? AppTheme.success : AppTheme.error,
            ),
            onPressed: () => _showConnectionDialog(),
            tooltip: '连接设置',
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) => MessageBubble(message: messages[index]),
                  ),
          ),
          // Input area
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, size: 64, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text('连接到你的 Hermes Agent', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('发送消息开始对话', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showConnectionDialog(),
            icon: const Icon(Icons.settings_ethernet),
            label: const Text('配置连接'),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            VoiceInputButton(
              onResult: (text) {
                _inputController.text = text;
                _inputController.selection = TextSelection.fromPosition(
                  TextPosition(offset: text.length),
                );
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: _inputController,
                  focusNode: _focusNode,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '输入消息...',
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sendMessage,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }

  void _showApprovalSheet(ApprovalRequest approval) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ApprovalSheet(approval: approval),
    );
  }

  void _showConnectionDialog() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ConnectionScreen()));
  }
}

// Connection Dialog
class ConnectionDialog extends ConsumerStatefulWidget {
  const ConnectionDialog({super.key});

  @override
  ConsumerState<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends ConsumerState<ConnectionDialog> {
  final _hostController = TextEditingController(text: '192.168.');
  final _portController = TextEditingController(text: '8642');
  final _tokenController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('连接到 Hermes Gateway'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(labelText: '主机 / Tailscale IP'),
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
          const Text(
            '提示: 使用 Tailscale 获取你 PC 的 Tailscale IP，或在同一 WiFi 下使用局域网 IP',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final config = GatewayConfig(
              host: _hostController.text.trim(),
              port: int.tryParse(_portController.text) ?? 8642,
              token: _tokenController.text.isNotEmpty ? _tokenController.text : null,
            );
            ref.read(gatewayConfigProvider.notifier).configure(config);
            ref.read(gatewayServiceProvider)?.connect();
            Navigator.pop(context);
          },
          child: const Text('连接'),
        ),
      ],
    );
  }
}
