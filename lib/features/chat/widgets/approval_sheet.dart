import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/approval.dart';
import '../../../core/network/gateway_service.dart';
import '../../../core/theme/app_theme.dart';

class ApprovalSheet extends ConsumerWidget {
  final ApprovalRequest approval;
  const ApprovalSheet({super.key, required this.approval});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E26),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: AppTheme.warning),
              const SizedBox(width: 12),
              const Text('审批请求', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  approval.toolName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
                const SizedBox(height: 8),
                if (approval.description != null)
                  Text(approval.description!, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Text(
                  _formatArguments(approval.arguments),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white60),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref.read(gatewayServiceProvider)?.approveAction(approval.runId, approval.id, false);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('拒绝'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: BorderSide(color: AppTheme.error.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () {
                    ref.read(gatewayServiceProvider)?.approveAction(approval.runId, approval.id, true);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('批准'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _formatArguments(Map<String, dynamic> args) {
    if (args.isEmpty) return '(无参数)';
    return args.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }
}
