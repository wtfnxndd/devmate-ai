import { useState } from "react"
import { CheckCircle2, PlusCircle, Trophy } from "lucide-react"

import { EmptyState, ErrorNote, Loading, PageHeader, Section, SeverityBadge, Stat, useApi } from "@/components/devmate"
import { Card } from "@/components/ui/card"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { api, type ProjectSummary } from "@/lib/api"
import { cn } from "@/lib/utils"
import { useProject } from "@/pages/ProjectLayout"

export default function Compare() {
  return (
    <div>
      <PageHeader title="Compare" description="Track progress between analyses, or compare two projects side by side." />
      <Tabs defaultValue="history">
        <TabsList><TabsTrigger value="history">Analysis history</TabsTrigger><TabsTrigger value="projects">Compare projects</TabsTrigger></TabsList>
        <TabsContent value="history" className="pt-5"><History /></TabsContent>
        <TabsContent value="projects" className="pt-5"><Projects /></TabsContent>
      </Tabs>
    </div>
  )
}

function History() {
  const { pid } = useProject()
  const [a, setA] = useState(-2)
  const [b, setB] = useState(-1)
  const { data: d, error } = useApi<any>(() => api.get(`/projects/${pid}/compare`, { a, b }), [pid, a, b])
  if (error) return <EmptyState title="Nothing to compare yet" description={error} />
  if (!d) return <Loading />
  const hist = d.history as any[]
  const idx = (v: number) => String(v < 0 ? hist.length + v : v)
  const label = (h: any, i: number) => `#${i + 1} · ${String(h.at).replace("T", " ").slice(0, 16)} · score ${h.score}`
  const delta = d.to.score - d.from.score
  const pick = (v: number, set: (n: number) => void, title: string) => (
    <div className="space-y-1">
      <div className="text-muted-foreground text-xs">{title}</div>
      <Select value={idx(v)} onValueChange={(s) => set(Number(s))}>
        <SelectTrigger className="w-80"><SelectValue /></SelectTrigger>
        <SelectContent>{hist.map((h, i) => <SelectItem key={i} value={String(i)}>{label(h, i)}</SelectItem>)}</SelectContent>
      </Select>
    </div>
  )
  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end gap-4">{pick(a, setA, "From")}<span className="text-muted-foreground pb-2">→</span>{pick(b, setB, "To")}</div>
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <Stat label="Health score" value={`${d.from.score} → ${d.to.score}`} hint={`${delta >= 0 ? "+" : ""}${delta} points`} tone={delta >= 0 ? "good" : "bad"} />
        <Stat label="Issues fixed" value={d.fixed.length} tone="good" />
        <Stat label="New issues" value={d.new.length} tone={d.new.length ? "bad" : undefined} />
        <Stat label="Unchanged" value={d.unchanged} />
      </div>
      {!d.comparable && <p className="text-muted-foreground text-sm">One of these analyses predates issue tracking, so only totals can be compared.</p>}
      <div className="grid gap-4 lg:grid-cols-2">
        <IssueList title="Fixed" items={d.fixed} icon={<CheckCircle2 className="text-good size-4" />} />
        <IssueList title="New" items={d.new} icon={<PlusCircle className="text-sev-high size-4" />} />
      </div>
    </div>
  )
}

function IssueList({ title, items, icon }: { title: string; items: any[]; icon: React.ReactNode }) {
  return (
    <Section title={`${title} (${items.length})`} icon={icon}>
      {items.length === 0 ? <p className="text-muted-foreground text-sm">None</p> : (
        <div className="divide-y">
          {items.slice(0, 60).map((f, i) => (
            <div key={i} className="flex items-center gap-3 py-2">
              <div className="min-w-0 flex-1">
                <div className="truncate text-sm font-medium">{f.rule}</div>
                <div className="text-muted-foreground truncate text-xs">{f.file} · {f.message}</div>
              </div>
              <SeverityBadge severity={f.severity} />
            </div>
          ))}
        </div>
      )}
    </Section>
  )
}

function Projects() {
  const { pid } = useProject()
  const { data: all } = useApi<ProjectSummary[]>(() => api.get("/projects"), [])
  const [other, setOther] = useState<string>()
  const { data: rows, error } = useApi<any[]>(
    () => (other ? api.get("/compare-projects", { a: pid, b: other }) : Promise.resolve([])),
    [pid, other],
  )
  const others = (all ?? []).filter((p) => p.id !== pid && p.status === "ready")
  if (all && !others.length) return <EmptyState title="No other project to compare" description="Import another project first." />

  return (
    <div className="space-y-6">
      <Select value={other} onValueChange={setOther}>
        <SelectTrigger className="w-80"><SelectValue placeholder="Compare with…" /></SelectTrigger>
        <SelectContent>{others.map((p) => <SelectItem key={p.id} value={String(p.id)}>{p.name} (#{p.id})</SelectItem>)}</SelectContent>
      </Select>
      {error && <ErrorNote error={error} />}
      {rows?.length === 2 && <SideBySide a={rows[0]} b={rows[1]} />}
    </div>
  )
}

function SideBySide({ a, b }: { a: any; b: any }) {
  const metrics: [string, number | null, number | null, boolean][] = [
    ["Health score", a.score, b.score, true],
    ["Files", a.files, b.files, true],
    ["Lines of code", a.lines, b.lines, true],
    ["Functions", a.functions, b.functions, true],
    ["High-severity issues", a.counts?.high, b.counts?.high, false],
    ["Medium-severity issues", a.counts?.medium, b.counts?.medium, false],
    ["Security issues", a.by_category?.security, b.by_category?.security, false],
    ["Avg complexity", a.avg_complexity, b.avg_complexity, false],
    ["Duplication %", a.duplication, b.duplication, false],
    ["Vulnerable packages", a.vulnerable_deps, b.vulnerable_deps, false],
  ]
  const cell = (v: number | null, o: number | null, hib: boolean) => {
    const win = v != null && o != null && v !== o && v > o === hib
    return (
      <td className={cn("px-4 py-3 tabular-nums", win && "text-good font-semibold")}>
        <span className="inline-flex items-center gap-1.5">{v ?? "–"}{win && <Trophy className="size-3.5" />}</span>
      </td>
    )
  }
  return (
    <Card className="overflow-hidden p-0 shadow-none">
      <table className="w-full text-sm">
        <thead className="bg-muted/50 text-left">
          <tr><th className="px-4 py-3 font-medium">Metric</th><th className="px-4 py-3 font-medium">{a.name}</th><th className="px-4 py-3 font-medium">{b.name}</th></tr>
        </thead>
        <tbody className="divide-y">
          {metrics.map(([l, x, y, hib]) => <tr key={l}><td className="text-muted-foreground px-4 py-3">{l}</td>{cell(x, y, hib)}{cell(y, x, hib)}</tr>)}
        </tbody>
      </table>
    </Card>
  )
}
