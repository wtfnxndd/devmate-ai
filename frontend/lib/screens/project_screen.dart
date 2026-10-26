import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import 'home_screen.dart' show scoreColor;

class ProjectScreen extends StatefulWidget {
  final int id;
  final String name;
  const ProjectScreen({super.key, required this.id, required this.name});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  int _tab = 0;

  static const _tabs = [
    (Icons.dashboard_outlined, 'Overview'),
    (Icons.bug_report_outlined, 'Review'),
    (Icons.account_tree_outlined, 'Architecture'),
    (Icons.description_outlined, 'Docs'),
    (Icons.science_outlined, 'Tests'),
    (Icons.healing_outlined, 'Debug'),
    (Icons.chat_outlined, 'Chat'),
    (Icons.assessment_outlined, 'Report'),
  ];

  @override
  Widget build(BuildContext context) {
    final pid = widget.id;
    final pages = [
      OverviewTab(pid: pid),
      ReviewTab(pid: pid),
      ArchitectureTab(pid: pid),
      DocsTab(pid: pid),
      TestsTab(pid: pid),
      DebugTab(pid: pid),
      ChatTab(pid: pid),
      AiMarkdownPanel(endpoint: '/projects/$pid/report', label: 'Generate health report'),
    ];
    final wide = MediaQuery.sizeOf(context).width > 800;
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [for (final t in _tabs) NavigationDestination(icon: Icon(t.$1), label: t.$2)],
            ),
      body: Row(children: [
        if (wide)
          NavigationRail(
            selectedIndex: _tab,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [for (final t in _tabs) NavigationRailDestination(icon: Icon(t.$1), label: Text(t.$2))],
          ),
        Expanded(child: IndexedStack(index: _tab, children: pages)),
      ]),
    );
  }
}

// ------------------------------------------------------------------ shared widgets
class Md extends StatelessWidget {
  final String data;
  const Md(this.data, {super.key});

  @override
  Widget build(BuildContext context) => MarkdownBody(
        data: data,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          code: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      );
}

class AiBadge extends StatelessWidget {
  final bool ai;
  const AiBadge(this.ai, {super.key});
  @override
  Widget build(BuildContext context) => Chip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(ai ? Icons.auto_awesome : Icons.rule, size: 16),
        label: Text(ai ? 'AI-enhanced' : 'Static analysis'),
      );
}

/// Button that calls an engine endpoint and renders the returned Markdown.
class AiMarkdownPanel extends StatefulWidget {
  final String endpoint;
  final String label;
  final Map<String, dynamic>? body;
  const AiMarkdownPanel({super.key, required this.endpoint, required this.label, this.body});

  @override
  State<AiMarkdownPanel> createState() => _AiMarkdownPanelState();
}

class _AiMarkdownPanelState extends State<AiMarkdownPanel> {
  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _error;

  Future<void> _go({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.post(widget.endpoint, widget.body, refresh ? {'refresh': 'true'} : null);
      setState(() => _result = Map<String, dynamic>.from(r));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(24), children: [
      Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.icon(
          onPressed: _loading ? null : () => _go(refresh: _result != null),
          icon: const Icon(Icons.auto_awesome),
          label: Text(_result == null ? widget.label : 'Regenerate'),
        ),
        if (_result != null) ...[
          AiBadge(_result!['ai'] == true),
          IconButton(
            tooltip: 'Copy Markdown',
            icon: const Icon(Icons.copy),
            onPressed: () => Clipboard.setData(ClipboardData(text: _result!['markdown'])),
          ),
        ],
        if (_loading) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      const SizedBox(height: 16),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (_result != null) Md(_result!['markdown']),
    ]);
  }
}

class _Loader extends StatelessWidget {
  final Future<dynamic> future;
  final Widget Function(dynamic data) builder;
  const _Loader({required this.future, required this.builder});

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: future,
        builder: (ctx, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return builder(snap.data);
        },
      );
}

// ------------------------------------------------------------------ Overview
class OverviewTab extends StatelessWidget {
  final int pid;
  const OverviewTab({super.key, required this.pid});

