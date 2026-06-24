import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/models/message.dart';
import '../../../core/theme/app_theme.dart';
import 'tool_call_card.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    switch (message.role) {
      case MessageRole.user:
        return _buildUserBubble(context);
      case MessageRole.assistant:
        return _buildAgentBubble(context);
      case MessageRole.tool:
        return _buildToolBubble(context);
      case MessageRole.system:
        return _buildSystemBubble(context);
    }
  }

  Widget _buildUserBubble(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: AppTheme.userBubble,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16), topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16), bottomRight: Radius.circular(4),
          ),
        ),
        child: SelectableText(
          message.content,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildAgentBubble(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.agentBubble,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4), topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: message.content,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(color: Colors.white, fontSize: 15),
                      code: TextStyle(
                        color: Colors.greenAccent.shade100,
                        backgroundColor: Colors.black26,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  if (message.isStreaming)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryDark),
                      ),
                    ),
                ],
              ),
            ),
            // Action buttons
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: message.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                      );
                    },

                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolBubble(BuildContext context) {
    final toolCall = message.toolCalls?.firstOrNull;
    if (toolCall == null) return const SizedBox.shrink();
    return ToolCallCard(toolCall: toolCall);
  }

  Widget _buildSystemBubble(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: message.content.contains('错误') ? AppTheme.error.withOpacity(0.15) : Colors.grey.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            fontSize: 13,
            color: message.content.contains('错误') ? AppTheme.error : Colors.grey,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
