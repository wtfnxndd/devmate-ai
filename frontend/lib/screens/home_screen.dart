import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart' show ThemeToggle;
import '../theme.dart';
import '../widgets.dart';
import 'project_screen.dart';

const pipelineStages = ['ingested', 'queued', 'parsing', 'analyzing', 'scanning dependencies', 'indexing', 'ready'];

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
  bool _loaded = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_projects.any((p) => p['status'] != 'ready' && !'${p['status']}'.startsWith('error'))) _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final health = await Api.get('/health');
      final r = [await Api.get('/projects'), health];
      if (!mounted) return;
      setState(() {
        _projects = r[0];
        _providers = r[1]['llm_providers'];
        _error = null;
        _loaded = true;
      });
    } catch (e) {
      if (e is ApiException && e.message.contains('token')) {
        if (mounted) setState(() => _error = 'This server needs an access token. Set it with ⚙ (top right).');
        return;
      }
      if (mounted) setState(() => _error = 'Cannot reach the DevMate backend at ${Api.baseUrl}. Start it with start.sh, or set the backend URL (⚙ top right).');
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

  Future<void> _askText(String title, String hint, String endpoint, String key, IconData icon) async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon),
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Analyze')),
        ],
      ),
    );
    if (value != null && value.isNotEmpty) await _run(() => Api.post(endpoint, {key: value}));
  }

  Future<void> _backendSettings() async {
    final ctrl = TextEditingController(text: Api.baseUrl);
    final tokenCtrl = TextEditingController(text: Api.token);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.settings_ethernet),
        title: const Text('Backend URL'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Where the DevMate API runs: http://localhost:8000 locally, or your Cloudflare Tunnel URL.'),
            const SizedBox(height: 12),
            TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'URL', hintText: 'https://xxxx.trycloudflare.com')),
            const SizedBox(height: 12),
            TextField(
              controller: tokenCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Access token (if the server requires one)'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (url != null && url.trim().startsWith('http')) {
      await Api.configure(url, tokenCtrl.text);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = width > 900 ? 40.0 : 16.0;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: _hero(pad)),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 24, pad, 8),
          sliver: SliverToBoxAdapter(child: _importRow()),
        ),
        if (_error != null)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8),
            sliver: SliverToBoxAdapter(
              child: Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(leading: const Icon(Icons.cloud_off), title: Text(_error!),
                    trailing: TextButton(onPressed: _load, child: const Text('Retry'))),
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 24, pad, 12),
          sliver: SliverToBoxAdapter(
            child: Row(children: [
              const Text('Projects', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              if (_projects.isNotEmpty) Chip(label: Text('${_projects.length}'), visualDensity: VisualDensity.compact),
              const Spacer(),
              if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
          ),
        ),
        if (_loaded && _projects.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.rocket_launch_outlined,
              title: 'No projects yet',
              subtitle: 'Upload a ZIP or paste a GitHub link to get a full review, docs, tests and a health report.',
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 40),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 420,
              mainAxisExtent: 190,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _projects.length,
            itemBuilder: (_, i) => _ProjectCard(project: _projects[i], onChanged: _load),
          ),
        ),
      ]),
    );
  }

  Widget _hero(double pad) => Container(
        decoration: const BoxDecoration(gradient: Brand.gradient),
        padding: EdgeInsets.fromLTRB(pad, 28, pad, 36),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .2), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.hub_outlined, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text('DevMate AI', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            const Spacer(),
            _LlmChip(_providers),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Backend URL',
              icon: const Icon(Icons.settings_ethernet, color: Colors.white),
              onPressed: _backendSettings,
            ),
            const IconTheme(data: IconThemeData(color: Colors.white), child: ThemeToggle()),
          ]),
          const SizedBox(height: 32),
          const Text('Intelligent Software Review,\nDebugging & Documentation',
              style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, height: 1.15)),
          const SizedBox(height: 12),
          Text(
            'Static analysis, OWASP security scanning, dependency CVEs, AI fixes, docs, tests and debugging, all free.',
            style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 15),
          ),
        ]),
      );

  Widget _importRow() {
    final cards = [
      _ImportCard(icon: Icons.folder_zip_outlined, title: 'Upload ZIP', subtitle: 'Any project archive', onTap: _busy ? null : _uploadZip),
      _ImportCard(
        icon: Icons.code,
        title: 'GitHub repository',
        subtitle: 'Public repo URL',
        onTap: _busy ? null : () => _askText('Import from GitHub', 'https://github.com/owner/repo', '/projects/github', 'url', Icons.code),
      ),
      if (!kIsWeb)
        _ImportCard(
          icon: Icons.folder_open_outlined,
          title: 'Local folder',
          subtitle: 'Path on this computer',
          onTap: _busy ? null : () => _askText('Local directory', '/path/to/project', '/projects/local', 'path', Icons.folder_open),
        ),
    ];
    return LayoutBuilder(
      builder: (_, c) => c.maxWidth > 700
          ? Row(children: [for (final w in cards) Expanded(child: Padding(padding: const EdgeInsets.only(right: 16), child: w))])
          : Column(children: [for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: w)]),
    );
  }
}

