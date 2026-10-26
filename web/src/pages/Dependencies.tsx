import { ExternalLink, PackageCheck, PackageX } from "lucide-react"

import { EmptyState, ErrorNote, Loading, PageHeader, SeverityBadge, Stat, useApi } from "@/components/devmate"
import { Badge } from "@/components/ui/badge"
import { Card } from "@/components/ui/card"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { api } from "@/lib/api"
import { useProject } from "@/pages/ProjectLayout"

export default function Dependencies() {
  const { pid } = useProject()
  const { data: d, error } = useApi<any>(() => api.get(`/projects/${pid}/dependencies`), [pid])
  if (error) return <ErrorNote error={error} />
  if (!d) return <Loading />
  const deps = d.dependencies as any[]

  return (
    <div>
      <PageHeader title="Dependencies" description="Every pinned package checked against the free OSV.dev vulnerability database (OWASP A06: vulnerable and outdated components)." />
      {deps.length === 0 ? (
        <EmptyState icon={<PackageCheck className="size-8" />} title="No pinned dependencies found" description="Supported: requirements*.txt, pyproject.toml, package.json, pubspec.yaml, go.mod" />
      ) : (
        <div className="space-y-6">
          <div className="grid grid-cols-3 gap-4">
            <Stat label="Dependencies" value={deps.length} />
            <Stat label="Vulnerable" value={d.vulnerable} tone={d.vulnerable ? "bad" : "good"} />
            <Stat label="Known CVEs" value={d.total_vulns} tone={d.total_vulns ? "warn" : "good"} />
          </div>
          {d.online === false && <ErrorNote error={`OSV.dev unreachable: ${d.error}`} />}
          <div className="space-y-2">
            {deps.map((dep) => {
              const vulns = (dep.vulns ?? []) as any[]
              const head = (
                <div className="flex w-full items-center gap-3 text-left">
                  {vulns.length ? <PackageX className="text-sev-high size-5" /> : <PackageCheck className="text-good size-5" />}
                  <div className="min-w-0 flex-1">
                    <div className="font-medium">{dep.name} <span className="text-muted-foreground font-mono text-sm">{dep.version}</span></div>
                    <div className="text-muted-foreground text-xs">{dep.ecosystem} · {dep.manifest}</div>
                  </div>
                  {vulns.length ? (
                    <>
                      {dep.upgrade_to && <Badge variant="outline" className="text-good border-good/30 hidden sm:inline-flex">Upgrade to ≥ {dep.upgrade_to}</Badge>}
                      <SeverityBadge severity={dep.worst ?? "medium"} />
                      <span className="text-sm font-medium tabular-nums">{vulns.length} CVE{vulns.length > 1 ? "s" : ""}</span>
                    </>
                  ) : (
                    <span className="text-muted-foreground text-sm">No known issues</span>
                  )}
                </div>
              )
              return (
                <Card key={dep.ecosystem + dep.name + dep.version} className="gap-0 p-0 shadow-none">
                  {vulns.length === 0 ? <div className="p-4">{head}</div> : (
                    <Collapsible>
                      <CollapsibleTrigger className="hover:bg-muted/50 w-full rounded-xl p-4">{head}</CollapsibleTrigger>
                      <CollapsibleContent className="divide-y border-t">
                        {vulns.map((v) => (
                          <a key={v.id} href={v.url} target="_blank" rel="noreferrer" className="hover:bg-muted/50 flex items-start gap-3 px-4 py-3">
                            <SeverityBadge severity={v.severity ?? "medium"} />
                            <div className="min-w-0 flex-1">
                              <div className="text-sm">{v.summary || v.id}</div>
                              <div className="text-muted-foreground mt-0.5 font-mono text-xs">
                                {[...(v.aliases ?? []), v.id].join(" · ")}{v.fixed_in?.length ? ` · fixed in ${v.fixed_in.join(", ")}` : ""}
                              </div>
                            </div>
                            <ExternalLink className="text-muted-foreground size-4" />
                          </a>
                        ))}
                      </CollapsibleContent>
                    </Collapsible>
                  )}
                </Card>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}
