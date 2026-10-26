import { Link } from "react-router-dom"
import { ArrowRight, ScrollText, Sparkles } from "lucide-react"
import { Bar, BarChart, Cell, Line, LineChart, Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts"

import { ErrorNote, Loading, PageHeader, ScoreRing, Section, SeverityBadge, Stat, useApi } from "@/components/devmate"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { api, type Analysis } from "@/lib/api"
import { useProject } from "@/pages/ProjectLayout"

const SEV = { high: "var(--sev-high)", medium: "var(--sev-medium)", low: "var(--sev-low)" }
const LANG = ["#111", "#555", "#888", "#aaa", "#ccc", "#ddd"]

function verdict(s: number) {
  if (s >= 85) return "Excellent: clean, secure and maintainable."
  if (s >= 70) return "Good overall, with a few issues worth fixing."
  if (s >= 55) return "Fair. Several issues need attention, especially high-severity ones."
  return "Needs work. Fix the security and high-severity findings first."
}

export default function Dashboard() {
  const { pid } = useProject()
  const { data, error } = useApi(
    () => Promise.all([api.get(`/projects/${pid}/structure`), api.get<Analysis>(`/projects/${pid}/analysis`), api.get(`/projects/${pid}/dependencies`), api.get(`/projects/${pid}/history`)]),
    [pid],
  )
  if (error) return <ErrorNote error={error} />
  if (!data) return <Loading rows={4} />
  const [structure, a, deps, history] = data as [any, Analysis, any, any[]]
  const s = structure.summary
  const sevData = (["high", "medium", "low"] as const).map((k) => ({ name: k, value: a.counts[k] })).filter((d) => d.value)
  const total = a.counts.high + a.counts.medium + a.counts.low
  const langs = Object.entries(s.languages as Record<string, number>).sort((x, y) => y[1] - x[1])
  const langTotal = langs.reduce((t, [, v]) => t + v, 0) || 1

  return (
    <div className="space-y-6">
      <PageHeader title="Dashboard" description={verdict(a.health_score)} />

      <Card className="flex-col items-center gap-8 p-8 shadow-none sm:flex-row">
        <ScoreRing score={a.health_score} grade={a.grade} size={150} />
        <div className="flex-1 space-y-4">
          <div>
            <div className="text-muted-foreground text-xs font-medium tracking-wide uppercase">Project health</div>
            <div className="mt-1 text-3xl font-semibold tracking-tight">{a.health_score} / 100</div>
          </div>
          <div className="flex flex-wrap gap-2">
            <Badge variant="secondary">Code score {a.code_score ?? a.health_score}</Badge>
            {deps.vulnerable > 0 && (
              <Badge variant="outline" className="text-sev-high border-sev-high/30">
                −{(a.code_score ?? a.health_score) - a.health_score} vulnerable dependencies
              </Badge>
            )}
            <Badge variant="outline">{a.tools.join(" · ")}</Badge>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button asChild><Link to={`/p/${pid}/review`}><Sparkles /> AI review</Link></Button>
            <Button variant="outline" asChild><Link to={`/p/${pid}/report`}><ScrollText /> Health report</Link></Button>
          </div>
        </div>
      </Card>

      <div className="grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-6">
        <Stat label="Files" value={s.files} />
        <Stat label="Lines" value={s.lines.toLocaleString()} />
        <Stat label="Functions" value={s.functions} hint={`${s.classes} classes`} />
        <Stat label="Security" value={a.by_category.security} tone={a.by_category.security ? "bad" : "good"} />
        <Stat label="Vuln. packages" value={deps.vulnerable} hint={`${deps.total_vulns} CVEs`} tone={deps.vulnerable ? "bad" : "good"} />
        <Stat label="Duplication" value={`${a.duplication?.percentage ?? 0}%`} tone={(a.duplication?.percentage ?? 0) > 5 ? "warn" : "good"} />
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Section title="Issues by severity">
          {total === 0 ? (
            <p className="text-muted-foreground py-10 text-center text-sm">No issues found</p>
          ) : (
            <div className="flex items-center gap-6">
              <div className="relative size-36">
                <ResponsiveContainer>
                  <PieChart>
                    <Pie data={sevData} dataKey="value" innerRadius={46} outerRadius={66} paddingAngle={3} strokeWidth={0}>
                      {sevData.map((d) => <Cell key={d.name} fill={SEV[d.name as keyof typeof SEV]} />)}
                    </Pie>
                  </PieChart>
                </ResponsiveContainer>
                <div className="absolute inset-0 grid place-items-center text-center">
                  <div><div className="text-2xl font-semibold">{total}</div><div className="text-muted-foreground text-xs">issues</div></div>
                </div>
              </div>
              <div className="flex-1 space-y-2 text-sm">
                {(["high", "medium", "low"] as const).map((k) => (
                  <div key={k} className="flex items-center gap-2">
                    <span className="size-2.5 rounded-full" style={{ background: SEV[k] }} />
                    <span className="flex-1 capitalize">{k}</span>
                    <span className="font-medium tabular-nums">{a.counts[k]}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </Section>

        <Section title="Issues by category">
          <div className="h-36">
            <ResponsiveContainer>
              <BarChart data={[{ n: "Security", v: a.by_category.security }, { n: "Bugs", v: a.by_category.bug }, { n: "Smells", v: a.by_category.smell }]}>
                <XAxis dataKey="n" tickLine={false} axisLine={false} fontSize={12} />
                <YAxis hide allowDecimals={false} />
                <Tooltip cursor={{ fill: "var(--muted)" }} contentStyle={{ borderRadius: 8, border: "1px solid var(--border)", background: "var(--popover)" }} />
                <Bar dataKey="v" name="Issues" radius={[6, 6, 0, 0]} fill="var(--foreground)" />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </Section>

        <Section title="Languages">
          <div className="flex h-2 overflow-hidden rounded-full">
            {langs.map(([l, v], i) => <div key={l} style={{ width: `${(v / langTotal) * 100}%`, background: LANG[i % LANG.length] }} />)}
          </div>
          <div className="mt-4 space-y-2 text-sm">
            {langs.map(([l, v], i) => (
              <div key={l} className="flex items-center gap-2">
                <span className="size-2.5 rounded-full" style={{ background: LANG[i % LANG.length] }} />
                <span className="flex-1">{l}</span>
                <span className="text-muted-foreground tabular-nums">{((v / langTotal) * 100).toFixed(1)}%</span>
              </div>
            ))}
          </div>
        </Section>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Section
          title="Top findings"
          actions={<Button variant="ghost" size="sm" asChild><Link to={`/p/${pid}/findings`}>All <ArrowRight /></Link></Button>}
        >
          <div className="divide-y">
            {a.findings.slice(0, 6).map((f, i) => (
              <div key={i} className="flex items-center gap-3 py-2.5">
                <SeverityBadge severity={f.severity} />
                <div className="min-w-0 flex-1">
                  <div className="truncate text-sm font-medium">{f.rule}</div>
                  <div className="text-muted-foreground truncate font-mono text-xs">{f.file}:{f.line}</div>
                </div>
              </div>
            ))}
            {a.findings.length === 0 && <p className="text-muted-foreground text-sm">No issues found.</p>}
          </div>
        </Section>

        <Section title="Most complex functions">
          <div className="space-y-3">
            {a.complex_functions.slice(0, 6).map((f) => {
              const max = Math.max(10, a.complex_functions[0]?.complexity ?? 10)
              const c = f.complexity > 20 ? "var(--sev-high)" : f.complexity > 10 ? "var(--sev-medium)" : "var(--good)"
              return (
                <div key={f.file + f.line}>
                  <div className="flex justify-between text-sm">
                    <span className="truncate font-medium">{f.function}</span>
                    <span className="font-semibold tabular-nums" style={{ color: c }}>{f.complexity}</span>
                  </div>
                  <div className="bg-muted mt-1 h-1.5 overflow-hidden rounded-full">
                    <div className="h-full rounded-full" style={{ width: `${(f.complexity / max) * 100}%`, background: c }} />
                  </div>
                  <div className="text-muted-foreground mt-0.5 font-mono text-[11px]">{f.file}:{f.line}</div>
                </div>
              )
            })}
          </div>
        </Section>
      </div>

      {history.length > 1 && (
        <Section title="Health trend">
          <div className="h-48">
            <ResponsiveContainer>
              <LineChart data={history.map((h, i) => ({ n: `#${i + 1}`, score: h.score }))}>
                <XAxis dataKey="n" tickLine={false} axisLine={false} fontSize={12} />
                <YAxis domain={[0, 100]} tickLine={false} axisLine={false} fontSize={12} width={30} />
                <Tooltip contentStyle={{ borderRadius: 8, border: "1px solid var(--border)", background: "var(--popover)" }} />
                <Line type="monotone" dataKey="score" stroke="var(--foreground)" strokeWidth={2} dot={{ r: 3 }} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </Section>
      )}
    </div>
  )
}