class _LlmChip extends StatelessWidget {
  final List<dynamic> providers;
  const _LlmChip(this.providers);
  @override
  Widget build(BuildContext context) => Tooltip(
        message: providers.isEmpty ? 'Add a free GEMINI_API_KEY in backend/.env' : 'LLM fallback chain',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(providers.isEmpty ? Icons.memory : Icons.auto_awesome, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(providers.isEmpty ? 'Static mode' : 'AI · ${providers.join(" → ")}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

class _ImportCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  const _ImportCard({required this.icon, required this.title, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
              ),
              const Icon(Icons.arrow_forward_rounded),
            ]),
          ),
        ),
      );
}

class _ProjectCard extends StatelessWidget {
  final dynamic project;
  final VoidCallback onChanged;
  const _ProjectCard({required this.project, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final status = project['status'] as String;
    final ready = status == 'ready';
    final failed = status.startsWith('error');
    final s = project['summary'];
    final counts = project['counts'];
    final langs = s == null ? <String>[] : (s['languages'] as Map).keys.cast<String>().toList();
    final stage = pipelineStages.indexOf(status);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: ready
            ? () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ProjectScreen(id: project['id'], name: project['name'])));
                onChanged();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            ready
                ? ScoreRing(score: project['health_score'], size: 92)
                : SizedBox(
                    width: 92,
                    height: 92,
                    child: failed
                        ? const Icon(Icons.error_outline, size: 40, color: Brand.high)
                        : const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()),
                  ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(children: [
                  Expanded(
                    child: Text(project['name'], overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  PopupMenuButton<String>(
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'reanalyze', child: Text('Re-analyze')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                    onSelected: (v) async {
                      if (v == 'delete') await Api.delete('/projects/${project['id']}');
                      if (v == 'reanalyze') await Api.post('/projects/${project['id']}/reanalyze');
                      onChanged();
                    },
                  ),
                ]),
                if (s != null) Text('${s['files']} files · ${s['lines']} lines', style: TextStyle(color: muted)),
                const SizedBox(height: 8),
                if (ready && counts != null)
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    _pill('${counts['high']} high', Brand.high),
                    _pill('${counts['medium']} med', Brand.medium),
                    if ((project['vulnerable_deps'] ?? 0) > 0) _pill('${project['vulnerable_deps']} vuln deps', Brand.high),
                    for (final l in langs.take(2)) _pill(l, Brand.primary),
                  ])
                else if (failed)
                  Text(project['error'] ?? status, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Brand.high))
                else ...[
                  Text('${status[0].toUpperCase()}${status.substring(1)}…', style: TextStyle(color: muted)),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: stage < 0 ? null : (stage + 1) / pipelineStages.length),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _pill(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: .13), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
      );
}
