import 'package:flutter/material.dart';
import 'file_viewer.dart';

class FileTreeView extends StatelessWidget {
  final String repoName;
  final String repoPath;
  const FileTreeView({super.key, required this.repoName, required this.repoPath});

  @override
  Widget build(BuildContext context) {
    // Demo file tree - in real app, fetched from Gateway API
    final items = <_FileItem>[
      _FileItem('lib', true, []),
      _FileItem('src', true, []),
      _FileItem('README.md', false, []),
      _FileItem('pubspec.yaml', false, []),
      _FileItem('.gitignore', false, []),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(repoName),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            leading: Icon(
              item.isDir ? Icons.folder : _fileIcon(item.name),
              color: item.isDir ? Colors.amber : Colors.grey,
              size: 20,
            ),
            title: Text(item.name, style: const TextStyle(fontSize: 14)),
            dense: true,
            onTap: () {
              if (item.isDir) {
                // Navigate deeper
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FileViewerScreen(fileName: item.name, filePath: '$repoPath/${item.name}'),
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }

  IconData _fileIcon(String name) {
    if (name.endsWith('.dart')) return Icons.code;
    if (name.endsWith('.md')) return Icons.description;
    if (name.endsWith('.yaml') || name.endsWith('.yml')) return Icons.settings;
    if (name.endsWith('.json')) return Icons.data_object;
    if (name.endsWith('.py')) return Icons.code;
    return Icons.insert_drive_file;
  }
}

class _FileItem {
  final String name;
  final bool isDir;
  final List<_FileItem> children;
  const _FileItem(this.name, this.isDir, this.children);
}