  @override
  Widget build(BuildContext context) {
    return _Loader(
      future: Future.wait([Api.get('/projects/$pid/structure'), Api.get('/projects/$pid/analysis')]),
      builder: (d) {
        final s = d[0]['summary'], a = d[1];
        final score = a['health_score'];
        Widget stat(String label, String value, [Color? c]) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: c, fontWeight: FontWeight.bold)),
                  Text(label),
                ]),
              ),
            );
        return ListView(padding: const EdgeInsets.all(24), children: [
          GridView.extent(
            maxCrossAxisExtent: 220,
            childAspectRatio: 1.8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              stat('Health score (${a['grade']})', '$score/100', scoreColor(score)),
              stat('Files', '${s['files']}'),
              stat('Lines of code', '${s['lines']}'),
              stat('Classes / Functions', '${s['classes']} / ${s['functions']}'),
              stat('High severity', '${a['counts']['high']}', Colors.red),
              stat('Medium severity', '${a['counts']['medium']}', Colors.orange),
              stat('Security issues', '${a['by_category']['security']}'),
              stat('Avg complexity', '${a['avg_complexity']}'),
            ],
          ),
          const SizedBox(height: 16),
          Text('Languages: ${(s['languages'] as Map).entries.map((e) => '${e.key} (${e.value} lines)').join(', ')}'),
          Text('Tools: ${(a['tools'] as List).join(', ')}'),
          const SizedBox(height: 24),
          Text('Findings', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final f in a['findings'])
            Card(
              child: ListTile(
                dense: true,
                leading: Icon(
                  f['category'] == 'security' ? Icons.shield_outlined : f['category'] == 'bug' ? Icons.bug_report : Icons.cleaning_services_outlined,
                  color: {'high': Colors.red, 'medium': Colors.orange}[f['severity']] ?? Colors.blueGrey,
                ),
                title: Text('${f['rule']} — ${f['message']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${f['file']}:${f['line']} · ${f['tool']} · ${f['severity']}'),
                onTap: () => showCode(context, pid, f['file'], f['line']),
              ),
            ),
        ]);
      },
    );
  }
}

