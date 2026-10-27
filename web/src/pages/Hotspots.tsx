import { useMemo, useState } from "react"
import { Flame } from "lucide-react"
import { Line, LineChart, ResponsiveContainer, Tooltip, Treemap, XAxis, YAxis } from "recharts"

import { EmptyState, ErrorNote, Loading, PageHeader, Section, Stat, useApi } from "@/components/devmate"
import { Badge } from "@/components/ui/badge"
import { Card } from "@/components/ui/card"
import { api } from "@/lib/api"
import { cn } from "@/lib/utils"
import { useProject } from "@/pages/ProjectLayout"

const riskColor = (r: number) => (r >= 70 ? "var(--sev-high)" : r >= 40 ? "var(--sev-medium)" : r >= 15 ? "oklch(0.8 0.1 130)" : "var(--good)")

function Cell(props: any) {
  const { x, y, width, height, name, risk } = props
  if (width < 2 || height < 2 || risk === undefined) return null
  return (
    <g>
      <rect x={x} y={y} width={width} height={height} rx={4} fill={riskColor(risk)} fillOpacity={0.85} stroke="var(--background)" strokeWidth={2} />
      {width > 70 && height > 26 && (
        <text x={x + 8} y={y + 18} fontSize={12} fill="#fff" fontWeight={600}>
          {String(name).split("/").pop()?.slice(0, Math.floor(width / 7.5))}
        </text>
      )}
      {width > 70 && height > 44 && <text x={x + 8} y={y + 34} fontSize={11} fill="#fff" opacity={0.85}>risk {risk}</text>}
    </g>
  )
}

export default function Hotspots() {
  const { pid } = useProject()
  const { data: d, error } = useApi<any>(() => api.get(`/projects/${pid}/hotspots`), [pid])
  const [sel, setSel] = useState<string | null>(null)
  const files = (d?.files ?? []) as any[]
  const tree = useMemo(() => files.filter((f) => f.loc > 0).map((f) => ({ name: f.file, size: f.loc, risk: f.risk })), [files])

  if (error) return <ErrorNote error={error} />
  if (!d) return <Loading />
  const selected = files.find((f) => f.file === (sel ?? files[0]?.file))
  const trend = selected ? (d.trends[selected.file] ?? []) : []

  return (
    <div className="space-y-6">
      <PageHeader
        title="Hotspots"
        description="Where the next bug is most likely: files that are complex, have issues and change often. Box size = lines of code, colour = risk."
      />
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <Stat label="Maintainability" value={d.avg_mi} hint="0–100, higher is better" tone={d.avg_mi >= 20 ? "good" : d.avg_mi >= 10 ? "warn" : "bad"} />
        <Stat label="Hotspots" value={d.hotspots.length} hint="risk ≥ 50" tone={d.hotspots.length ? "warn" : "good"} />
        <Stat label="Files" value={files.length} />
        <Stat label="Change history" value={d.has_churn ? "git" : "none"} hint={d.has_churn ? "last 300 commits" : "import from GitHub for churn"} />
      </div>

      {tree.length === 0 ? <EmptyState icon={<Flame className="size-8" />} title="No source files" /> : (
        <Section title="Risk map">
          <div className="h-80">
            <ResponsiveContainer>
              <Treemap data={tree} dataKey="size" isAnimationActive={false} content={<Cell />} onClick={(n: any) => n?.name && setSel(n.name)}>
                <Tooltip content={({ payload }) => {
                  const p = payload?.[0]?.payload
                  return p ? <Card className="gap-1 p-3 text-xs shadow-md"><div className="font-mono font-medium">{p.name}</div><div>{p.size} lines · risk {p.risk}</div></Card> : null
                }} />
              </Treemap>
            </ResponsiveContainer>
          </div>
        </Section>
      )}

      <div className="grid gap-4 xl:grid-cols-[1fr_380px]">
        <Section title="Files by risk">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="text-muted-foreground text-left text-xs">
                <tr><th className="py-2 pr-3 font-medium">File</th><th className="px-2 font-medium">Risk</th><th className="px-2 font-medium">Maint.</th><th className="px-2 font-medium">CC max</th><th className="px-2 font-medium">Issues</th><th className="px-2 font-medium">Commits</th></tr>
              </thead>
              <tbody className="divide-y">
                {files.slice(0, 40).map((f) => (
                  <tr key={f.file} onClick={() => setSel(f.file)} className={cn("hover:bg-muted/50 cursor-pointer", selected?.file === f.file && "bg-muted")}>
                    <td className="max-w-72 truncate py-2 pr-3 font-mono text-xs">{f.file}</td>
                    <td className="px-2">
                      <div className="flex items-center gap-2">
                        <div className="bg-muted h-1.5 w-14 overflow-hidden rounded-full"><div className="h-full rounded-full" style={{ width: `${f.risk}%`, background: riskColor(f.risk) }} /></div>
                        <span className="tabular-nums">{f.risk}</span>
                      </div>
                    </td>
                    <td className="px-2"><Badge variant="outline" className={cn(f.mi_band === "poor" && "text-sev-high", f.mi_band === "moderate" && "text-sev-medium")}>{f.mi}</Badge></td>
                    <td className="px-2 tabular-nums">{f.cc_max}</td>
                    <td className="px-2 tabular-nums">{f.issues.high + f.issues.medium + f.issues.low}</td>
                    <td className="px-2 tabular-nums">{f.churn || "–"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Section>

        {selected && (
          <Section title="File detail">
            <div className="space-y-4">
              <div className="font-mono text-xs break-all">{selected.file}</div>
              <div className="grid grid-cols-2 gap-2 text-sm">
                <div><div className="text-muted-foreground text-xs">Lines</div>{selected.loc}</div>
                <div><div className="text-muted-foreground text-xs">Functions</div>{selected.functions}</div>
                <div><div className="text-muted-foreground text-xs">Total complexity</div>{selected.cc_total}</div>
                <div><div className="text-muted-foreground text-xs">Comments</div>{Math.round(selected.comment_ratio * 100)}%</div>
              </div>
              <div>
                <div className="text-muted-foreground mb-1 text-xs">Quality trend across analyses</div>
                {trend.length > 1 ? (
                  <div className="h-36">
                    <ResponsiveContainer>
                      <LineChart data={trend.map((t: any, i: number) => ({ n: `#${i + 1}`, risk: t.risk, maint: t.mi }))}>
                        <XAxis dataKey="n" fontSize={11} tickLine={false} axisLine={false} />
                        <YAxis domain={[0, 100]} fontSize={11} width={26} tickLine={false} axisLine={false} />
                        <Tooltip contentStyle={{ borderRadius: 8, border: "1px solid var(--border)", background: "var(--popover)" }} />
                        <Line dataKey="risk" stroke="var(--sev-high)" strokeWidth={2} dot={false} />
                        <Line dataKey="maint" stroke="var(--good)" strokeWidth={2} dot={false} />
                      </LineChart>
                    </ResponsiveContainer>
                  </div>
                ) : <p className="text-muted-foreground text-xs">Re-analyze after changes to see this file's trend.</p>}
              </div>
            </div>
          </Section>
        )}
      </div>
    </div>
  )
}
