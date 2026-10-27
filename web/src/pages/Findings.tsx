import { useMemo, useState } from "react"
import { Link } from "react-router-dom"
import { Bug, Check, Loader2, Search, ShieldAlert, Sparkles, SprayCan, Wand2 } from "lucide-react"
import { toast } from "sonner"

import {
  CodeView, CopyButton, DiffView, EmptyState, ErrorNote, languageFor, Loading, Markdown, PageHeader, ProviderBadge, SeverityBadge, useApi,
} from "@/components/devmate"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { ShimmeringText } from "@/components/ui/shimmering-text"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { api, streamAi, type Analysis, type Finding } from "@/lib/api"
import { cn } from "@/lib/utils"
import { useProject } from "@/pages/ProjectLayout"

const CAT_ICON = { security: ShieldAlert, bug: Bug, smell: SprayCan }

export default function Findings() {
  const { pid } = useProject()
  const { data: a, error } = useApi(() => api.get<Analysis>(`/projects/${pid}/analysis`), [pid])
  const [sev, setSev] = useState<string[]>(["high", "medium", "low"])
  const [cat, setCat] = useState<string[]>(["security", "bug", "smell"])
  const [q, setQ] = useState("")
  const [selected, setSelected] = useState<Finding | null>(null)

  const list = useMemo(
    () =>
      (a?.findings ?? []).filter(
        (f) => sev.includes(f.severity) && cat.includes(f.category) && `${f.file} ${f.rule} ${f.message}`.toLowerCase().includes(q.toLowerCase()),
      ),
    [a, sev, cat, q],
  )

  if (error) return <ErrorNote error={error} />
  if (!a) return <Loading />
  const count = (k: keyof Finding, v: string) => a.findings.filter((f) => f[k] === v).length

  return (
    <div>
      <PageHeader title="Findings" description={`${a.findings.length} issues from ${a.tools.join(", ")}. Select one to see the code and get an AI fix.`} />
      <div className="mb-5 flex flex-wrap items-center gap-3">
        <div className="relative min-w-60 flex-1">
          <Search className="text-muted-foreground absolute top-2.5 left-3 size-4" />
          <Input className="pl-9" placeholder="Search file, rule or message…" value={q} onChange={(e) => setQ(e.target.value)} />
        </div>
        <ToggleGroup type="multiple" variant="outline" value={sev} onValueChange={setSev}>
          {(["high", "medium", "low"] as const).map((s) => (
            <ToggleGroupItem key={s} value={s} className="px-3 capitalize">{s} {count("severity", s)}</ToggleGroupItem>
          ))}
        </ToggleGroup>
        <ToggleGroup type="multiple" variant="outline" value={cat} onValueChange={setCat}>
          {(["security", "bug", "smell"] as const).map((c) => (
            <ToggleGroupItem key={c} value={c} className="px-3 capitalize">{c} {count("category", c)}</ToggleGroupItem>
          ))}
        </ToggleGroup>
      </div>

      <div className="grid gap-5 xl:grid-cols-[minmax(0,420px)_1fr]">
        <div className="space-y-2">
          {list.length === 0 && <EmptyState title="No matching findings" />}
          {list.map((f, i) => {
            const Icon = CAT_ICON[f.category] ?? Bug
            return (
              <button
                key={i}
                onClick={() => setSelected(f)}
                className={cn(
                  "bg-card hover:border-foreground/30 w-full rounded-xl border p-4 text-left transition-colors",
                  selected === f && "border-foreground ring-foreground/10 ring-2",
                )}
              >
                <div className="flex items-center gap-2">
                  <Icon className="text-muted-foreground size-4" />
                  <SeverityBadge severity={f.severity} />
                  <span className="truncate text-sm font-medium">{f.rule}</span>
                </div>
                <p className="mt-2 line-clamp-2 text-sm">{f.message}</p>
                <p className="text-muted-foreground mt-2 font-mono text-xs">{f.file}:{f.line} · {f.tool}</p>
              </button>
            )
          })}
        </div>
        <div className="xl:sticky xl:top-20 xl:self-start">
          {selected ? <FindingDetail key={`${selected.file}:${selected.line}:${selected.rule}`} pid={pid} f={selected} /> : (
            <EmptyState icon={<Sparkles className="size-8" />} title="Select a finding" description="See the code around it and generate a fix with AI." />
          )}
        </div>
      </div>
    </div>
  )
}

