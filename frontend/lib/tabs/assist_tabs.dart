import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Common padded, width-limited page for AI tools.
class _Page extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final List<Widget> children;
  const _Page({required this.title, required this.subtitle, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    return ListView(padding: EdgeInsets.all(wide ? 28 : 16), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
              ),
            ]),
            const SizedBox(height: 24),
            ...children,
          ]),
        ),
      ),
    ]);
  }
}

class ReviewTab extends StatelessWidget {
  final int pid;
  const ReviewTab({super.key, required this.pid});
  @override
  Widget build(BuildContext context) => _Page(
        title: 'AI Code Review',
        subtitle: 'Explains the top issues, flags false positives, maps them to OWASP and gives corrected code.',
        icon: Icons.rate_review_outlined,
        children: [Card(child: Padding(padding: const EdgeInsets.all(24), child: AiPanel(
          endpoint: '/projects/$pid/review',
          label: 'Run AI code review',
          description: 'Static tools have already found the issues. The AI reviews the most important ones in a single request.',
          downloadName: 'code-review.md',
        )))],
      );
}

class DocsTab extends StatelessWidget {
  final int pid;
  const DocsTab({super.key, required this.pid});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: _Page(
          title: 'Documentation Generator',
          subtitle: 'README with architecture diagram, plus an API reference for detected HTTP endpoints.',
          icon: Icons.description_outlined,
          children: [
            const TabBar(tabAlignment: TabAlignment.start, isScrollable: true, tabs: [
              Tab(icon: Icon(Icons.article_outlined), text: 'README.md'),
              Tab(icon: Icon(Icons.api), text: 'API reference'),
            ]),
            const SizedBox(height: 16),
            Builder(builder: (context) {
              final ctrl = DefaultTabController.of(context);
              return AnimatedBuilder(
                animation: ctrl,
                builder: (_, __) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: IndexedStack(index: ctrl.index, children: [
                      AiPanel(endpoint: '/projects/$pid/readme', label: 'Generate README', downloadName: 'README.md',
                          description: 'Features, tech stack, setup, usage, structure and a Mermaid architecture diagram.'),
                      AiPanel(endpoint: '/projects/$pid/api-docs', label: 'Generate API docs', downloadName: 'API.md',
                          description: 'Detects FastAPI, Flask, Express, Spring and Django routes and documents parameters, responses and curl examples.'),
                    ]),
                  ),
                ),
              );
            }),
          ],
        ),
      );
}

class TestsTab extends StatefulWidget {
  final int pid;
  const TestsTab({super.key, required this.pid});
  @override
  State<TestsTab> createState() => _TestsTabState();
}

class _TestsTabState extends State<TestsTab> {
  late final Future<dynamic> _files = Api.get('/projects/${widget.pid}/files');
  String? _file;

