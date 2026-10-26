import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../screens/project_screen.dart' show ProjectNav;
import '../theme.dart';
import '../widgets.dart';

// ============================================================== Fix & Export
class FixTab extends StatefulWidget {
  final int pid;
  final String name;
  const FixTab({super.key, required this.pid, required this.name});

  @override
  State<FixTab> createState() => _FixTabState();
}

class _FixTabState extends State<FixTab> {
  Map<String, dynamic>? _changes;
  Map<String, dynamic>? _lastRun;
  bool _busy = false;
  double _limit = 8;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await Api.get('/projects/${widget.pid}/changes');
    if (mounted) setState(() => _changes = Map<String, dynamic>.from(c));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _fixAll() => _run(() async {
        _lastRun = Map<String, dynamic>.from(
            await Api.post('/projects/${widget.pid}/fix-all', null, {'limit': '${_limit.round()}'}));
      });

  Future<void> _revert() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revert all fixes?'),
        content: const Text('Every changed file goes back to its original content.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Revert')),
        ],
      ),
    );
    if (ok == true) {
      await _run(() async {
        await Api.post('/projects/${widget.pid}/fix/revert');
        _lastRun = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _changes;
    final files = (c?['files'] as List?) ?? [];
    final applied = (c?['applied'] as List?) ?? [];
    final patch = (c?['patch'] as String?) ?? '';
    final wide = MediaQuery.sizeOf(context).width > 900;
    return ListView(padding: EdgeInsets.all(wide ? 28 : 16), children: [
      Card(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(colors: [Brand.primary.withValues(alpha: .16), Brand.accent.withValues(alpha: .08)]),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.auto_fix_high, color: Brand.primary),
              SizedBox(width: 10),
              Text('Fix the project', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            Text(
              'DevMate generates a patch for each high and medium issue and applies it to its copy of your code. '
              'Review the diff, re-analyze to verify, then download the fixed project or a .patch for your repository.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Text('Issues to fix:'),
              SizedBox(
                width: 220,
                child: Slider(value: _limit, min: 1, max: 20, divisions: 19, label: '${_limit.round()}',
                    onChanged: _busy ? null : (v) => setState(() => _limit = v)),
              ),
              Text('${_limit.round()}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              FilledButton.icon(
                onPressed: _busy ? null : _fixAll,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_fix_high),
                label: Text(_busy ? 'Fixing…' : 'Fix with AI'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || files.isEmpty ? null : () => ProjectNav.of(context)?.reanalyze(),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Re-analyze to verify'),
              ),
              OutlinedButton.icon(
                onPressed: () => downloadFile(context, '/projects/${widget.pid}/export/zip', '${widget.name}-fixed.zip'),
                icon: const Icon(Icons.folder_zip_outlined),
                label: const Text('Download project (ZIP)'),
              ),
              OutlinedButton.icon(
                onPressed: patch.isEmpty ? null : () => saveText(context, '${widget.name}-devmate.patch', patch),
                icon: const Icon(Icons.difference_outlined),
                label: const Text('Download .patch'),
              ),
              TextButton.icon(
                onPressed: _busy || files.isEmpty ? null : _revert,
                icon: const Icon(Icons.undo),
                label: const Text('Revert all'),
              ),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(spacing: 16, runSpacing: 16, children: [
        SizedBox(width: 240, child: StatCard(icon: Icons.build_circle_outlined, label: 'Fixes applied', value: '${applied.length}', color: Brand.good)),
        SizedBox(width: 240, child: StatCard(icon: Icons.description_outlined, label: 'Files changed', value: '${files.length}')),
        SizedBox(
          width: 240,
          child: StatCard(icon: Icons.difference_outlined, label: 'Patch lines',
              value: '${patch.split('\n').where((l) => (l.startsWith('+') || l.startsWith('-')) && !l.startsWith('+++') && !l.startsWith('---')).length}'),
        ),
      ]),
      if (_lastRun != null) ...[
        const SizedBox(height: 16),
        Section(
          title: 'Last run',
          icon: Icons.history,
          child: Column(children: [
            for (final a in _lastRun!['applied'])
              ListTile(
                dense: true,
                leading: const Icon(Icons.check_circle, color: Brand.good),
                title: Text('${a['rule']}'),
                subtitle: Text('${a['file']}:${a['line']}  ·  -${a['removed']} +${a['added']} lines'),
              ),
            for (final f in _lastRun!['failed'])
              ListTile(
                dense: true,
                leading: const Icon(Icons.error_outline, color: Brand.medium),
                title: Text('${f['rule']}  (skipped)'),
                subtitle: Text('${f['file']}:${f['line']} · ${f['reason']}', maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      Section(
        title: 'Changes',
        icon: Icons.difference_outlined,
        actions: [
          if (patch.isNotEmpty)
            IconButton(tooltip: 'Copy patch', icon: const Icon(Icons.copy, size: 18),
                onPressed: () => Clipboard.setData(ClipboardData(text: patch))),
        ],
        child: patch.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No changes yet. Use "Fix with AI" here, or "Apply to project" on a single finding.'),
              )
            : PatchView(patch),
      ),
      const SizedBox(height: 12),
      Text('Apply the patch to your own repository with:  git apply ${widget.name}-devmate.patch',
          style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);
  }
}

/// Coloured unified diff.
class PatchView extends StatelessWidget {
  final String patch;
  const PatchView(this.patch, {super.key});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.45);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isDark(context) ? const Color(0xFF11131A) : const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final l in patch.split('\n'))
            Container(
              color: l.startsWith('+++') || l.startsWith('---')
                  ? null
                  : l.startsWith('+')
                      ? Brand.good.withValues(alpha: .16)
                      : l.startsWith('-')
                          ? Brand.high.withValues(alpha: .16)
                          : null,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                l,
                style: style.copyWith(
                  color: l.startsWith('@@') ? Brand.primary : l.startsWith('+++') || l.startsWith('---') ? muted : null,
                  fontWeight: l.startsWith('+++') || l.startsWith('---') ? FontWeight.w700 : null,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ============================================================== Duplication
class DuplicationTab extends StatelessWidget {
  final int pid;
  const DuplicationTab({super.key, required this.pid});

  @override
  Widget build(BuildContext context) {
    return Loader(
      future: Api.get('/projects/$pid/duplicates'),
      builder: (d) {
        final blocks = (d['blocks'] as List?) ?? [];
        final pct = (d['percentage'] ?? 0) as num;
        final wide = MediaQuery.sizeOf(context).width > 900;
        return ListView(padding: EdgeInsets.all(wide ? 28 : 16), children: [
          Wrap(spacing: 16, runSpacing: 16, children: [
            SizedBox(
              width: 260,
              child: StatCard(icon: Icons.copy_all_outlined, label: 'Duplicated code', value: '$pct%',
                  color: pct > 10 ? Brand.high : pct > 5 ? Brand.medium : Brand.good, hint: 'target: under 5%'),
            ),
            SizedBox(width: 260, child: StatCard(icon: Icons.content_copy, label: 'Clone groups', value: '${blocks.length}')),
            SizedBox(width: 260, child: StatCard(icon: Icons.notes, label: 'Duplicated lines', value: '${d['duplicated_lines'] ?? 0}')),
          ]),
          const SizedBox(height: 20),
          if (blocks.isEmpty)
            const EmptyState(icon: Icons.verified_outlined, title: 'No duplicated code found', subtitle: 'No block of 6+ meaningful lines appears twice.')
          else
            for (var i = 0; i < blocks.length; i++)
              Padding(padding: const EdgeInsets.only(bottom: 14), child: _CloneCard(pid: pid, index: i, block: blocks[i])),
        ]);
      },
    );
  }
}

class _CloneCard extends StatefulWidget {
  final int pid, index;
  final dynamic block;
  const _CloneCard({required this.pid, required this.index, required this.block});
  @override
  State<_CloneCard> createState() => _CloneCardState();
}

class _CloneCardState extends State<_CloneCard> {
  bool _refactor = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    final occ = b['occurrences'] as List;
    final first = occ.first;
    return Section(
      title: '${b['lines']} lines × ${occ.length} copies',
      icon: Icons.content_copy,
      actions: [
        if (!_refactor)
          FilledButton.tonalIcon(
            onPressed: () => setState(() => _refactor = true),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Suggest refactor'),
          ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in occ)
            Chip(avatar: const Icon(Icons.insert_drive_file_outlined, size: 16), label: Text('${o['file']}:${o['start']}-${o['end']}')),
        ]),
        const SizedBox(height: 12),
        CodeView(code: b['snippet'], language: languageFor(first['file']), startLine: first['start']),
        if (_refactor) ...[
          const SizedBox(height: 16),
          AiPanel(
            endpoint: '/projects/${widget.pid}/duplicates/${widget.index}/refactor',
            label: 'Suggest refactor',
            downloadName: 'refactor-duplicate-${widget.index + 1}.md',
            autoRun: true,
          ),
        ],
      ]),
    );
  }
}

// ============================================================== Compare
class CompareTab extends StatefulWidget {
  final int pid;
  const CompareTab({super.key, required this.pid});
  @override
  State<CompareTab> createState() => _CompareTabState();
}

class _CompareTabState extends State<CompareTab> {
  int _a = -2, _b = -1;
  int? _other;
  Future<dynamic>? _cmp;
  late final Future<dynamic> _projects = Api.get('/projects');
  Future<dynamic>? _side;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _cmp = Api.get('/projects/${widget.pid}/compare?a=$_a&b=$_b'));

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const TabBar(tabAlignment: TabAlignment.start, isScrollable: true, tabs: [
          Tab(icon: Icon(Icons.timeline), text: 'Analysis history'),
          Tab(icon: Icon(Icons.compare_arrows), text: 'Compare projects'),
        ]),
        Expanded(
          child: TabBarView(children: [
            ListView(padding: EdgeInsets.all(wide ? 28 : 16), children: [_history()]),
            ListView(padding: EdgeInsets.all(wide ? 28 : 16), children: [_projectsCompare()]),
          ]),
        ),
      ]),
    );
  }

  Widget _history() => FutureBuilder(
        future: _cmp,
        builder: (_, snap) {
          if (snap.hasError) {
            return EmptyState(icon: Icons.timeline, title: 'Nothing to compare yet', subtitle: '${snap.error}');
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final d = snap.data;
          final hist = d['history'] as List;
          String label(int i) {
            final h = hist[i];
            return '#${i + 1} · ${'${h['at']}'.replaceFirst('T', ' ').substring(0, 16)} · score ${h['score']}';
          }

          int idx(int v) => v < 0 ? hist.length + v : v;
          final from = d['from'], to = d['to'];
          final delta = (to['score'] as num) - (from['score'] as num);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              DropdownMenu<int>(
                width: 320,
                label: const Text('From'),
                initialSelection: idx(_a),
                dropdownMenuEntries: [for (var i = 0; i < hist.length; i++) DropdownMenuEntry(value: i, label: label(i))],
                onSelected: (v) {
                  _a = v!;
                  _reload();
                },
              ),
              const Icon(Icons.arrow_forward),
              DropdownMenu<int>(
                width: 320,
                label: const Text('To'),
                initialSelection: idx(_b),
                dropdownMenuEntries: [for (var i = 0; i < hist.length; i++) DropdownMenuEntry(value: i, label: label(i))],
                onSelected: (v) {
                  _b = v!;
                  _reload();
                },
              ),
            ]),
            const SizedBox(height: 20),
            Wrap(spacing: 16, runSpacing: 16, children: [
              SizedBox(
                width: 260,
                child: StatCard(
                  icon: delta >= 0 ? Icons.trending_up : Icons.trending_down,
                  label: 'Health score',
                  value: '${from['score']} → ${to['score']}',
                  color: delta >= 0 ? Brand.good : Brand.high,
                  hint: '${delta >= 0 ? '+' : ''}$delta points',
                ),
              ),
              SizedBox(width: 260, child: StatCard(icon: Icons.check_circle_outline, label: 'Issues fixed', value: '${(d['fixed'] as List).length}', color: Brand.good)),
              SizedBox(width: 260, child: StatCard(icon: Icons.new_releases_outlined, label: 'New issues', value: '${(d['new'] as List).length}', color: Brand.high)),
              SizedBox(width: 260, child: StatCard(icon: Icons.drag_handle, label: 'Unchanged', value: '${d['unchanged']}')),
            ]),
            if (d['comparable'] == false)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Card(child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('One of these analyses was recorded before issue tracking existed. Only totals can be compared. Pick newer analyses.'),
                )),
              ),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (_, c) {
              final fixed = _issueList('Fixed', d['fixed'], Brand.good, Icons.check_circle);
              final added = _issueList('New', d['new'], Brand.high, Icons.add_circle);
              return c.maxWidth > 900
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: fixed),
                      const SizedBox(width: 16),
                      Expanded(child: added),
                    ])
                  : Column(children: [fixed, const SizedBox(height: 16), added]);
            }),
          ]);
        },
      );

  Widget _issueList(String title, List items, Color c, IconData icon) => Section(
        title: '$title (${items.length})',
        icon: icon,
        child: items.isEmpty
            ? const Text('None')
            : Column(children: [
                for (final f in items.take(60))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(icon, color: c, size: 18),
                    title: Text('${f['rule']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${f['file']} · ${f['message']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: SeverityBadge(f['severity']),
                  ),
              ]),
      );

  Widget _projectsCompare() => Loader(
        future: _projects,
        builder: (ps) {
          final others = (ps as List).where((p) => p['id'] != widget.pid && p['status'] == 'ready').toList();
          if (others.isEmpty) {
            return const EmptyState(icon: Icons.compare_arrows, title: 'No other project to compare', subtitle: 'Import another project first.');
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownMenu<int>(
              width: 420,
              label: const Text('Compare with'),
              dropdownMenuEntries: [for (final p in others) DropdownMenuEntry(value: p['id'] as int, label: '${p['name']} (#${p['id']})')],
              onSelected: (v) => setState(() {
                _other = v;
                _side = Api.get('/compare-projects?a=${widget.pid}&b=$v');
              }),
            ),
            const SizedBox(height: 20),
            if (_other != null) Loader(future: _side!, builder: (rows) => _sideBySide(rows as List)),
          ]);
        },
      );

  Widget _sideBySide(List rows) {
    final a = rows[0], b = rows[1];
    // (label, valueA, valueB, higherIsBetter)
    final metrics = <(String, num?, num?, bool)>[
      ('Health score', a['score'], b['score'], true),
      ('Files', a['files'], b['files'], true),
      ('Lines of code', a['lines'], b['lines'], true),
      ('Functions', a['functions'], b['functions'], true),
      ('High-severity issues', a['counts']?['high'], b['counts']?['high'], false),
      ('Medium-severity issues', a['counts']?['medium'], b['counts']?['medium'], false),
      ('Security issues', a['by_category']?['security'], b['by_category']?['security'], false),
      ('Avg complexity', a['avg_complexity'], b['avg_complexity'], false),
      ('Duplication %', a['duplication'], b['duplication'], false),
      ('Vulnerable packages', a['vulnerable_deps'], b['vulnerable_deps'], false),
    ];
    Widget cell(num? v, num? other, bool hib) {
      final better = v != null && other != null && v != other && ((v > other) == hib);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(children: [
          Text('${v ?? '–'}', style: TextStyle(fontWeight: FontWeight.w700, color: better ? Brand.good : null)),
          if (better) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.emoji_events_outlined, size: 16, color: Brand.good)),
        ]),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Table(
          columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1.4), 2: FlexColumnWidth(1.4)},
          border: TableBorder(horizontalInside: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .4))),
          children: [
            TableRow(children: [
              const Padding(padding: EdgeInsets.all(12), child: Text('Metric', style: TextStyle(fontWeight: FontWeight.w800))),
              Padding(padding: const EdgeInsets.all(12), child: Text('${a['name']}', style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.primary))),
              Padding(padding: const EdgeInsets.all(12), child: Text('${b['name']}', style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.accent))),
            ]),
            for (final m in metrics)
              TableRow(children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12), child: Text(m.$1)),
                cell(m.$2, m.$3, m.$4),
                cell(m.$3, m.$2, m.$4),
              ]),
          ],
        ),
      ),
    );
  }
}
