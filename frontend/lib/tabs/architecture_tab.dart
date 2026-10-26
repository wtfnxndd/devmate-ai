import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Interactive dependency graph, folder tree and Mermaid export.
class ArchitectureTab extends StatelessWidget {
  final int pid;
  const ArchitectureTab({super.key, required this.pid});

  @override
  Widget build(BuildContext context) {
    return Loader(
      future: Api.get('/projects/$pid/architecture'),
      builder: (d) {
        final mermaid = d['mermaid'] as String;
        final edges = [for (final e in d['dependencies'] as List) (e['from'] as String, e['to'] as String)];
        final state = base64Url.encode(utf8.encode(jsonEncode({'code': mermaid, 'mermaid': {'theme': 'dark'}})));
        final wide = MediaQuery.sizeOf(context).width > 900;
        return ListView(padding: EdgeInsets.all(wide ? 28 : 16), children: [
          Section(
            title: 'Module dependency graph',
            icon: Icons.account_tree_outlined,
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Mermaid Live'),
                onPressed: () => launchUrl(Uri.parse('https://mermaid.live/view#base64:$state')),
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy Mermaid'),
                onPressed: () => Clipboard.setData(ClipboardData(text: mermaid)),
              ),
            ],
            child: edges.isEmpty
                ? const Padding(padding: EdgeInsets.all(24), child: Text('No internal imports between files were detected.'))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${edges.length} import edges · arrows point from importer to imported module · drag / scroll to zoom',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                    const SizedBox(height: 12),
                    SizedBox(height: 520, child: DependencyGraph(edges: edges)),
                  ]),
          ),
          const SizedBox(height: 16),
          Section(title: 'Folder structure', icon: Icons.folder_outlined, child: CodeView(code: d['tree'] as String)),
        ]);
      },
    );
  }
}

/// Layered (left → right) graph: each module sits one column before the deepest module it imports.
class DependencyGraph extends StatelessWidget {
  final List<(String, String)> edges;
  const DependencyGraph({super.key, required this.edges});

  static const _nodeW = 170.0, _nodeH = 40.0, _colGap = 90.0, _rowGap = 18.0, _pad = 24.0;

  @override
  Widget build(BuildContext context) {
    final nodes = <String>{for (final e in edges) ...[e.$1, e.$2]}.toList()..sort();
    final deps = {for (final n in nodes) n: <String>{}};
    final fanIn = {for (final n in nodes) n: 0};
    for (final e in edges) {
      deps[e.$1]!.add(e.$2);
      fanIn[e.$2] = fanIn[e.$2]! + 1;
    }
    // Layer = longest path to a leaf; the visiting set cuts import cycles.
    final layer = <String, int>{};
    int depth(String n, Set<String> visiting) {
      if (layer.containsKey(n)) return layer[n]!;
      if (!visiting.add(n)) return 0;
      final d = deps[n]!.isEmpty ? 0 : deps[n]!.map((m) => depth(m, visiting) + 1).reduce(math.max);
      visiting.remove(n);
      return layer[n] = d;
    }

    for (final n in nodes) {
      depth(n, {});
    }
    final maxLayer = layer.values.fold(0, math.max);
    final columns = List.generate(maxLayer + 1, (_) => <String>[]);
    for (final n in nodes) {
      columns[maxLayer - layer[n]!].add(n); // importers left, imported modules right
    }
    final tallest = columns.map((c) => c.length).fold(0, math.max);
    final height = _pad * 2 + tallest * (_nodeH + _rowGap);
    final pos = <String, Offset>{};
    for (var c = 0; c < columns.length; c++) {
      final col = columns[c];
      final top = (height - col.length * (_nodeH + _rowGap)) / 2;
      for (var r = 0; r < col.length; r++) {
        pos[col[r]] = Offset(_pad + c * (_nodeW + _colGap), top + r * (_nodeH + _rowGap));
      }
    }
    final width = _pad * 2 + columns.length * (_nodeW + _colGap) - _colGap;
    final dark = isDark(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: dark ? const Color(0xFF11131A) : const Color(0xFFF6F7FB),
        child: InteractiveViewer(
          constrained: false,
          boundaryMargin: const EdgeInsets.all(400),
          minScale: .2,
          maxScale: 3,
          child: SizedBox(
            width: math.max(width, 600),
            height: math.max(height, 480),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _EdgePainter(edges, pos, const Size(_nodeW, _nodeH)))),
              for (final n in nodes)
                Positioned(
                  left: pos[n]!.dx,
                  top: pos[n]!.dy,
                  width: _nodeW,
                  height: _nodeH,
                  child: Tooltip(
                    message: '$n\nimports ${deps[n]!.length} · imported by ${fanIn[n]}',
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        gradient: fanIn[n]! >= 3 ? Brand.gradient : null,
                        color: fanIn[n]! >= 3 ? null : (dark ? const Color(0xFF1E2230) : Colors.white),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Brand.primary.withValues(alpha: .55)),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .15), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Text(n.split('/').last,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: fanIn[n]! >= 3 ? Colors.white : null)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  final List<(String, String)> edges;
  final Map<String, Offset> pos;
  final Size node;
  _EdgePainter(this.edges, this.pos, this.node);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Brand.primary.withValues(alpha: .55)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final head = Paint()..color = Brand.primary.withValues(alpha: .85);
    for (final (from, to) in edges) {
      final a = pos[from]!, b = pos[to]!;
      final forward = b.dx > a.dx;
      final start = Offset(forward ? a.dx + node.width : a.dx, a.dy + node.height / 2);
      final end = Offset(forward ? b.dx : b.dx + node.width, b.dy + node.height / 2);
      final bend = (end.dx - start.dx).abs() / 2 + 30;
      final s = forward ? 1.0 : -1.0;
      canvas.drawPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(start.dx + bend * s, start.dy, end.dx - bend * s, end.dy, end.dx, end.dy),
        line,
      );
      canvas.drawPath(
        Path()
          ..moveTo(end.dx, end.dy)
          ..lineTo(end.dx - 8 * s, end.dy - 5)
          ..lineTo(end.dx - 8 * s, end.dy + 5)
          ..close(),
        head,
      );
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) => old.edges != edges;
}
