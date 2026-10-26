import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// File explorer with per-file metrics and AI assistants (explain / refactor / docstrings / tests).
class FilesTab extends StatefulWidget {
  final int pid;
  const FilesTab({super.key, required this.pid});

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  late final Future<dynamic> _future = Api.get('/projects/${widget.pid}/files');
  String _query = '';
  String _sort = 'issues';
  String? _selected;

  int _issues(dynamic f) => (f['issues']['high'] as int) * 100 + (f['issues']['medium'] as int) * 10 + (f['issues']['low'] as int);

  @override
  Widget build(BuildContext context) {
    return Loader(
      future: _future,
      builder: (data) {
        final files = (data as List).where((f) => '${f['file']}'.toLowerCase().contains(_query.toLowerCase())).toList();
        files.sort((a, b) => switch (_sort) {
              'lines' => (b['lines'] as int).compareTo(a['lines']),
              'complexity' => ((b['max_complexity'] ?? 0) as num).compareTo((a['max_complexity'] ?? 0) as num),
              'name' => '${a['file']}'.compareTo('${b['file']}'),
              _ => _issues(b).compareTo(_issues(a)),
            });
        final wide = MediaQuery.sizeOf(context).width >= 1300;
        final list = Column(children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Filter files…', isDense: true),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _sort,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'issues', child: Text('Most issues')),
                  DropdownMenuItem(value: 'complexity', child: Text('Complexity')),
                  DropdownMenuItem(value: 'lines', child: Text('Size')),
                  DropdownMenuItem(value: 'name', child: Text('Name')),
                ],
                onChanged: (v) => setState(() => _sort = v!),
              ),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: files.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _tile(files[i], wide),
            ),
          ),
        ]);
        if (!wide) return list;
        return Row(children: [
          SizedBox(width: 520, child: list),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selected == null
                ? const EmptyState(icon: Icons.description_outlined, title: 'Select a file', subtitle: 'View its code, explain it, refactor it or add documentation.')
                : FileDetail(key: ValueKey(_selected), pid: widget.pid, file: _selected!),
          ),
        ]);
      },
    );
  }

  Widget _tile(dynamic f, bool wide) {
    final iss = f['issues'];
    final selected = _selected == f['file'];
    final cc = f['max_complexity'];
    return Card(
      color: selected ? Brand.primary.withValues(alpha: .1) : null,
      child: ListTile(
        leading: Icon(Icons.insert_drive_file_outlined, color: Theme.of(context).colorScheme.primary),
        title: Text('${f['file']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${f['language']} · ${f['lines']} lines · ${f['functions']} fn${cc != null ? ' · max CC $cc' : ''}'),
        trailing: Wrap(spacing: 4, children: [
          if (iss['high'] > 0) _dot(iss['high'], Brand.high),
          if (iss['medium'] > 0) _dot(iss['medium'], Brand.medium),
          if (iss['low'] > 0) _dot(iss['low'], Brand.low),
        ]),
        onTap: () {
          if (wide) {
            setState(() => _selected = f['file']);
          } else {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => Scaffold(appBar: AppBar(title: Text('${f['file']}')), body: FileDetail(pid: widget.pid, file: f['file'])),
            ));
          }
        },
      ),
    );
  }

  Widget _dot(int n, Color c) => CircleAvatar(
        radius: 12,
        backgroundColor: c.withValues(alpha: .18),
        child: Text('$n', style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w800)),
      );
}

class FileDetail extends StatefulWidget {
  final int pid;
  final String file;
  const FileDetail({super.key, required this.pid, required this.file});

  @override
  State<FileDetail> createState() => _FileDetailState();
}

class _FileDetailState extends State<FileDetail> {
  late final Future<String> _code = Api.file(widget.pid, widget.file);
  String? _task;

  static const _tasks = [
    ('code', Icons.code, 'Code'),
    ('explain', Icons.lightbulb_outline, 'Explain'),
    ('refactor', Icons.auto_fix_high, 'Refactor'),
    ('docstrings', Icons.menu_book_outlined, 'Add docs'),
    ('tests', Icons.science_outlined, 'Tests'),
  ];

  @override
  Widget build(BuildContext context) {
    final task = _task ?? 'code';
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text(widget.file, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),
      SegmentedButton<String>(
        segments: [for (final t in _tasks) ButtonSegment(value: t.$1, icon: Icon(t.$2, size: 18), label: Text(t.$3))],
        selected: {task},
        onSelectionChanged: (s) => setState(() => _task = s.first),
      ),
      const SizedBox(height: 20),
      if (task == 'code')
        Loader<String>(future: _code, builder: (c) => CodeView(code: c, language: languageFor(widget.file), startLine: 1))
      else if (task == 'tests')
        AiPanel(
          key: const ValueKey('tests'),
          endpoint: '/projects/${widget.pid}/tests',
          body: {'file': widget.file},
          label: 'Generate unit tests',
          icon: Icons.science_outlined,
          downloadName: 'test_${widget.file.split('/').last}.md',
          autoRun: true,
        )
      else
        AiPanel(
          key: ValueKey(task),
          endpoint: '/projects/${widget.pid}/file-assist',
          body: {'file': widget.file, 'task': task},
          label: {'explain': 'Explain this file', 'refactor': 'Suggest refactorings', 'docstrings': 'Add documentation'}[task]!,
          downloadName: '${widget.file.split('/').last}.$task.md',
          autoRun: true,
        ),
    ]);
  }
}
