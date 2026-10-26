import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart' show ThemeToggle;
import '../tabs/architecture_tab.dart';
import '../tabs/assist_tabs.dart';
import '../tabs/dashboard_tab.dart';
import '../tabs/dependencies_tab.dart';
import '../tabs/files_tab.dart';
import '../tabs/findings_tab.dart';
import '../tabs/improve_tabs.dart';
import '../theme.dart';

class _Dest {
  final IconData icon;
  final String label;
  final String? group;
  const _Dest(this.icon, this.label, [this.group]);
}

const _dests = [
  _Dest(Icons.space_dashboard_outlined, 'Dashboard', 'ANALYSIS'),
  _Dest(Icons.bug_report_outlined, 'Findings'),
  _Dest(Icons.inventory_2_outlined, 'Dependencies'),
  _Dest(Icons.folder_copy_outlined, 'Files'),
  _Dest(Icons.account_tree_outlined, 'Architecture'),
  _Dest(Icons.rate_review_outlined, 'AI Review', 'AI ASSISTANT'),
  _Dest(Icons.description_outlined, 'Documentation'),
  _Dest(Icons.science_outlined, 'Test Generator'),
  _Dest(Icons.healing_outlined, 'Debugger'),
  _Dest(Icons.forum_outlined, 'Chat'),
  _Dest(Icons.assessment_outlined, 'Health Report'),
  _Dest(Icons.auto_fix_high, 'Fix & Export', 'IMPROVE'),
  _Dest(Icons.copy_all_outlined, 'Duplication'),
  _Dest(Icons.compare_arrows, 'Compare'),
];

/// Lets any tab jump to another tab (e.g. dashboard → findings).
class ProjectNav extends InheritedWidget {
  final void Function(int) go;
  final Future<void> Function() reanalyze;
  const ProjectNav({super.key, required this.go, required this.reanalyze, required super.child});
  static ProjectNav? of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<ProjectNav>();
  @override
  bool updateShouldNotify(ProjectNav old) => false;
}

class ProjectScreen extends StatefulWidget {
  final int id;
  final String name;
  const ProjectScreen({super.key, required this.id, required this.name});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  int _tab = 0;
  int _version = 0; // bump to rebuild tabs after re-analysis
  final _built = <int>{0};

  Widget _page(int i) {
    final pid = widget.id;
    return switch (i) {
      0 => DashboardTab(pid: pid),
      1 => FindingsTab(pid: pid),
      2 => DependenciesTab(pid: pid),
      3 => FilesTab(pid: pid),
      4 => ArchitectureTab(pid: pid),
      5 => ReviewTab(pid: pid),
      6 => DocsTab(pid: pid),
      7 => TestsTab(pid: pid),
      8 => DebugTab(pid: pid),
      9 => ChatTab(pid: pid),
      10 => ReportTab(pid: pid, name: widget.name),
      11 => FixTab(pid: pid, name: widget.name),
      12 => DuplicationTab(pid: pid),
      _ => CompareTab(pid: pid),
    };
  }

  void _go(int i) => setState(() {
        _tab = i;
        _built.add(i);
      });

  Future<void> _reanalyze() async {
    await Api.post('/projects/${widget.id}/reanalyze');
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text('Re-analyzing project…')]),
      ),
    );
    while (true) {
      await Future.delayed(const Duration(seconds: 2));
      final p = await Api.get('/projects/${widget.id}');
      if (p['status'] == 'ready' || '${p['status']}'.startsWith('error')) break;
    }
    if (!mounted) return;
    Navigator.pop(context);
    setState(() {
      _version++;
      _built
        ..clear()
        ..add(_tab);
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final body = KeyedSubtree(
      key: ValueKey(_version),
      child: IndexedStack(
        index: _tab,
        children: [for (var i = 0; i < _dests.length; i++) _built.contains(i) ? _page(i) : const SizedBox()],
      ),
    );
    return ProjectNav(
      go: _go,
      reanalyze: _reanalyze,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: wide ? 24 : 0,
          title: Row(children: [
            Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 12),
            Text('/  ${_dests[_tab].label}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16)),
          ]),
          actions: [
            TextButton.icon(onPressed: _reanalyze, icon: const Icon(Icons.refresh), label: const Text('Re-analyze')),
            const ThemeToggle(),
            const SizedBox(width: 8),
          ],
        ),
        drawer: wide ? null : Drawer(child: _Sidebar(selected: _tab, onSelect: (i) {
          Navigator.pop(context);
          _go(i);
        })),
        body: Row(children: [
          if (wide) _Sidebar(selected: _tab, onSelect: _go),
          Expanded(child: body),
        ]),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int selected;
  final void Function(int) onSelect;
  const _Sidebar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 240,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: cs.outlineVariant.withValues(alpha: .4)))),
      child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
        for (var i = 0; i < _dests.length; i++) ...[
          if (_dests[i].group != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
              child: Text(_dests[i].group!,
                  style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                dense: true,
                selected: i == selected,
                selectedTileColor: Brand.primary.withValues(alpha: .12),
                selectedColor: Brand.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                leading: Icon(_dests[i].icon, size: 20),
                title: Text(_dests[i].label, style: TextStyle(fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500)),
                onTap: () => onSelect(i),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
