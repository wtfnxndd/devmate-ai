import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../screens/project_screen.dart' show ProjectNav;
import '../theme.dart';
import '../widgets.dart';

class DashboardTab extends StatelessWidget {
  final int pid;
  const DashboardTab({super.key, required this.pid});

  @override
  Widget build(BuildContext context) {
    return Loader<List<dynamic>>(
      future: Future.wait([
        Api.get('/projects/$pid/structure'),
        Api.get('/projects/$pid/analysis'),
        Api.get('/projects/$pid/dependencies'),
        Api.get('/projects/$pid/history'),
      ]),
      builder: (d) => _Dashboard(pid: pid, structure: d[0], analysis: d[1], deps: d[2], history: d[3]),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final int pid;
  final dynamic structure, analysis, deps;
  final List<dynamic> history;
  const _Dashboard({required this.pid, required this.structure, required this.analysis, required this.deps, required this.history});

  @override
  Widget build(BuildContext context) {
    final s = structure['summary'], a = analysis;
    final width = MediaQuery.sizeOf(context).width;
    final cols = width > 1400 ? 3 : width > 900 ? 2 : 1;
    final nav = ProjectNav.of(context);

    final kpis = [
      StatCard(icon: Icons.description_outlined, label: 'Source files', value: '${s['files']}'),
      StatCard(icon: Icons.notes, label: 'Lines of code', value: '${s['lines']}'),
      StatCard(icon: Icons.functions, label: 'Classes / functions', value: '${s['classes']} / ${s['functions']}'),
      StatCard(icon: Icons.shield_outlined, label: 'Security issues', value: '${a['by_category']['security']}', color: Brand.high),
      StatCard(icon: Icons.inventory_2_outlined, label: 'Vulnerable packages', value: '${deps['vulnerable']}',
          color: deps['vulnerable'] > 0 ? Brand.high : Brand.good, hint: '${deps['total_vulns']} CVEs'),
      StatCard(icon: Icons.device_hub, label: 'Avg complexity', value: '${a['avg_complexity']}',
          color: (a['avg_complexity'] as num) > 10 ? Brand.medium : Brand.good),
    ];

    final charts = <Widget>[
      Section(title: 'Issues by severity', icon: Icons.donut_large, child: _severityDonut(a['counts'])),
      Section(title: 'Issues by category', icon: Icons.bar_chart, child: _categoryBars(context, a['by_category'])),
      Section(title: 'Languages', icon: Icons.translate, child: _languages(context, s['languages'])),
      if (history.length > 1) Section(title: 'Health trend', icon: Icons.show_chart, child: _trend(context)),
      Section(
        title: 'Most complex functions',
        icon: Icons.whatshot_outlined,
        actions: [TextButton(onPressed: () => nav?.go(3), child: const Text('Files →'))],
        child: _complexity(context, a['complex_functions']),
      ),
      Section(
        title: 'Top findings',
        icon: Icons.priority_high,
        actions: [TextButton(onPressed: () => nav?.go(1), child: const Text('All →'))],
        child: Column(children: [
          for (final f in (a['findings'] as List).take(6))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: SeverityBadge(f['severity']),
              title: Text('${f['rule']}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${f['file']}:${f['line']}', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          if ((a['findings'] as List).isEmpty) const Text('No issues found 🎉'),
        ]),
      ),
    ];

    return ListView(padding: EdgeInsets.all(width > 900 ? 28 : 16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(spacing: 32, runSpacing: 20, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ScoreRing(score: a['health_score'], grade: a['grade'], size: 150),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Project health', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(_verdict(a['health_score']), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15)),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  Chip(avatar: const Icon(Icons.code, size: 16), label: Text('Code score ${a['code_score'] ?? a['health_score']}')),
                  if (deps['vulnerable'] > 0)
                    Chip(avatar: const Icon(Icons.warning_amber, size: 16, color: Brand.high), label: Text('−${(a['code_score'] ?? a['health_score']) - a['health_score']} for vulnerable dependencies')),
                  Chip(avatar: const Icon(Icons.build_outlined, size: 16), label: Text((a['tools'] as List).join(' · '))),
                ]),
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  FilledButton.icon(onPressed: () => nav?.go(5), icon: const Icon(Icons.auto_awesome), label: const Text('AI review')),
                  OutlinedButton.icon(onPressed: () => nav?.go(10), icon: const Icon(Icons.assessment_outlined), label: const Text('Health report')),
                ]),
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      _grid(kpis, width > 1700 ? 6 : width > 700 ? 3 : 2, 92),
      const SizedBox(height: 16),
      _masonry(charts, cols),
    ]);
  }

  String _verdict(num score) {
    if (score >= 85) return 'Excellent: clean, secure and maintainable. Keep it up.';
    if (score >= 70) return 'Good overall, with a few issues worth fixing.';
    if (score >= 55) return 'Fair. Several issues need attention, especially high-severity ones.';
    return 'Needs work. Fix the security and high-severity findings first.';
  }

