import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';

class OrchestratorScreen extends ConsumerStatefulWidget {
  const OrchestratorScreen({super.key});

  @override
  ConsumerState<OrchestratorScreen> createState() => _OrchestratorScreenState();
}

class _OrchestratorScreenState extends ConsumerState<OrchestratorScreen> {
  // Demo agent tree
  final _agents = <_AgentNode>[
    _AgentNode('主 Agent', 'mimo-v2.5-pro', _AgentStatus.running, [
      _AgentNode('研究任务', 'deepseek-v4-flash', _AgentStatus.completed, []),
      _AgentNode('代码重构', 'mimo-v2.5-pro', _AgentStatus.running, [
        _AgentNode('子任务: 认证模块', 'deepseek-v4-flash', _AgentStatus.running, []),
        _AgentNode('子任务: 数据库迁移', 'deepseek-v4-flash', _AgentStatus.queued, []),
      ]),
      _AgentNode('测试生成', 'deepseek-v4-flash', _AgentStatus.queued, []),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent 编排'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _showNewAgentDialog(),
            tooltip: '创建新 Agent',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Stats cards
          Row(
            children: [
              _StatCard(title: '运行中', count: 3, color: AppTheme.success, icon: Icons.play_circle),
              const SizedBox(width: 8),
              _StatCard(title: '队列中', count: 2, color: AppTheme.warning, icon: Icons.queue),
              const SizedBox(width: 8),
              _StatCard(title: '已完成', count: 1, color: Colors.grey, icon: Icons.check_circle),
            ],
          ),
          const SizedBox(height: 16),
          // Agent tree
          const Text('Agent 树', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 8),
          ..._agents.map((node) => _AgentTreeNode(node: node, depth: 0)),
        ],
      ),
    );
  }

  void _showNewAgentDialog() {
    final promptController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建新 Agent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: promptController,
              decoration: const InputDecoration(labelText: '任务描述'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: '模型'),
              items: const [
                DropdownMenuItem(value: 'mimo-v2.5-pro', child: Text('mimo-v2.5-pro')),
                DropdownMenuItem(value: 'deepseek-v4-flash', child: Text('deepseek-v4-flash')),
              ],
              onChanged: (_) {},
              value: 'deepseek-v4-flash',
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              // TODO: Create agent run via Gateway
              Navigator.pop(ctx);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}

enum _AgentStatus { queued, running, completed, failed }

class _AgentNode {
  final String name;
  final String model;
  final _AgentStatus status;
  final List<_AgentNode> children;
  const _AgentNode(this.name, this.model, this.status, this.children);
}

class _StatCard extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  final IconData icon;
  const _StatCard({required this.title, required this.count, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text('$count', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentTreeNode extends StatelessWidget {
  final _AgentNode node;
  final int depth;
  const _AgentTreeNode({required this.node, required this.depth});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    switch (node.status) {
      case _AgentStatus.running:
        statusColor = AppTheme.success;
        statusIcon = Icons.play_circle;
        break;
      case _AgentStatus.completed:
        statusColor = Colors.grey;
        statusIcon = Icons.check_circle;
        break;
      case _AgentStatus.queued:
        statusColor = AppTheme.warning;
        statusIcon = Icons.schedule;
        break;
      case _AgentStatus.failed:
        statusColor = AppTheme.error;
        statusIcon = Icons.error;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: EdgeInsets.only(left: depth * 24.0, top: 4, bottom: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(node.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text(node.model, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              if (node.status == _AgentStatus.running)
                SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: statusColor),
                ),
            ],
          ),
        ),
        ...node.children.map((child) => _AgentTreeNode(node: child, depth: depth + 1)),
      ],
    );
  }
}
