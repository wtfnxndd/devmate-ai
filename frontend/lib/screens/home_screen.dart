import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../api.dart';
import 'project_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _projects = [];
  List<dynamic> _providers = [];
  String? _error;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_projects.any((p) => !['ready'].contains(p['status']) && !p['status'].toString().startsWith('error'))) _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([Api.get('/projects'), Api.get('/health')]);
      setState(() {
        _projects = results[0];
        _providers = results[1]['llm_providers'];
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Cannot reach backend at ${Api.baseUrl}. Is it running?\n$e');
    }
  }

  Future<void> _run(Future<dynamic> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadZip() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip'], withData: true);
    final f = res?.files.single;
    if (f?.bytes == null) return;
    await _run(() => Api.uploadZip(f!.name, f.bytes!));
  }

  Future<void> _askText(String title, String hint, String endpoint, String key) async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: hint)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Import')),
        ],
      ),
    );
    if (value != null && value.isNotEmpty) await _run(() => Api.post(endpoint, {key: value}));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('DevMate AI', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              avatar: Icon(_providers.isEmpty ? Icons.memory : Icons.auto_awesome, size: 18),
              label: Text(_providers.isEmpty ? 'Static mode (no LLM key)' : 'AI: ${_providers.join(" → ")}'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Intelligent Software Review, Debugging & Documentation',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            FilledButton.icon(onPressed: _busy ? null : _uploadZip, icon: const Icon(Icons.folder_zip), label: const Text('Upload ZIP')),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _askText('Import from GitHub', 'https://github.com/owner/repo', '/projects/github', 'url'),
              icon: const Icon(Icons.code),
              label: const Text('GitHub link'),
            ),
            if (!kIsWeb)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _askText('Local directory', '/path/to/project', '/projects/local', 'path'),
                icon: const Icon(Icons.folder_open),
                label: const Text('Local folder'),
              ),
            if (_busy) const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ]),
          const SizedBox(height: 24),
          if (_error != null) Card(color: cs.errorContainer, child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!))),
          if (_projects.isEmpty && _error == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No projects yet — import one to start.'))),
          ..._projects.map((p) => _ProjectTile(project: p, onChanged: _load)),
        ],
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  final dynamic project;
  final VoidCallback onChanged;
  const _ProjectTile({required this.project, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final status = project['status'] as String;
    final ready = status == 'ready';
    final s = project['summary'];
    final score = project['health_score'];
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: scoreColor(score).withValues(alpha: .15),
          child: Text(project['grade'] ?? '…', style: TextStyle(color: scoreColor(score), fontWeight: FontWeight.bold, fontSize: 20)),
        ),
        title: Text(project['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          if (s != null) '${s['files']} files · ${s['lines']} lines · ${(s['languages'] as Map).keys.join(", ")}',
          ready ? 'Health $score/100' : 'Status: $status',
        ].join('\n')),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!ready && !status.startsWith('error')) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await Api.delete('/projects/${project['id']}');
              onChanged();
            },
          ),
        ]),
        onTap: ready
            ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(id: project['id'], name: project['name'])))
            : null,
      ),
    );
  }
}

Color scoreColor(dynamic score) {
  if (score == null) return Colors.grey;
  if (score >= 85) return Colors.green;
  if (score >= 70) return Colors.lightGreen;
  if (score >= 55) return Colors.orange;
  return Colors.red;
}