  Widget _grid(List<Widget> items, int cols, double height) => LayoutBuilder(
        builder: (_, c) {
          final w = (c.maxWidth - (cols - 1) * 16) / cols;
          return Wrap(spacing: 16, runSpacing: 16, children: [for (final i in items) SizedBox(width: w, height: height, child: i)]);
        },
      );

  Widget _masonry(List<Widget> items, int cols) {
    final columns = List.generate(cols, (_) => <Widget>[]);
    for (var i = 0; i < items.length; i++) {
      columns[i % cols].add(Padding(padding: const EdgeInsets.only(bottom: 16), child: items[i]));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < cols; i++) ...[
        if (i > 0) const SizedBox(width: 16),
        Expanded(child: Column(children: columns[i])),
      ],
    ]);
  }

  Widget _severityDonut(dynamic counts) {
    final data = [('High', counts['high'] as int, Brand.high), ('Medium', counts['medium'] as int, Brand.medium), ('Low', counts['low'] as int, Brand.low)];
    final total = data.fold<int>(0, (s, e) => s + e.$2);
    if (total == 0) return const SizedBox(height: 120, child: Center(child: Text('No issues 🎉')));
    return Row(children: [
      SizedBox(
        width: 160,
        height: 160,
        child: Stack(alignment: Alignment.center, children: [
          PieChart(PieChartData(
            centerSpaceRadius: 50,
            sectionsSpace: 3,
            sections: [
              for (final d in data)
                if (d.$2 > 0) PieChartSectionData(value: d.$2.toDouble(), color: d.$3, radius: 22, showTitle: false),
            ],
          )),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$total', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const Text('issues'),
          ]),
        ]),
      ),
      const SizedBox(width: 24),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final d in data)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: d.$3, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 10),
                Expanded(child: Text(d.$1)),
                Text('${d.$2}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _categoryBars(BuildContext context, dynamic cat) {
    final data = [('Security', cat['security'] as int, Brand.high), ('Bugs', cat['bug'] as int, Brand.medium), ('Smells', cat['smell'] as int, Brand.primary)];
    final maxV = data.map((e) => e.$2).fold<int>(1, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 180,
      child: BarChart(BarChartData(
        maxY: maxV * 1.25,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: const BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, _) => Text('${data[v.toInt()].$2}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 26, getTitlesWidget: (v, _) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(data[v.toInt()].$1),
            )),
          ),
        ),
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: data[i].$2.toDouble(),
                width: 34,
                color: data[i].$3,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
            ]),
        ],
      )),
    );
  }

  Widget _languages(BuildContext context, Map langs) {
    final total = langs.values.fold<num>(0, (a, b) => a + b);
    final entries = langs.entries.toList()..sort((a, b) => (b.value as num).compareTo(a.value as num));
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 12,
          child: Row(children: [
            for (var i = 0; i < entries.length; i++)
              Expanded(
                flex: ((entries[i].value as num) * 1000 / (total == 0 ? 1 : total)).round().clamp(1, 1000),
                child: Container(color: Brand.languageColors[i % Brand.languageColors.length]),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      for (var i = 0; i < entries.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(Icons.circle, size: 10, color: Brand.languageColors[i % Brand.languageColors.length]),
            const SizedBox(width: 10),
            Expanded(child: Text('${entries[i].key}')),
            Text('${entries[i].value} lines · ${((entries[i].value as num) * 100 / (total == 0 ? 1 : total)).toStringAsFixed(1)}%'),
          ]),
        ),
    ]);
  }

  Widget _trend(BuildContext context) {
    final spots = [for (var i = 0; i < history.length; i++) FlSpot(i.toDouble(), (history[i]['score'] as num).toDouble())];
    return SizedBox(
      height: 180,
      child: LineChart(LineChartData(
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) => FlLine(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .4), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, interval: 1, reservedSize: 22, getTitlesWidget: (v, _) => Text('#${v.toInt() + 1}', style: const TextStyle(fontSize: 11))),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, interval: 25, reservedSize: 32, getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(fontSize: 11))),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 3,
            color: Brand.primary,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [Brand.primary.withValues(alpha: .3), Brand.primary.withValues(alpha: 0)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      )),
    );
  }

  Widget _complexity(BuildContext context, List fns) {
    if (fns.isEmpty) return const Text('No functions found.');
    final maxC = fns.map((f) => f['complexity'] as num).reduce((a, b) => a > b ? a : b);
    return Column(children: [
      for (final f in fns.take(7))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${f['function']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text('${f['complexity']}', style: TextStyle(fontWeight: FontWeight.w800, color: _ccColor(f['complexity']))),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (f['complexity'] as num) / (maxC < 10 ? 10 : maxC),
                minHeight: 6,
                color: _ccColor(f['complexity']),
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
            Text('${f['file']}:${f['line']}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
    ]);
  }

  Color _ccColor(num c) => c > 20 ? Brand.high : c > 10 ? Brand.medium : Brand.good;
}
