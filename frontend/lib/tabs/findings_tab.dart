import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

class FindingsTab extends StatefulWidget {
  final int pid;
  const FindingsTab({super.key, required this.pid});

  @override
  State<FindingsTab> createState() => _FindingsTabState();
}

class _FindingsTabState extends State<FindingsTab> {
  late final Future<dynamic> _future = Api.get('/projects/${widget.pid}/analysis');
  final _severities = <String>{'high', 'medium', 'low'};
  final _categories = <String>{'security', 'bug', 'smell'};
  String _query = '';
  Map<String, dynamic>? _selected;

  static const _catIcon = {'security': Icons.shield_outlined, 'bug': Icons.bug_report_outlined, 'smell': Icons.cleaning_services_outlined};

  @override
  Widget build(BuildContext context) {
    return Loader(
      future: _future,
      builder: (a) {
        final all = (a['findings'] as List).cast<Map<String, dynamic>>();
        final q = _query.toLowerCase();
        final list = all
            .where((f) => _severities.contains(f['severity']) && _categories.contains(f['category']))
            .where((f) => q.isEmpty || '${f['file']} ${f['rule']} ${f['message']}'.toLowerCase().contains(q))
            .toList();
        final wide = MediaQuery.sizeOf(context).width >= 1300;
        final listView = Column(children: [
          _filters(all),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(icon: Icons.filter_alt_off, title: 'No matching findings')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _tile(list[i], wide),
                  ),
          ),
        ]);
        if (!wide) return listView;
        return Row(children: [
          SizedBox(width: 560, child: listView),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selected == null
                ? const EmptyState(icon: Icons.touch_app_outlined, title: 'Select a finding', subtitle: 'See the code and get an AI-generated fix.')
                : FindingDetail(key: ValueKey(_selected), pid: widget.pid, finding: _selected!),
          ),
        ]);
      },
    );
  }

  Widget _filters(List<Map<String, dynamic>> all) {
    int count(String k, String v) => all.where((f) => f[k] == v).length;
    FilterChip chip(String label, Set<String> set, String v, Color? c, String key) => FilterChip(
          label: Text('$label (${count(key, v)})'),
          selected: set.contains(v),
          selectedColor: (c ?? Brand.primary).withValues(alpha: .18),
          onSelected: (on) => setState(() => on ? set.add(v) : set.remove(v)),
        );
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search file, rule or message…', isDense: true),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          chip('High', _severities, 'high', Brand.high, 'severity'),
          chip('Medium', _severities, 'medium', Brand.medium, 'severity'),
          chip('Low', _severities, 'low', Brand.low, 'severity'),
          const SizedBox(width: 8),
          chip('Security', _categories, 'security', null, 'category'),
          chip('Bugs', _categories, 'bug', null, 'category'),
          chip('Smells', _categories, 'smell', null, 'category'),
        ]),
      ]),
    );
  }

  Widget _tile(Map<String, dynamic> f, bool wide) {
    final selected = identical(f, _selected);
    return Card(
      color: selected ? Brand.primary.withValues(alpha: .1) : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (wide) {
            setState(() => _selected = f);
          } else {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => Scaffold(appBar: AppBar(title: Text('${f['rule']}')), body: FindingDetail(pid: widget.pid, finding: f)),
            ));
          }
        },
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: Brand.severity(f['severity']), width: 4))),
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(_catIcon[f['category']] ?? Icons.info_outline, color: Brand.severity(f['severity'])),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  SeverityBadge(f['severity']),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${f['rule']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 6),
                Text('${f['message']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text('${f['file']}:${f['line']}  ·  ${f['tool']}${f['owasp'] != null && '${f['owasp']}'.isNotEmpty && !'${f['owasp']}'.startsWith('http') ? '  ·  ${f['owasp']}' : ''}',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Code around a finding plus the "Fix with AI" diff.
class FindingDetail extends StatefulWidget {
  final int pid;
  final Map<String, dynamic> finding;
  const FindingDetail({super.key, required this.pid, required this.finding});

  @override
  State<FindingDetail> createState() => _FindingDetailState();
}

class _FindingDetailState extends State<FindingDetail> {
  late final Future<String> _code = Api.file(widget.pid, widget.finding['file']);
  Map<String, dynamic>? _fix;
  bool _fixing = false;

  Future<void> _getFix() async {
    setState(() => _fixing = true);
    try {
      final f = widget.finding;
      _fix = Map<String, dynamic>.from(await Api.post('/projects/${widget.pid}/fix',
          {'file': f['file'], 'line': f['line'], 'rule': f['rule'], 'message': f['message']}));
    } catch (e) {
      _fix = {'fixed': null, 'explanation': '$e'};
    }
    if (mounted) setState(() => _fixing = false);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.finding;
    final line = f['line'] as int;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Row(children: [
        SeverityBadge(f['severity']),
        const SizedBox(width: 10),
        Expanded(child: Text('${f['rule']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
      ]),
      const SizedBox(height: 8),
      Text('${f['message']}', style: const TextStyle(fontSize: 15)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        Chip(avatar: const Icon(Icons.insert_drive_file_outlined, size: 16), label: Text('${f['file']}:$line')),
        Chip(avatar: const Icon(Icons.build_outlined, size: 16), label: Text('${f['tool']}')),
        Chip(label: Text('${f['category']}')),
      ]),
      const SizedBox(height: 16),
      Loader<String>(
        future: _code,
        builder: (code) {
          final lines = code.split('\n');
          final lo = (line - 10).clamp(1, lines.length), hi = (line + 10).clamp(1, lines.length);
          return CodeView(
            code: lines.sublist(lo - 1, hi).join('\n'),
            language: languageFor(f['file']),
            startLine: lo,
            highlightLine: line,
          );
        },
      ),
      const SizedBox(height: 20),
      Row(children: [
        FilledButton.icon(
          onPressed: _fixing ? null : _getFix,
          icon: _fixing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.auto_fix_high),
          label: Text(_fixing ? 'Generating fix…' : _fix == null ? 'Fix with AI' : 'Regenerate fix'),
        ),
      ]),
      if (_fix != null) ...[
        const SizedBox(height: 20),
        if (_fix!['fixed'] != null) ...[
          Row(children: [
            const Text('Suggested change', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: _fix!['fixed'])),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy fixed code'),
            ),
          ]),
          const SizedBox(height: 8),
          DiffView(original: _fix!['original'], fixed: _fix!['fixed'], start: _fix!['start'], language: languageFor(f['file'])),
          const SizedBox(height: 16),
        ],
        MarkdownView('${_fix!['explanation']}'),
      ],
    ]);
  }
}
