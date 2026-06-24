import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/file_tree.dart';
import 'widgets/file_viewer.dart';

class GitReposScreen extends ConsumerStatefulWidget {
  const GitReposScreen({super.key});

  @override
  ConsumerState<GitReposScreen> createState() => _GitReposScreenState();
}

class _GitReposScreenState extends ConsumerState<GitReposScreen> {
  // Demo repos - in real app, fetched from Gateway
  final _repos = [
    _RepoInfo('hermes-agent', 'C:\\Users\\yao11\\AppData\\Local\\hermes\\hermes-agent', 'main', 42),
    _RepoInfo('hermes-mobile', 'C:\\Users\\yao11\\hermes-mobile', 'main', 0),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('代码浏览'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddRepoDialog(),
            tooltip: '添加仓库',
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _repos.length,
        itemBuilder: (context, index) {
          final repo = _repos[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.success.withOpacity(0.2),
                child: const Icon(Icons.folder_special, color: AppTheme.success, size: 20),
              ),
              title: Text(repo.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${repo.branch} · ${repo.commits} commits', style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => FileTreeView(repoName: repo.name, repoPath: repo.path)),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddRepoDialog() {
    final pathController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加 Git 仓库'),
        content: TextField(
          controller: pathController,
          decoration: const InputDecoration(labelText: '仓库路径', hintText: 'C:\\path\\to\\repo'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              // TODO: Add repo
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}

class _RepoInfo {
  final String name;
  final String path;
  final String branch;
  final int commits;
  const _RepoInfo(this.name, this.path, this.branch, this.commits);
}