  @override
  Widget build(BuildContext context) => _Page(
        title: 'Test Generator',
        subtitle: 'Unit tests with happy paths, edge cases and mocks in the right framework for each language.',
        icon: Icons.science_outlined,
        children: [
          Loader(
            future: _files,
            builder: (files) {
              final candidates = (files as List).where((f) => (f['functions'] as int) > 0).toList();
              return DropdownMenu<String>(
                width: 600,
                leadingIcon: const Icon(Icons.insert_drive_file_outlined),
                label: const Text('Choose a source file'),
                enableFilter: true,
                requestFocusOnTap: true,
                dropdownMenuEntries: [
                  for (final f in candidates)
                    DropdownMenuEntry(value: f['file'] as String, label: f['file'] as String, trailingIcon: Text('${f['functions']} fn')),
                ],
                onSelected: (v) => setState(() => _file = v),
              );
            },
          ),
          const SizedBox(height: 20),
          if (_file != null)
            Card(child: Padding(padding: const EdgeInsets.all(24), child: AiPanel(
              key: ValueKey(_file),
              endpoint: '/projects/${widget.pid}/tests',
              body: {'file': _file},
              label: 'Generate tests for $_file',
              icon: Icons.science_outlined,
              downloadName: 'tests_${_file!.split('/').last}.md',
            ))),
        ],
      );
}

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

  static const _example = 'Traceback (most recent call last):\n  File "app/main.py", line 42, in handler\n    total = items / count\nZeroDivisionError: division by zero';

  Future<void> _debug() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      _result = Map<String, dynamic>.from(await Api.post('/projects/${widget.pid}/debug', {'error': _ctrl.text}));
    } catch (e) {
      _result = {'markdown': 'Error: $e', 'ai': false};
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => _Page(
        title: 'Intelligent Debugger',
        subtitle: 'Paste a stack trace or log. DevMate finds the frames in your code, pulls related context and explains the fix.',
        icon: Icons.healing_outlined,
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 12,
            minLines: 8,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(hintText: _example),
          ),
          const SizedBox(height: 14),
          Row(children: [
            FilledButton.icon(
              onPressed: _loading ? null : _debug,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.healing),
              label: Text(_loading ? 'Analyzing…' : 'Explain & fix'),
            ),
            const SizedBox(width: 12),
            TextButton(onPressed: () => _ctrl.clear(), child: const Text('Clear')),
            const Spacer(),
            if (_result != null) AiBadge(_result!['ai'] == true),
          ]),
          if (_result != null) ...[
            const SizedBox(height: 20),
            if ((_result!['frames'] as List?)?.isNotEmpty ?? false)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in _result!['frames'])
                  Chip(avatar: const Icon(Icons.location_on_outlined, size: 16), label: Text('${f['file']}:${f['line']}')),
              ]),
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(24), child: MarkdownView(_result!['markdown']))),
          ],
        ],
      );
}

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

  static const _suggestions = [
    'Give me an overview of this codebase',
    'Where is the main entry point?',
    'Which parts are most risky to change?',
    'How is data stored?',
  ];

  @override
  void initState() {
    super.initState();
    Api.get('/projects/${widget.pid}/chat').then((h) {
      if (mounted) setState(() => _msgs = List<Map<String, dynamic>>.from(h));
      _toBottom();
    });
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      });

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _ctrl.text).trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();
    setState(() {
      _msgs.add({'role': 'user', 'content': text});
      _sending = true;
    });
    _toBottom();
    try {
      final r = await Api.post('/projects/${widget.pid}/chat', {'message': text});
      final sources = (r['sources'] as List).map((s) => '`${s['file']}:${s['start']}`').join(' · ');
      _msgs.add({'role': 'assistant', 'content': r['markdown'], 'sources': sources});
    } catch (e) {
      _msgs.add({'role': 'assistant', 'content': 'Error: $e'});
    }
    if (mounted) setState(() => _sending = false);
    _toBottom();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Expanded(
        child: _msgs.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.forum_outlined, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 16),
                  const Text('Ask anything about this codebase', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Answers use the most relevant code retrieved with RAG.', style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 20),
                  Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                    for (final s in _suggestions) ActionChip(label: Text(s), onPressed: () => _send(s)),
                  ]),
                ]),
              )
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(24),
                itemCount: _msgs.length + (_sending ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == _msgs.length) {
                    return const Align(alignment: Alignment.centerLeft, child: Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 40, child: LinearProgressIndicator()),
                    ));
                  }
                  final m = _msgs[i];
                  final user = m['role'] == 'user';
                  return Align(
                    alignment: user ? Alignment.centerRight : Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!user)
                          Container(
                            margin: const EdgeInsets.only(right: 10, top: 8),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                          ),
                        Flexible(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 820),
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: user ? Brand.primary : Theme.of(context).cardTheme.color,
                              borderRadius: BorderRadius.circular(16),
                              border: user ? null : Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
                            ),
                            child: user
                                ? Text(m['content'], style: const TextStyle(color: Colors.white))
                                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    MarkdownView(m['content']),
                                    if ((m['sources'] ?? '').toString().isNotEmpty) ...[
                                      const Divider(height: 24),
                                      Text('Sources: ${m['sources']}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                    ],
                                  ]),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(hintText: 'Ask about the code…', prefixIcon: Icon(Icons.chat_bubble_outline)),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filled(
            style: IconButton.styleFrom(padding: const EdgeInsets.all(16)),
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send),
          ),
        ]),
      ),
    ]);
  }
}

class ReportTab extends StatelessWidget {
  final int pid;
  final String name;
  const ReportTab({super.key, required this.pid, required this.name});
  @override
  Widget build(BuildContext context) => _Page(
        title: 'Project Health Report',
        subtitle: 'Executive summary, metrics, complexity, top issues, vulnerable dependencies and recommendations.',
        icon: Icons.assessment_outlined,
        children: [Card(child: Padding(padding: const EdgeInsets.all(24), child: AiPanel(
          endpoint: '/projects/$pid/report',
          label: 'Generate health report',
          icon: Icons.assessment_outlined,
          downloadName: '$name-health-report.md',
          autoRun: true,
        )))],
      );
}
