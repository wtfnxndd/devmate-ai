import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Vulnerable & outdated components (OWASP A06) via the free OSV.dev database.
class DependenciesTab extends StatelessWidget {
  final int pid;
  const DependenciesTab({super.key, required this.pid});

  @override
  Widget build(BuildContext context) {
    return Loader(
      future: Api.get('/projects/$pid/dependencies'),
      builder: (d) {
        final deps = (d['dependencies'] as List);
        final wide = MediaQuery.sizeOf(context).width > 900;
        if (deps.isEmpty) {
          return const EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No pinned dependencies found',
            subtitle: 'Supported: requirements*.txt, pyproject.toml, package.json, pubspec.yaml, go.mod',
          );
        }
        return ListView(padding: EdgeInsets.all(wide ? 28 : 16), children: [
          Wrap(spacing: 16, runSpacing: 16, children: [
            SizedBox(width: 260, child: StatCard(icon: Icons.inventory_2_outlined, label: 'Dependencies', value: '${deps.length}')),
            SizedBox(
              width: 260,
              child: StatCard(icon: Icons.gpp_bad_outlined, label: 'Vulnerable packages', value: '${d['vulnerable']}',
                  color: d['vulnerable'] > 0 ? Brand.high : Brand.good),
            ),
            SizedBox(width: 260, child: StatCard(icon: Icons.bug_report_outlined, label: 'Known vulnerabilities', value: '${d['total_vulns']}', color: Brand.medium)),
          ]),
          if (d['online'] == false)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Card(child: ListTile(leading: const Icon(Icons.cloud_off), title: Text('OSV.dev unreachable: ${d['error']}'))),
            ),
          const SizedBox(height: 20),
          Text('Source: OSV.dev open vulnerability database · OWASP A06 Vulnerable & Outdated Components',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          for (final dep in deps) Padding(padding: const EdgeInsets.only(bottom: 10), child: _DepCard(dep)),
        ]);
      },
    );
  }
}

class _DepCard extends StatelessWidget {
  final dynamic dep;
  const _DepCard(this.dep);

  @override
  Widget build(BuildContext context) {
    final vulns = (dep['vulns'] as List?) ?? [];
    final worst = dep['worst'];
    final header = Row(children: [
      Icon(vulns.isEmpty ? Icons.verified_outlined : Icons.gpp_bad_outlined, color: vulns.isEmpty ? Brand.good : Brand.severity(worst)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${dep['name']}  ${dep['version']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          Text('${dep['ecosystem']} · ${dep['manifest']}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ),
      if (vulns.isNotEmpty) ...[
        SeverityBadge(worst ?? 'medium'),
        const SizedBox(width: 8),
        Text('${vulns.length} CVE${vulns.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w700)),
      ] else
        const Text('No known issues', style: TextStyle(color: Brand.good)),
    ]);
    if (vulns.isEmpty) return Card(child: Padding(padding: const EdgeInsets.all(16), child: header));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: header,
        subtitle: dep['upgrade_to'] == null ? null : Padding(
          padding: const EdgeInsets.only(left: 36, top: 4),
          child: Text('Upgrade to ≥ ${dep['upgrade_to']}', style: const TextStyle(color: Brand.good, fontWeight: FontWeight.w600)),
        ),
        children: [
          for (final v in vulns)
            ListTile(
              dense: true,
              leading: SeverityBadge(v['severity'] ?? 'medium'),
              title: Text(v['summary'] ?? v['id'], maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text([...(v['aliases'] as List? ?? []), v['id'],
                if ((v['fixed_in'] as List? ?? []).isNotEmpty) 'fixed in ${(v['fixed_in'] as List).join(', ')}'].join(' · ')),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: v['url'] == null ? null : () => launchUrl(Uri.parse(v['url'])),
            ),
        ],
      ),
    );
  }
}
