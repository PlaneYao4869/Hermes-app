import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/message.dart';

class ToolCallCard extends StatelessWidget {
  final ToolCall toolCall;
  const ToolCallCard({super.key, required this.toolCall});

  @override
  Widget build(BuildContext context) {
    final isRunning = toolCall.status == 'running';
    final isComplete = toolCall.status == 'complete';
    final isError = toolCall.status == 'error';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRunning
              ? Colors.blue.withOpacity(0.4)
              : isError
                  ? Colors.red.withOpacity(0.4)
                  : Colors.green.withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isRunning ? Icons.sync : isComplete ? Icons.check_circle : Icons.error,
                size: 18,
                color: isRunning ? Colors.blue : isComplete ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  toolCall.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 14),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: toolCall.arguments.toString()));
                },

                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          if (toolCall.arguments.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatArgs(toolCall.arguments),
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Colors.white70,
                ),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (toolCall.result != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                toolCall.result!.length > 500
                    ? '${toolCall.result!.substring(0, 500)}...'
                    : toolCall.result!,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Colors.white60,
                ),
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatArgs(Map<String, dynamic> args) {
    if (args.isEmpty) return '(无参数)';
    final parts = <String>[];
    args.forEach((k, v) {
      final val = v.toString();
      parts.add('$k: ${val.length > 100 ? '${val.substring(0, 100)}...' : val}');
    });
    return parts.join('\n');
  }
}
