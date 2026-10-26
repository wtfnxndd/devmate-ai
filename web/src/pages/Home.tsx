import { useEffect, useRef, useState } from "react"
import { Link } from "react-router-dom"
import { ArrowRight, FileArchive, GitBranch, Loader2, MoreHorizontal, RefreshCw, Trash2, WifiOff } from "lucide-react"
import { toast } from "sonner"

import { BackendSettings, Logo, ThemeToggle } from "@/components/chrome"
import { ScoreRing } from "@/components/devmate"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Input } from "@/components/ui/input"
import { Progress } from "@/components/ui/progress"
import { ShimmeringText } from "@/components/ui/shimmering-text"
import { api, ApiError, getConfig, type ProjectSummary } from "@/lib/api"

const STAGES = ["ingested", "queued", "parsing", "analyzing", "scanning dependencies", "indexing", "ready"]

export default function Home() {
  const [projects, setProjects] = useState<ProjectSummary[] | null>(null)
  const [providers, setProviders] = useState<string[]>([])
  const [error, setError] = useState<string | null>(null)
  const [repo, setRepo] = useState("")
  const [busy, setBusy] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  const load = async () => {
    try {
      const h = await api.get("/health")
      setProviders(h.llm_providers)
      setProjects(await api.get("/projects"))
      setError(null)
    } catch (e) {
      setError(e instanceof ApiError && e.status === 401
        ? "This server needs an access token. Open the token link once, or add it in settings."
        : `Can't reach the DevMate backend at ${getConfig().baseUrl}. Start "DevMate Online" on your Mac.`)
    }
  }

  useEffect(() => {
    load()
  }, [])

  // Poll while any project is still being analysed.
  useEffect(() => {
    if (!projects?.some((p) => p.status !== "ready" && !p.status.startsWith("error"))) return
    const t = setTimeout(load, 2000)
    return () => clearTimeout(t)
  }, [projects])

  const run = async (fn: () => Promise<unknown>) => {
    setBusy(true)
    try {
      await fn()
      await load()
    } catch (e) {
      toast.error((e as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="min-h-screen">
      <header className="mx-auto flex max-w-6xl items-center justify-between px-6 py-5">
        <Logo />
        <div className="flex items-center gap-1">
          <Badge variant="outline" className="mr-2 hidden gap-1.5 rounded-full px-3 py-1 sm:inline-flex">
            <span className={`size-1.5 rounded-full ${providers.length ? "bg-good" : "bg-muted-foreground"}`} />
            {providers.length ? `AI · ${providers.join(" + ")}` : "Static mode"}
          </Badge>
          <BackendSettings onSaved={load} />
          <ThemeToggle />
        </div>
      </header>

      <section className="mx-auto max-w-6xl px-6 pt-16 pb-14 text-center">
        <Badge variant="secondary" className="mb-6 rounded-full px-3 py-1 font-normal">
          Free · OWASP scanning · dependency CVEs · AI fixes
        </Badge>
        <h1 className="mx-auto max-w-3xl text-4xl font-semibold tracking-tight text-balance sm:text-6xl">
          The AI engineer that reviews, fixes and documents your code
        </h1>
        <p className="text-muted-foreground mx-auto mt-5 max-w-xl text-base text-balance">
          Import a repository and get a health score, security findings, one-click fixes, tests, docs and a PDF report.
        </p>

        <form
          className="bg-card mx-auto mt-10 flex max-w-2xl flex-col gap-2 rounded-full border p-1.5 shadow-sm sm:flex-row"
          onSubmit={(e) => {
            e.preventDefault()
            if (repo.trim()) run(() => api.post("/projects/github", { url: repo.trim() }).then(() => setRepo("")))
          }}
        >
          <div className="flex flex-1 items-center gap-2 pl-4">
            <GitBranch className="text-muted-foreground size-4" />
            <Input
              value={repo}
              onChange={(e) => setRepo(e.target.value)}
              placeholder="https://github.com/owner/repo"
              className="border-0 bg-transparent shadow-none focus-visible:ring-0 dark:bg-transparent"
            />
          </div>
          <Button type="submit" className="rounded-full px-6" disabled={busy || !repo.trim()}>
            {busy ? <Loader2 className="animate-spin" /> : <ArrowRight />} Analyze
          </Button>
        </form>
        <div className="mt-4">
          <input
            ref={fileRef}
            type="file"
            accept=".zip"
            hidden
            onChange={(e) => {
              const f = e.target.files?.[0]
              if (f) run(() => api.upload(f))
              e.target.value = ""
            }}
          />
          <Button variant="ghost" size="sm" className="text-muted-foreground" onClick={() => fileRef.current?.click()} disabled={busy}>
            <FileArchive /> or upload a .zip
          </Button>
        </div>
      </section>

      <main className="mx-auto max-w-6xl px-6 pb-24">
        {error && (
          <Card className="mb-8 flex-row items-center gap-3 px-5 py-4 shadow-none">
            <WifiOff className="text-muted-foreground size-5 shrink-0" />
            <p className="flex-1 text-sm">{error}</p>
            <Button variant="outline" size="sm" onClick={load}>Retry</Button>
          </Card>
        )}

        <div className="mb-4 flex items-baseline justify-between">
          <h2 className="text-lg font-semibold">Projects</h2>
          {projects && <span className="text-muted-foreground text-sm">{projects.length}</span>}
        </div>

        {projects?.length === 0 && (
          <div className="text-muted-foreground rounded-2xl border border-dashed p-12 text-center text-sm">
            No projects yet. Paste a GitHub URL above to start.
          </div>
        )}

        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {projects?.map((p) => <ProjectCard key={p.id} p={p} onChange={load} />)}
        </div>
      </main>
    </div>
  )
}

function ProjectCard({ p, onChange }: { p: ProjectSummary; onChange: () => void }) {
  const ready = p.status === "ready"
  const failed = p.status.startsWith("error")
  const stage = STAGES.indexOf(p.status)
  const langs = Object.keys(p.summary?.languages ?? {}).slice(0, 3)

  const body = (
    <Card className="hover:border-foreground/25 h-full flex-row items-center gap-5 p-5 shadow-none transition-colors">
      {ready ? (
        <ScoreRing score={p.health_score} size={76} />
      ) : (
        <div className="grid size-[76px] shrink-0 place-items-center">
          {failed ? <span className="text-sev-high text-xs">Failed</span> : <Loader2 className="text-muted-foreground size-6 animate-spin" />}
        </div>
      )}
      <div className="min-w-0 flex-1 space-y-2">
        <div className="flex items-start justify-between gap-2">
          <div className="truncate font-medium">{p.name}</div>
          <DropdownMenu>
            <DropdownMenuTrigger asChild onClick={(e) => e.preventDefault()}>
              <Button variant="ghost" size="icon" className="-mt-1 -mr-2 size-7"><MoreHorizontal /></Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" onClick={(e) => e.stopPropagation()}>
              <DropdownMenuItem onClick={async (e) => { e.preventDefault(); await api.post(`/projects/${p.id}/reanalyze`); onChange() }}>
                <RefreshCw /> Re-analyze
              </DropdownMenuItem>
              <DropdownMenuItem variant="destructive" onClick={async (e) => { e.preventDefault(); await api.del(`/projects/${p.id}`); onChange() }}>
                <Trash2 /> Delete
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
        {p.summary && (
          <div className="text-muted-foreground text-xs">
            {p.summary.files} files · {p.summary.lines.toLocaleString()} lines
          </div>
        )}
        {ready && p.counts ? (
          <div className="flex flex-wrap gap-1">
            {p.counts.high > 0 && <Badge variant="outline" className="text-sev-high border-sev-high/30">{p.counts.high} high</Badge>}
            {p.counts.medium > 0 && <Badge variant="outline" className="text-sev-medium border-sev-medium/30">{p.counts.medium} medium</Badge>}
            {!!p.vulnerable_deps && <Badge variant="outline" className="text-sev-high border-sev-high/30">{p.vulnerable_deps} vulnerable deps</Badge>}
            {langs.map((l) => <Badge key={l} variant="secondary">{l}</Badge>)}
          </div>
        ) : failed ? (
          <p className="text-sev-high line-clamp-2 text-xs">{p.error ?? p.status}</p>
        ) : (
          <div className="space-y-2">
            <ShimmeringText text={`${p.status[0].toUpperCase()}${p.status.slice(1)}…`} className="text-xs" />
            <Progress value={stage < 0 ? 10 : ((stage + 1) / STAGES.length) * 100} className="h-1" />
          </div>
        )}
      </div>
    </Card>
  )
  return ready ? <Link to={`/p/${p.id}`}>{body}</Link> : body
}