Future<void> showCode(BuildContext context, int pid, String file, int line) async {
  final code = await Api.file(pid, file);
  if (!context.mounted) return;
  final lines = code.split('\n');
  showDialog(
    context: context,
    builder: (_) => Dialog(
      child: SizedBox(
        width: 900,
        height: 600,
        child: Column(children: [
          ListTile(title: Text(file), trailing: CloseButton(onPressed: () => Navigator.pop(context))),
          Expanded(
            child: ListView.builder(
              itemCount: lines.length,
              controller: ScrollController(initialScrollOffset: (line - 8).clamp(0, lines.length) * 18.0),
              itemBuilder: (_, i) => Container(
                color: i + 1 == line ? Colors.amber.withValues(alpha: .25) : null,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                height: 18,
                child: Text('${(i + 1).toString().padLeft(5)}  ${lines[i]}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              ),
            ),
          ),
        ]),
      ),
    ),
  );
}

// ------------------------------------------------------------------ Review
class ReviewTab extends StatelessWidget {
  final int pid;
  const ReviewTab({super.key, required this.pid});
  @override
  Widget build(BuildContext context) =>
      AiMarkdownPanel(endpoint: '/projects/$pid/review', label: 'Run AI code review');
}

// ------------------------------------------------------------------ Architecture
class ArchitectureTab extends StatelessWidget {
  final int pid;
  const ArchitectureTab({super.key, required this.pid});

  @override
  Widget build(BuildContext context) {
    return _Loader(
      future: Api.get('/projects/$pid/architecture'),
      builder: (d) {
        final mermaid = d['mermaid'] as String;
        final state = base64Url.encode(utf8.encode(jsonEncode({'code': mermaid, 'mermaid': {'theme': 'default'}})));
        return ListView(padding: const EdgeInsets.all(24), children: [
          Text('Dependency graph (${(d['dependencies'] as List).length} internal edges)', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 12, children: [
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open diagram in Mermaid Live'),
              onPressed: () => launchUrl(Uri.parse('https://mermaid.live/view#base64:$state')),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy Mermaid'),
              onPressed: () => Clipboard.setData(ClipboardData(text: mermaid)),
            ),
          ]),
          const SizedBox(height: 12),
          Md('```mermaid\n$mermaid\n```'),
          const SizedBox(height: 24),
          Text('Folder structure', style: Theme.of(context).textTheme.titleLarge),
          Md('```\n${d['tree']}\n```'),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ Docs
class DocsTab extends StatelessWidget {
  final int pid;
  const DocsTab({super.key, required this.pid});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Column(children: [
          const TabBar(tabs: [Tab(text: 'README.md'), Tab(text: 'API reference')]),
          Expanded(
            child: TabBarView(children: [
              AiMarkdownPanel(endpoint: '/projects/$pid/readme', label: 'Generate README'),
              AiMarkdownPanel(endpoint: '/projects/$pid/api-docs', label: 'Generate API docs'),
            ]),
          ),
        ]),
      );
}

// ------------------------------------------------------------------ Tests
class TestsTab extends StatefulWidget {
  final int pid;
  const TestsTab({super.key, required this.pid});
  @override
  State<TestsTab> createState() => _TestsTabState();
}

class _TestsTabState extends State<TestsTab> {
  String? _file;

  @override
  Widget build(BuildContext context) {
    return _Loader(
      future: Api.get('/projects/${widget.pid}/structure'),
      builder: (d) {
        final files = (d['files'] as Map).entries.where((e) => (e.value['functions'] as List).isNotEmpty).map((e) => e.key as String).toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: DropdownButtonFormField<String>(
              initialValue: _file,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Choose a file to generate unit tests for', border: OutlineInputBorder()),
              items: [for (final f in files) DropdownMenuItem(value: f, child: Text(f))],
              onChanged: (v) => setState(() => _file = v),
            ),
          ),
          if (_file != null)
            Expanded(
              child: AiMarkdownPanel(
                key: ValueKey(_file),
                endpoint: '/projects/${widget.pid}/tests',
                label: 'Generate tests',
                body: {'file': _file},
              ),
            ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ Debug
class DebugTab extends StatefulWidget {
  final int pid;
  const DebugTab({super.key, required this.pid});
  @override
  State<DebugTab> createState() => _DebugTabState();
}

class _DebugTabState extends State<DebugTab> {
  final _ctrl = TextEditingController();
  Map<String, dynamic>? _result;
  bool _loading = false;

  Future<void> _debug() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      _result = Map<String, dynamic>.from(await Api.post('/projects/${widget.pid}/debug', {'error': _ctrl.text}));
    } catch (e) {
      _result = {'markdown': 'Error: $e', 'ai': false};
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
        TextField(
          controller: _ctrl,
          maxLines: 10,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Paste an error message, stack trace or log',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          FilledButton.icon(onPressed: _loading ? null : _debug, icon: const Icon(Icons.healing), label: const Text('Explain & fix')),
          const SizedBox(width: 12),
          if (_loading) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          if (_result != null) AiBadge(_result!['ai'] == true),
        ]),
        const SizedBox(height: 16),
        if (_result != null) Md(_result!['markdown']),
      ]);
}

// ------------------------------------------------------------------ Chat
class ChatTab extends StatefulWidget {
  final int pid;
  const ChatTab({super.key, required this.pid});
  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _msgs = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    Api.get('/projects/${widget.pid}/chat').then((h) => setState(() => _msgs = List<Map<String, dynamic>>.from(h)));
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();
    setState(() {
      _msgs.add({'role': 'user', 'content': text});
      _sending = true;
    });
    try {
      final r = await Api.post('/projects/${widget.pid}/chat', {'message': text});
      _msgs.add({'role': 'assistant', 'content': r['markdown']});
    } catch (e) {
      _msgs.add({'role': 'assistant', 'content': 'Error: $e'});
    }
    setState(() => _sending = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scroll.jumpTo(_scroll.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Expanded(
        child: _msgs.isEmpty
            ? const Center(child: Text('Ask anything about this codebase, e.g. "Where is checkout implemented?"'))
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(24),
                itemCount: _msgs.length,
                itemBuilder: (_, i) {
                  final m = _msgs[i];
                  final user = m['role'] == 'user';
                  return Align(
                    alignment: user ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 760),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: user ? cs.primaryContainer : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: user ? Text(m['content']) : Md(m['content']),
                    ),
                  );
                },
              ),
      ),
      if (_sending) const LinearProgressIndicator(),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(hintText: 'Ask about the code…', border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
        ]),
      ),
    ]);
  }
}
