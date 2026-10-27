import { useState } from "react"
import { Link } from "react-router-dom"
import { ArrowLeft, Check, Cloud, Cpu, Download, HardDrive, Loader2, Lock, RefreshCw, Shuffle, Trash2 } from "lucide-react"
import { toast } from "sonner"

import { Logo, ThemeToggle } from "@/components/chrome"
import { ErrorNote, Loading, useApi } from "@/components/devmate"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Progress } from "@/components/ui/progress"
import { api, readSSE } from "@/lib/api"
import { cn } from "@/lib/utils"

const MODES = [
  { id: "local", title: "Local only", icon: Lock, text: "Private: your code never leaves your computer. Uses Ollama only." },
  { id: "local-first", title: "Local first", icon: Cpu, text: "Uses your local model; falls back to free cloud AI if Ollama is off." },
  { id: "cloud-first", title: "Cloud first", icon: Cloud, text: "Fastest answers from Groq / Gemini; local model as backup." },
]

const gb = (bytes: number) => `${(bytes / 1e9).toFixed(1)} GB`

export default function AiSettings() {
  const { data: s, error, reload, setData } = useApi<any>(() => api.get("/ai/status"), [])
  const [pulling, setPulling] = useState<Record<string, { pct: number; status: string }>>({})

  const save = async (patch: { mode?: string; local_model?: string }) => {
    try {
      setData(await api.put("/ai/settings", patch))
      toast.success("AI settings saved")
    } catch (e) {
      toast.error((e as Error).message)
    }
  }

  const pull = async (name: string) => {
    setPulling((p) => ({ ...p, [name]: { pct: 0, status: "starting" } }))
    try {
      await readSSE("/ai/models/pull", { name }, (e: any) => {
        if (e.error) throw new Error(e.error)
        const pct = e.total ? Math.round((100 * (e.completed ?? 0)) / e.total) : 0
        setPulling((p) => ({ ...p, [name]: { pct, status: e.status ?? "" } }))
      })
      toast.success(`${name} is ready`)
      await save({ local_model: name })
    } catch (e) {
      toast.error(`Download failed: ${(e as Error).message}`)
    } finally {
      setPulling((p) => {
        const { [name]: _, ...rest } = p
        return rest
      })
      reload()
    }
  }

  const remove = async (name: string) => {
    await api.del(`/ai/models/${encodeURIComponent(name)}`)
    toast.success(`Removed ${name}`)
    reload()
  }

  return (
    <div className="min-h-screen">
      <header className="mx-auto flex max-w-4xl items-center justify-between px-6 py-5">
        <Link to="/"><Logo /></Link>
        <ThemeToggle />
      </header>
      <main className="mx-auto max-w-4xl space-y-8 px-6 pb-24">
        <div>
          <Button variant="ghost" size="sm" asChild className="text-muted-foreground -ml-3"><Link to="/"><ArrowLeft /> Projects</Link></Button>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight">AI settings</h1>
          <p className="text-muted-foreground mt-1 text-sm">Run AI on your own computer with Ollama: free, private and offline-capable.</p>
        </div>
        {error && <ErrorNote error={error} />}
        {!s ? <Loading /> : (
          <>
            <section className="space-y-3">
              <h2 className="text-sm font-medium">Mode</h2>
              <div className="grid gap-3 sm:grid-cols-3">
                {MODES.map((m) => (
                  <button
                    key={m.id}
                    onClick={() => save({ mode: m.id })}
                    className={cn("bg-card hover:border-foreground/40 rounded-xl border p-4 text-left transition-colors", s.mode === m.id && "border-foreground ring-foreground/10 ring-2")}
                  >
                    <div className="flex items-center justify-between">
                      <m.icon className="size-5" />
                      {s.mode === m.id && <Check className="size-4" />}
                    </div>
                    <div className="mt-3 font-medium">{m.title}</div>
                    <p className="text-muted-foreground mt-1 text-xs leading-relaxed">{m.text}</p>
                  </button>
                ))}
              </div>
              <p className="text-muted-foreground text-xs">
                Order now: {s.order.length ? s.order.map((o: string) => o.split(":")[0] === "local" ? `local (${o.split(":").slice(1).join(":")})` : o.split(":")[0]).filter((v: string, i: number, a: string[]) => a.indexOf(v) === i).join(" → ") : "none available"}
              </p>
            </section>

            <Card className="gap-4 p-6 shadow-none">
              <div className="flex items-center gap-3">
                <HardDrive className="size-5" />
                <div className="flex-1">
                  <div className="font-medium">Local AI (Ollama)</div>
                  <div className="text-muted-foreground text-xs">{s.ollama_url}</div>
                </div>
                <Badge variant="outline" className="gap-1.5">
                  <span className={cn("size-1.5 rounded-full", s.ollama_running ? "bg-good" : "bg-sev-high")} />
                  {s.ollama_running ? "Running" : "Not running"}
                </Badge>
                <Button variant="ghost" size="icon" onClick={reload} aria-label="Refresh"><RefreshCw /></Button>
              </div>

              {!s.ollama_running ? (
                <div className="bg-surface space-y-3 rounded-xl border p-5 text-sm">
                  <div className="font-medium">Set up local AI (one time, free)</div>
                  <ol className="text-muted-foreground list-decimal space-y-1.5 pl-5">
                    <li>Download Ollama from <a className="text-foreground underline" href="https://ollama.com/download" target="_blank" rel="noreferrer">ollama.com/download</a> and open it (it runs in the menu bar).</li>
                    <li>Come back here and press refresh. Ollama should show <b>Running</b>.</li>
                    <li>Download a model below. <b>qwen2.5-coder:3b</b> is recommended for laptops.</li>
                  </ol>
                </div>
              ) : (
                <div className="space-y-2">
                  <div className="text-sm font-medium">Installed models</div>
                  {s.installed.length === 0 && <p className="text-muted-foreground text-sm">No models yet. Download one below.</p>}
                  {s.installed.map((m: any) => {
                    const active = s.active_local_model === m.name
                    return (
                      <div key={m.name} className="flex items-center gap-3 rounded-lg border px-3 py-2.5">
                        <Cpu className="text-muted-foreground size-4" />
                        <div className="min-w-0 flex-1">
                          <div className="font-mono text-sm">{m.name}</div>
                          <div className="text-muted-foreground text-xs">{[m.parameters, m.family, gb(m.size)].filter(Boolean).join(" · ")}</div>
                        </div>
                        {active ? <Badge>Default</Badge> : <Button variant="outline" size="sm" onClick={() => save({ local_model: m.name })}>Use</Button>}
                        <Button variant="ghost" size="icon" onClick={() => remove(m.name)} aria-label={`Remove ${m.name}`}><Trash2 /></Button>
                      </div>
                    )
                  })}
                </div>
              )}
            </Card>

            <section className="space-y-3">
              <h2 className="text-sm font-medium">Recommended free models</h2>
              <div className="grid gap-3 sm:grid-cols-2">
                {s.recommended.map((m: any) => {
                  const installed = s.installed.some((i: any) => i.name === m.name || i.name === `${m.name}:latest`)
                  const p = pulling[m.name]
                  return (
                    <Card key={m.name} className="gap-3 p-4 shadow-none">
                      <div className="flex items-start justify-between gap-2">
                        <div>
                          <div className="font-mono text-sm font-medium">{m.name}</div>
                          <div className="text-muted-foreground text-xs">{m.size_gb} GB download</div>
                        </div>
                        {installed ? <Badge variant="secondary"><Check /> Installed</Badge> : (
                          <Button size="sm" variant="outline" disabled={!s.ollama_running || !!p} onClick={() => pull(m.name)}>
                            {p ? <Loader2 className="animate-spin" /> : <Download />} Download
                          </Button>
                        )}
                      </div>
                      <p className="text-muted-foreground text-xs">{m.note}</p>
                      {p && (
                        <div className="space-y-1">
                          <Progress value={p.pct} className="h-1.5" />
                          <div className="text-muted-foreground text-xs">{p.status} {p.pct ? `· ${p.pct}%` : ""}</div>
                        </div>
                      )}
                    </Card>
                  )
                })}
              </div>
            </section>

            <Card className="flex-row items-center gap-3 p-5 shadow-none">
              <Shuffle className="text-muted-foreground size-5" />
              <p className="flex-1 text-sm">
                Cloud fallback: {s.cloud.length ? s.cloud.join(", ") : "none configured"}.
                <span className="text-muted-foreground"> Add GROQ_API_KEY / GEMINI_API_KEY in backend/.env.</span>
              </p>
            </Card>
          </>
        )}
      </main>
    </div>
  )
}
