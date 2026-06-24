import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FileViewerScreen extends StatelessWidget {
  final String fileName;
  final String filePath;
  const FileViewerScreen({super.key, required this.fileName, required this.filePath});

  @override
  Widget build(BuildContext context) {
    // In real app, fetch file content from Gateway API
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              // Copy file content
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制文件内容'), duration: Duration(seconds: 1)),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '// 文件内容将从 Gateway API 加载\n// 路径: <file_path>\n\n// TODO: 实现文件内容获取',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