function FindingDetail({ pid, f }: { pid: number; f: Finding }) {
  const { data: code } = useApi(() => api.text(`/projects/${pid}/file`, { path: f.file }), [f.file])
  const [fix, setFix] = useState<any>(null)
  const [busy, setBusy] = useState(false)
  const [applied, setApplied] = useState(false)
  const [live, setLive] = useState("")
  const [provider, setProvider] = useState<string | null>(null)

  const lines = code?.split("\n") ?? []
  const lo = Math.max(1, f.line - 10), hi = Math.min(lines.length, f.line + 10)

  const getFix = async () => {
    setBusy(true)
    setApplied(false)
    try {
      setLive("")
      setProvider(null)
      setFix(await streamAi(pid, "fix", { file: f.file, line: f.line, rule: f.rule, message: f.message }, { onText: setLive, onProvider: setProvider }))
    } catch (e) {
      toast.error((e as Error).message)
    } finally {
      setBusy(false)
    }
  }

  const apply = async () => {
    try {
      await api.post(`/projects/${pid}/fix/apply`, { file: fix.file, start: fix.start, original: fix.original, fixed: fix.fixed })
      setApplied(true)
      toast.success("Fix applied to the project", { action: { label: "Review", onClick: () => (location.href = `/p/${pid}/fix`) } })
    } catch (e) {
      toast.error((e as Error).message)
    }
  }

  return (
    <Card className="gap-5 p-6 shadow-none">
      <div>
        <div className="flex items-center gap-2">
          <SeverityBadge severity={f.severity} />
          <Badge variant="secondary" className="capitalize">{f.category}</Badge>
        </div>
        <h2 className="mt-3 text-lg font-semibold">{f.rule}</h2>
        <p className="mt-1 text-sm">{f.message}</p>
        <p className="text-muted-foreground mt-2 font-mono text-xs">{f.file}:{f.line} · {f.tool}{f.owasp && !f.owasp.startsWith("http") ? ` · ${f.owasp}` : ""}</p>
      </div>
      {code == null ? <Loading rows={1} /> : (
        <CodeView code={lines.slice(lo - 1, hi).join("\n")} lang={languageFor(f.file)} start={lo} highlight={f.line} />
      )}
      <div className="flex flex-wrap gap-2">
        <Button onClick={getFix} disabled={busy}>
          {busy ? <Loader2 className="animate-spin" /> : <Wand2 />} {fix ? "Regenerate fix" : "Fix with AI"}
        </Button>
        {fix?.fixed && (
          <>
            <Button variant="outline" onClick={apply} disabled={applied}>
              {applied ? <Check /> : <Sparkles />} {applied ? "Applied" : "Apply to project"}
            </Button>
            <CopyButton text={fix.fixed} label="Copy fixed code" />
          </>
        )}
        {applied && <Button variant="ghost" asChild><Link to={`/p/${pid}/fix`}>Review changes →</Link></Button>}
      </div>
      <ProviderBadge provider={provider} />
      {busy && !live && <ShimmeringText text="Writing a fix…" className="text-sm" />}
      {busy && live && <Markdown>{live}</Markdown>}
      {fix && !busy && (
        <div className="space-y-4">
          {fix.fixed && <DiffView original={fix.original} fixed={fix.fixed} />}
          <Markdown>{fix.explanation ?? ""}</Markdown>
        </div>
      )}
    </Card>
  )
}
