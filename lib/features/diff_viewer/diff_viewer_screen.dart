import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class DiffViewerScreen extends StatelessWidget {
  final String fileName;
  final String oldContent;
  final String newContent;

  const DiffViewerScreen({
    super.key,
    required this.fileName,
    required this.oldContent,
    required this.newContent,
  });

  @override
  Widget build(BuildContext context) {
    final diffLines = _computeDiff(oldContent, newContent);

    return Scaffold(
      appBar: AppBar(
        title: Text('Diff: $fileName'),
        actions: [
          SegmentedButton<_DiffViewMode>(
            segments: const [
              ButtonSegment(value: _DiffViewMode.unified, label: Text('统一')),
              ButtonSegment(value: _DiffViewMode.split, label: Text('并排')),
            ],
            selected: const {_DiffViewMode.unified},
            onSelectionChanged: (_) {},
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: diffLines.length,
        itemBuilder: (context, index) {
          final line = diffLines[index];
          return _DiffLineWidget(line: line);
        },
      ),
    );
  }

  List<_DiffLine> _computeDiff(String old, String newContent) {
    final oldLines = old.split('\n');
    final newLines = newContent.split('\n');
    final result = <_DiffLine>[];
    final maxLen = oldLines.length > newLines.length ? oldLines.length : newLines.length;

    for (var i = 0; i < maxLen; i++) {
      final oldLine = i < oldLines.length ? oldLines[i] : null;
      final newLine = i < newLines.length ? newLines[i] : null;

      if (oldLine == null) {
        result.add(_DiffLine(i + 1, null, i + 1, newLine!, _DiffLineType.added));
      } else if (newLine == null) {
        result.add(_DiffLine(i + 1, oldLine, i + 1, null, _DiffLineType.removed));
      } else if (oldLine != newLine) {
        result.add(_DiffLine(i + 1, oldLine, null, null, _DiffLineType.removed));
        result.add(_DiffLine(null, null, i + 1, newLine, _DiffLineType.added));
      } else {
        result.add(_DiffLine(i + 1, oldLine, i + 1, newLine, _DiffLineType.context));
      }
    }
    return result;
  }
}

enum _DiffViewMode { unified, split }
enum _DiffLineType { context, added, removed }

class _DiffLine {
  final int? oldLineNum;
  final String? oldContent;
  final int? newLineNum;
  final String? newContent;
  final _DiffLineType type;
  const _DiffLine(this.oldLineNum, this.oldContent, this.newLineNum, this.newContent, this.type);
}

class _DiffLineWidget extends StatelessWidget {
  final _DiffLine line;
  const _DiffLineWidget({required this.line});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String prefix;
    String content;

    switch (line.type) {
      case _DiffLineType.added:
        bgColor = AppTheme.diffAddedBg;
        textColor = AppTheme.diffAdded;
        prefix = '+';
        content = line.newContent ?? '';
        break;
      case _DiffLineType.removed:
        bgColor = AppTheme.diffRemovedBg;
        textColor = AppTheme.diffRemoved;
        prefix = '-';
        content = line.oldContent ?? '';
        break;
      case _DiffLineType.context:
        bgColor = Colors.transparent;
        textColor = Colors.white70;
        prefix = ' ';
        content = line.oldContent ?? '';
        break;
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '${line.oldLineNum ?? ''}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFamily: 'monospace'),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 36,
            child: Text(
              '${line.newLineNum ?? ''}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFamily: 'monospace'),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          Text(prefix, style: TextStyle(fontSize: 13, color: textColor, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(content, style: TextStyle(fontSize: 13, color: textColor, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}
