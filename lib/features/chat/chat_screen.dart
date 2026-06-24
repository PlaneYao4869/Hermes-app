import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/gateway_service.dart';
import '../../core/network/connection_state.dart';
import '../../core/models/message.dart';
import '../../core/models/approval.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/message_bubble.dart';
import 'widgets/approval_sheet.dart';
import 'chat_controller.dart';
import '../settings/connection_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String? sessionId;
  const ChatScreen({super.key, this.sessionId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.sessionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(chatControllerProvider.notifier).loadSession(widget.sessionId!);
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    ref.read(chatControllerProvider.notifier).sendMessage(text);
    _inputController.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider);
    final connState = ref.watch(connectionStateProvider);
    final pendingApproval = ref.watch(pendingApprovalProvider);
    final isSending = ref.watch(isSendingProvider);

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
            child: isSending && messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: messages.length,
                        itemBuilder: (context, index) => MessageBubble(
                          message: messages[messages.length - 1 - index],
                        ),
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        bottom: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 100),
                child: TextField(
                  controller: _inputController,
                  focusNode: _focusNode,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '输入消息...',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              onPressed: _sendMessage,
              icon: const Icon(Icons.send_rounded),
              iconSize: 20,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
