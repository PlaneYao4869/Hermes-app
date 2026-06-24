import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/models/message.dart';
import '../../../core/theme/app_theme.dart';
import 'tool_call_card.dart';

class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  const MessageBubble({super.key, required this.message});

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _isExpanded = false;

  // Heuristic: collapse if content > 300 chars or > 8 lines
  bool get _needsCollapse {
    final content = widget.message.content;
    if (content.length > 300) return true;
    final lineCount = '\n'.allMatches(content).length + 1;
    return lineCount > 8;
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.message.role) {
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

  // === User bubble (right-aligned, blue) ===
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
          widget.message.content,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
    );
  }

  // === Agent bubble (left-aligned, grey) with LayoutBuilder ===
  Widget _buildAgentBubble(BuildContext context) {
    final content = widget.message.content;
    final showCollapsed = _needsCollapse && !_isExpanded;

    return Align(
      alignment: Alignment.centerLeft,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth * 0.85;

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bubble body
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.agentBubble,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4), topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: showCollapsed
                        ? SizedBox(
                            width: maxWidth - 28, // subtract padding
                            height: 110,
                            child: SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: _buildMarkdown(content),
                            ),
                          )
                        : SizedBox(
                            width: maxWidth - 28,
                            child: _buildMarkdown(content),
                          ),
                  ),
                ),
                // Expand/collapse button
                if (_needsCollapse)
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, left: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isExpanded ? '收起' : '展开',
                            style: TextStyle(
                              color: AppTheme.primaryDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                            size: 16,
                            color: AppTheme.primaryDark,
                          ),
                        ],
                      ),
                    ),
                  ),
                // Copy button
                _buildCopyButton(content),
              ],
            ),
          );
        },
      ),
    );
  }

  // === Tool bubble ===
  Widget _buildToolBubble(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade900,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueGrey.shade700, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.build, size: 14, color: Colors.blueGrey.shade300),
                const SizedBox(width: 6),
                Text(
                  widget.message.toolCalls?.first.name ?? '工具',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade300, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (widget.message.toolCalls?.first.arguments.isNotEmpty ?? false)
              Text(
                widget.message.toolCalls!.first.arguments.toString(),
                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade200, fontFamily: 'monospace'),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            if (widget.message.toolCalls?.first.result != null) ...[
              const Divider(height: 8, color: Colors.blueGrey),
              Text(
                widget.message.toolCalls!.first.result!,
                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade100),
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // === System bubble ===
  Widget _buildSystemBubble(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          widget.message.content,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // === Markdown renderer ===
  Widget _buildMarkdown(String data) {
    return MarkdownBody(
      data: data,
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
    );
  }

  // === Copy button ===
  Widget _buildCopyButton(String content) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: content));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 4, left: 14),
        child: Icon(Icons.copy, size: 14, color: Colors.white.withOpacity(0.3)),
      ),
    );
  }
}
