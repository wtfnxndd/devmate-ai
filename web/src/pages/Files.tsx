import { useMemo, useState } from "react"
import { BookOpen, Code2, FileCode2, FlaskConical, Lightbulb, Search, Wand2 } from "lucide-react"

import { AiPanel, CodeView, EmptyState, ErrorNote, languageFor, Loading, PageHeader, useApi } from "@/components/devmate"
import { Card } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { api } from "@/lib/api"
import { cn } from "@/lib/utils"
import { useProject } from "@/pages/ProjectLayout"

export default function Files() {
  const { pid } = useProject()
  const { data, error } = useApi<any[]>(() => api.get(`/projects/${pid}/files`), [pid])
  const [q, setQ] = useState("")
  const [sort, setSort] = useState("issues")
  const [sel, setSel] = useState<string | null>(null)

  const files = useMemo(() => {
    const score = (f: any) => f.issues.high * 100 + f.issues.medium * 10 + f.issues.low
    return (data ?? [])
      .filter((f) => f.file.toLowerCase().includes(q.toLowerCase()))
      .sort((a, b) =>
        sort === "lines" ? b.lines - a.lines
          : sort === "complexity" ? (b.max_complexity ?? 0) - (a.max_complexity ?? 0)
          : sort === "name" ? a.file.localeCompare(b.file)
          : score(b) - score(a),
      )
  }, [data, q, sort])

  if (error) return <ErrorNote error={error} />
  if (!data) return <Loading />

  return (
    <div>
      <PageHeader title="Files" description="Per-file metrics. Open a file to read it, explain it, refactor it, add documentation or generate tests." />
      <div className="grid gap-5 xl:grid-cols-[minmax(0,380px)_1fr]">
        <div className="space-y-3">
          <div className="flex gap-2">
            <div className="relative flex-1">
              <Search className="text-muted-foreground absolute top-2.5 left-3 size-4" />
              <Input className="pl-9" placeholder="Filter files…" value={q} onChange={(e) => setQ(e.target.value)} />
            </div>
            <Select value={sort} onValueChange={setSort}>
              <SelectTrigger className="w-36"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="issues">Most issues</SelectItem>
                <SelectItem value="complexity">Complexity</SelectItem>
                <SelectItem value="lines">Size</SelectItem>
                <SelectItem value="name">Name</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="max-h-[70vh] space-y-1.5 overflow-auto pr-1">
            {files.map((f) => (
              <button
                key={f.file}
                onClick={() => setSel(f.file)}
                className={cn("bg-card hover:border-foreground/30 flex w-full items-center gap-3 rounded-lg border px-3 py-2.5 text-left", sel === f.file && "border-foreground")}
              >
                <FileCode2 className="text-muted-foreground size-4 shrink-0" />
                <div className="min-w-0 flex-1">
                  <div className="truncate font-mono text-[13px]">{f.file}</div>
                  <div className="text-muted-foreground text-xs">
                    {f.language} · {f.lines} lines · {f.functions} fn{f.max_complexity ? ` · CC ${f.max_complexity}` : ""}
                  </div>
                </div>
                <div className="flex gap-1">
                  {f.issues.high > 0 && <Dot n={f.issues.high} c="bg-sev-high" />}
                  {f.issues.medium > 0 && <Dot n={f.issues.medium} c="bg-sev-medium" />}
                  {f.issues.low > 0 && <Dot n={f.issues.low} c="bg-sev-low" />}
                </div>
              </button>
            ))}
          </div>
        </div>
        <div>{sel ? <FileDetail key={sel} pid={pid} file={sel} /> : <EmptyState icon={<FileCode2 className="size-8" />} title="Select a file" />}</div>
      </div>
    </div>
  )
}

const Dot = ({ n, c }: { n: number; c: string }) => (
  <span className={cn("grid size-5 place-items-center rounded-full text-[10px] font-semibold text-white", c)}>{n}</span>
)

function FileDetail({ pid, file }: { pid: number; file: string }) {
  const { data: code } = useApi(() => api.text(`/projects/${pid}/file`, { path: file }), [file])
  const name = file.split("/").pop()
  const assist = (task: string, label: string) => (
    <AiPanel endpoint={`/projects/${pid}/file-assist`} body={{ file, task }} label={label} filename={`${name}.${task}.md`} autoRun />
  )
  return (
    <Card className="gap-4 p-6 shadow-none">
      <div className="font-mono text-sm font-medium">{file}</div>
      <Tabs defaultValue="code">
        <TabsList>
          <TabsTrigger value="code"><Code2 /> Code</TabsTrigger>
          <TabsTrigger value="explain"><Lightbulb /> Explain</TabsTrigger>
          <TabsTrigger value="refactor"><Wand2 /> Refactor</TabsTrigger>
          <TabsTrigger value="docstrings"><BookOpen /> Add docs</TabsTrigger>
          <TabsTrigger value="tests"><FlaskConical /> Tests</TabsTrigger>
        </TabsList>
        <TabsContent value="code" className="pt-3">
          {code == null ? <Loading rows={2} /> : <CodeView code={code} lang={languageFor(file)} className="max-h-[70vh]" />}
        </TabsContent>
        <TabsContent value="explain" className="pt-3">{assist("explain", "Explain this file")}</TabsContent>
        <TabsContent value="refactor" className="pt-3">{assist("refactor", "Suggest refactorings")}</TabsContent>
        <TabsContent value="docstrings" className="pt-3">{assist("docstrings", "Add documentation")}</TabsContent>
        <TabsContent value="tests" className="pt-3">
          <AiPanel endpoint={`/projects/${pid}/tests`} body={{ file }} label="Generate unit tests" filename={`tests_${name}.md`} autoRun />
        </TabsContent>
      </Tabs>
    </Card>
  )
}
