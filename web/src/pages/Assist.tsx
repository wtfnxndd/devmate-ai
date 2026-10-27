import { useState } from "react"
import { BookOpen, ClipboardCheck, FlaskConical, Loader2, MapPin, ScrollText, Stethoscope } from "lucide-react"
import { toast } from "sonner"

import { AiBadge, AiPanel, ErrorNote, Loading, Markdown, PageHeader, ProviderBadge, useApi } from "@/components/devmate"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ShimmeringText } from "@/components/ui/shimmering-text"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Textarea } from "@/components/ui/textarea"
import { api, streamAi, type AiResult } from "@/lib/api"
import { useProject } from "@/pages/ProjectLayout"

type Kind = "review" | "docs" | "tests" | "debug" | "report"

export default function Assist({ kind }: { kind: Kind }) {
  const { pid, project } = useProject()
  const name = project?.name ?? "project"
  const pdf = (k: string) => ({ path: `/projects/${pid}/export/pdf`, kind: k })

  if (kind === "review")
    return (
      <Page title="AI code review" description="Explains the top issues, flags false positives, maps them to OWASP and gives corrected code.">
        <AiPanel pid={pid} kind="review" label="Run AI code review" icon={<ClipboardCheck />} filename={`${name}-code-review.md`} pdf={pdf("review")}
          description="Static tools have already found the issues; the AI reviews the most important ones in one request." />
      </Page>
    )
  if (kind === "report")
    return (
      <Page title="Health report" description="Executive summary, metrics, complexity, top issues, vulnerable dependencies and recommendations. Download it as Markdown or PDF.">
        <AiPanel pid={pid} kind="report" label="Generate health report" icon={<ScrollText />} filename={`${name}-health-report.md`} pdf={pdf("report")} autoRun />
      </Page>
    )
  if (kind === "docs")
    return (
      <Page title="Documentation" description="A README with an architecture diagram, plus an API reference for detected HTTP endpoints.">
        <Tabs defaultValue="readme">
          <TabsList><TabsTrigger value="readme">README.md</TabsTrigger><TabsTrigger value="api">API reference</TabsTrigger></TabsList>
          <TabsContent value="readme" className="pt-4">
            <AiPanel pid={pid} kind="readme" label="Generate README" icon={<BookOpen />} filename="README.md" pdf={pdf("readme")} />
          </TabsContent>
          <TabsContent value="api" className="pt-4">
            <AiPanel pid={pid} kind="api-docs" label="Generate API docs" icon={<BookOpen />} filename="API.md" pdf={pdf("api_docs")}
              description="Detects FastAPI, Flask, Express, Spring and Django routes." />
          </TabsContent>
        </Tabs>
      </Page>
    )
  if (kind === "tests") return <Tests pid={pid} />
  return <Debug pid={pid} />
}

function Page({ title, description, children }: { title: string; description: string; children: React.ReactNode }) {
  return (
    <div className="max-w-4xl">
      <PageHeader title={title} description={description} />
      <Card className="p-6 shadow-none">{children}</Card>
    </div>
  )
}

function Tests({ pid }: { pid: number }) {
  const { data: files, error } = useApi<any[]>(() => api.get(`/projects/${pid}/files`), [pid])
  const [file, setFile] = useState<string>()
  if (error) return <ErrorNote error={error} />
  if (!files) return <Loading />
  const candidates = files.filter((f) => f.functions > 0).sort((a, b) => b.functions - a.functions)
  return (
    <Page title="Test generator" description="Unit tests with happy paths, edge cases and mocks, in the right framework for each language.">
      <div className="space-y-5">
        <Select value={file} onValueChange={setFile}>
          <SelectTrigger className="w-full max-w-xl"><SelectValue placeholder="Choose a source file" /></SelectTrigger>
          <SelectContent>
            {candidates.map((f) => (
              <SelectItem key={f.file} value={f.file}>
                <span className="font-mono text-xs">{f.file}</span>
                <span className="text-muted-foreground ml-2 text-xs">{f.functions} fn</span>
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        {file && (
          <AiPanel key={file} pid={pid} kind="tests" body={{ file }} label="Generate tests" icon={<FlaskConical />}
            filename={`tests_${file.split("/").pop()}.md`} />
        )}
      </div>
    </Page>
  )
}

const EXAMPLE = `Traceback (most recent call last):
  File "app/main.py", line 42, in handler
    total = items / count
ZeroDivisionError: division by zero`

function Debug({ pid }: { pid: number }) {
  const [error, setError] = useState("")
  const [res, setRes] = useState<AiResult | null>(null)
  const [busy, setBusy] = useState(false)
  const [live, setLive] = useState("")
  const [provider, setProvider] = useState<string | null>(null)
  const go = async () => {
    if (!error.trim()) return
    setBusy(true)
    setLive("")
    setProvider(null)
    try {
      setRes(await streamAi(pid, "debug", { error }, { onText: setLive, onProvider: setProvider }))
    } catch (e) {
      toast.error((e as Error).message)
    } finally {
      setBusy(false)
    }
  }
  return (
    <Page title="Debugger" description="Paste a stack trace or log. DevMate finds the frames in your code, pulls related context and explains the fix.">
      <div className="space-y-4">
        <Textarea rows={9} className="font-mono text-[13px]" placeholder={EXAMPLE} value={error} onChange={(e) => setError(e.target.value)} />
        <div className="flex items-center gap-2">
          <Button onClick={go} disabled={busy || !error.trim()}>
            {busy ? <Loader2 className="animate-spin" /> : <Stethoscope />} Explain & fix
          </Button>
          <Button variant="ghost" onClick={() => { setError(""); setRes(null) }}>Clear</Button>
          <ProviderBadge provider={provider} />
          {res && !busy && <AiBadge ai={res.ai} />}
        </div>
        {busy && !live && <ShimmeringText text="Tracing the error through your code…" className="text-sm" />}
        {busy && live && <Markdown>{live}</Markdown>}
        {res && !busy && (
          <div className="space-y-4 pt-2">
            {(res.frames as any[])?.length > 0 && (
              <div className="flex flex-wrap gap-2">
                {(res.frames as any[]).map((f) => (
                  <Badge key={f.file + f.line} variant="secondary" className="font-mono"><MapPin /> {f.file}:{f.line}</Badge>
                ))}
              </div>
            )}
            <Markdown>{res.markdown}</Markdown>
          </div>
        )}
      </div>
    </Page>
  )
}
