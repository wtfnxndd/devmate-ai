import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'theme.dart';

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

/// Circular health-score gauge.
class ScoreRing extends StatelessWidget {
  final num? score;
  final String? grade;
  final double size;
  const ScoreRing({super.key, this.score, this.grade, this.size = 140});

  @override
  Widget build(BuildContext context) {
    final c = Brand.score(score);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: (score ?? 0) / 100),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => CustomPaint(
          painter: _RingPainter(v, c, Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .35)),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(score == null ? '–' : '${(v * 100).round()}',
                  style: TextStyle(fontSize: size * .26, fontWeight: FontWeight.w800, color: c)),
              if (grade != null)
                Text('Grade $grade', style: TextStyle(fontSize: size * .1, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color, track;
  _RingPainter(this.value, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * .09;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * value, false, Paint()
      ..shader = SweepGradient(colors: [color.withValues(alpha: .6), color], transform: const GradientRotation(-math.pi / 2)).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.value != value || o.color != color;
}

/// KPI tile.
class StatCard extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color? color;
  final String? hint;
  const StatCard({super.key, required this.icon, required this.label, required this.value, this.color, this.hint});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: c),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
              if (hint != null) Text(hint!, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Titled card section.
class Section extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final IconData? icon;
  const Section({super.key, required this.title, required this.child, this.actions = const [], this.icon});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8)],
              Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              ...actions,
            ]),
            const SizedBox(height: 16),
            child,
          ]),
        ),
      );
}

class SeverityBadge extends StatelessWidget {
  final String severity;
  const SeverityBadge(this.severity, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = Brand.severity(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(6)),
      child: Text(severity.toUpperCase(), style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .5)),
    );
  }
}

class AiBadge extends StatelessWidget {
  final bool ai;
  const AiBadge(this.ai, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: ai ? Brand.gradient : null,
          color: ai ? null : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ai ? Icons.auto_awesome : Icons.rule, size: 14, color: ai ? Colors.white : null),
          const SizedBox(width: 6),
          Text(ai ? 'AI-enhanced' : 'Static analysis',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ai ? Colors.white : null)),
        ]),
      );
}

String languageFor(String file) {
  final ext = file.split('.').last.toLowerCase();
  return const {
        'py': 'python', 'js': 'javascript', 'jsx': 'javascript', 'ts': 'typescript', 'tsx': 'typescript',
        'java': 'java', 'kt': 'kotlin', 'go': 'go', 'rs': 'rust', 'c': 'cpp', 'h': 'cpp', 'cpp': 'cpp',
        'cs': 'cs', 'rb': 'ruby', 'php': 'php', 'dart': 'dart', 'swift': 'swift',
      }[ext] ??
      'plaintext';
}

/// Syntax-highlighted code block.
class CodeView extends StatelessWidget {
  final String code;
  final String language;
  final int? startLine;
  final int? highlightLine;
  const CodeView({super.key, required this.code, this.language = 'plaintext', this.startLine, this.highlightLine});

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final theme = Map.of(dark ? atomOneDarkTheme : atomOneLightTheme);
    final bg = dark ? const Color(0xFF11131A) : const Color(0xFFF6F7FB);
    theme['root'] = (theme['root'] ?? const TextStyle()).copyWith(backgroundColor: bg);
    final lines = code.split('\n');
    const style = TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5);
    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (startLine != null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 14, 10, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < lines.length; i++)
                  Container(
                    color: startLine! + i == highlightLine ? Brand.medium.withValues(alpha: .25) : null,
                    child: Text('${startLine! + i}', style: style.copyWith(color: Colors.grey)),
                  ),
              ]),
            ),
          HighlightView(code, language: language, theme: theme, padding: const EdgeInsets.all(14), textStyle: style),
        ]),
      ),
    );
  }
}

/// Before/after view for an AI fix.
class DiffView extends StatelessWidget {
  final String original, fixed;
  final int start;
  final String language;
  const DiffView({super.key, required this.original, required this.fixed, required this.start, required this.language});

  @override
  Widget build(BuildContext context) {
    final a = original.split('\n'), b = fixed.split('\n');
    final rows = <Widget>[];
    const style = TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5);
    // Simple LCS-based line diff.
    final n = a.length, m = b.length;
    final dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : math.max(dp[i + 1][j], dp[i][j + 1]);
      }
    }
    var i = 0, j = 0;
    Widget line(String sign, String text, Color? bg) => Container(
          width: double.infinity,
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('$sign $text', style: style),
        );
    while (i < n || j < m) {
      if (i < n && j < m && a[i] == b[j]) {
        rows.add(line(' ', a[i], null));
        i++;
        j++;
      } else if (i < n && (j >= m || dp[i + 1][j] >= dp[i][j + 1])) {
        rows.add(line('-', a[i++], Brand.high.withValues(alpha: .18))); // removals first, like git
      } else {
        rows.add(line('+', b[j++], Brand.good.withValues(alpha: .18)));
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isDark(context) ? const Color(0xFF11131A) : const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }
}

/// Markdown renderer with syntax-highlighted code blocks.
class MarkdownView extends StatelessWidget {
  final String data;
  const MarkdownView(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return MarkdownBody(
      data: data,
      selectable: true,
      onTapLink: (_, href, __) => href != null ? launchUrl(Uri.parse(href)) : null,
      builders: {'code': _CodeBuilder()},
      styleSheet: MarkdownStyleSheet.fromTheme(t).copyWith(
        h1: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        h2: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        h3: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        blockSpacing: 12,
        code: TextStyle(fontFamily: 'monospace', fontSize: 13, backgroundColor: t.colorScheme.surfaceContainerHighest),
        codeblockDecoration: const BoxDecoration(),
        codeblockPadding: EdgeInsets.zero,
        tableBorder: TableBorder.all(color: t.colorScheme.outlineVariant),
        tableCellsPadding: const EdgeInsets.all(8),
        blockquoteDecoration: BoxDecoration(
          color: t.colorScheme.primary.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: t.colorScheme.primary, width: 4)),
        ),
      ),
    );
  }
}

class _CodeBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(BuildContext context, element, preferredStyle, parentStyle) {
    final cls = element.attributes['class'];
    final text = element.textContent;
    if (cls == null && !text.contains('\n')) return null; // inline code: default style
    final lang = cls?.replaceFirst('language-', '') ?? 'plaintext';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Stack(children: [
        SizedBox(width: double.infinity, child: CodeView(code: text.trimRight(), language: lang == 'mermaid' ? 'plaintext' : lang)),
        Positioned(
          right: 6,
          top: 6,
          child: IconButton(
            tooltip: 'Copy',
            iconSize: 16,
            icon: const Icon(Icons.copy),
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
          ),
        ),
      ]),
    );
  }
}

/// Saves text as a file (browser download on web, save dialog on desktop).
Future<void> saveText(BuildContext context, String name, String text) async {
  try {
    await FilePicker.platform.saveFile(fileName: name, bytes: utf8.encode(text));
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
    }
  }
}

/// Button → calls an engine endpoint → renders Markdown, with copy/download/regenerate.
class AiPanel extends StatefulWidget {
  final String endpoint;
  final String label;
  final String description;
  final IconData icon;
  final Map<String, dynamic>? body;
  final String downloadName;
  final bool autoRun;
  const AiPanel({
    super.key,
    required this.endpoint,
    required this.label,
    this.description = '',
    this.icon = Icons.auto_awesome,
    this.body,
    this.downloadName = 'devmate.md',
    this.autoRun = false,
  });

  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<AiPanel> {
  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoRun) _go();
  }

  Future<void> _go({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.post(widget.endpoint, widget.body, refresh ? {'refresh': 'true'} : null);
      if (mounted) setState(() => _result = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final md = _result?['markdown'] as String?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.icon(
          onPressed: _loading ? null : () => _go(refresh: _result != null),
          icon: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(_result == null ? widget.icon : Icons.refresh),
          label: Text(_loading ? 'Working…' : _result == null ? widget.label : 'Regenerate'),
        ),
        if (md != null) ...[
          AiBadge(_result!['ai'] == true),
          IconButton.outlined(tooltip: 'Copy Markdown', icon: const Icon(Icons.copy, size: 18),
              onPressed: () => Clipboard.setData(ClipboardData(text: md))),
          IconButton.outlined(tooltip: 'Download', icon: const Icon(Icons.download, size: 18),
              onPressed: () => saveText(context, widget.downloadName, md)),
        ],
      ]),
      if (_result == null && !_loading && widget.description.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(widget.description, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      if (_loading)
        const Padding(padding: EdgeInsets.only(top: 20), child: LinearProgressIndicator()),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      if (md != null) ...[const SizedBox(height: 20), MarkdownView(md)],
    ]);
  }
}

/// FutureBuilder with loading / error states.
class Loader<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(T data) builder;
  const Loader({super.key, required this.future, required this.builder});

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (ctx, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return builder(snap.data as T);
        },
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle = ''});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary.withValues(alpha: .5)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ]),
        ),
      );
}
