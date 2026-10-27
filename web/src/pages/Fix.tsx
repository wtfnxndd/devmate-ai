import { useState } from "react"
import { CheckCircle2, CircleSlash, FileArchive, FileDiff, Loader2, RotateCcw, ShieldCheck, Wand2 } from "lucide-react"
import { toast } from "sonner"

import { AiPanel, CopyButton, ErrorNote, Loading, PageHeader, PatchLines, Section, Stat, useApi } from "@/components/devmate"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import {
  Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog"
import { ShimmeringText } from "@/components/ui/shimmering-text"
import { Slider } from "@/components/ui/slider"
import { api, download, saveText } from "@/lib/api"
import { useProject } from "@/pages/ProjectLayout"

export default function Fix() {
  const { pid, project, reanalyze } = useProject()
  const name = project?.name ?? "project"
  const { data: c, error, reload } = useApi<any>(() => api.get(`/projects/${pid}/changes`), [pid])
  const [limit, setLimit] = useState(8)
  const [busy, setBusy] = useState(false)
  const [run, setRun] = useState<any>(null)

  if (error) return <ErrorNote error={error} />
  if (!c) return <Loading />
  const patch: string = c.patch
  const patchLines = patch.split("\n").filter((l) => /^[+-]/.test(l) && !/^(\+\+\+|---)/.test(l)).length

  const fixAll = async () => {
    setBusy(true)
    try {
      setRun(await api.post(`/projects/${pid}/fix-all`, undefined, { limit }))
      reload()
    } catch (e) {
      toast.error((e as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Fix & export"
        description="DevMate writes a patch for each high and medium issue and applies it to its copy of your code. Review the diff, re-analyze to verify, then download the fixed project or a .patch for your repository."
      />

      <Card className="gap-5 p-6 shadow-none">
        <div className="flex flex-wrap items-center gap-6">
          <div className="min-w-56 flex-1">
            <div className="mb-2 flex justify-between text-sm"><span>Issues to fix</span><span className="font-medium tabular-nums">{limit}</span></div>
            <Slider min={1} max={20} step={1} value={[limit]} onValueChange={([v]) => setLimit(v)} disabled={busy} />
          </div>
          <Button size="lg" onClick={fixAll} disabled={busy}>
            {busy ? <Loader2 className="animate-spin" /> : <Wand2 />} Fix with AI
          </Button>
        </div>
        {busy && <ShimmeringText text="Generating and applying patches…" className="text-sm" />}
        <div className="flex flex-wrap gap-2 border-t pt-5">
          <Button variant="outline" onClick={reanalyze} disabled={busy || !c.files.length}><ShieldCheck /> Re-analyze to verify</Button>
          <Button variant="outline" onClick={() => download(`/projects/${pid}/export/zip`, `${name}-devmate.zip`).catch((e) => toast.error(e.message))}>
            <FileArchive /> Download project (.zip)
          </Button>
          <Button variant="outline" disabled={!patch} onClick={() => saveText(patch, `${name}-devmate.patch`, "text/x-diff")}>
            <FileDiff /> Download .patch
          </Button>
          <Dialog>
            <DialogTrigger asChild>
              <Button variant="ghost" disabled={busy || !c.files.length}><RotateCcw /> Revert all</Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Revert all fixes?</DialogTitle>
                <DialogDescription>Every changed file goes back to its original content.</DialogDescription>
              </DialogHeader>
              <DialogFooter>
                <DialogClose asChild><Button variant="outline">Cancel</Button></DialogClose>
                <DialogClose asChild>
                  <Button variant="destructive" onClick={async () => { await api.post(`/projects/${pid}/fix/revert`); setRun(null); reload(); toast.success("Reverted") }}>
                    Revert
                  </Button>
                </DialogClose>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>
      </Card>

      <div className="grid grid-cols-3 gap-4">
        <Stat label="Fixes applied" value={c.applied.length} tone={c.applied.length ? "good" : undefined} />
        <Stat label="Files changed" value={c.files.length} />
        <Stat label="Patch lines" value={patchLines} />
      </div>

      {run && (
        <Section title="Last run">
          <div className="divide-y">
            {run.applied.map((a: any, i: number) => (
              <div key={"a" + i} className="flex items-center gap-3 py-2 text-sm">
                <CheckCircle2 className="text-good size-4" />
                <span className="font-medium">{a.rule}</span>
                <span className="text-muted-foreground font-mono text-xs">{a.file}:{a.line} · −{a.removed} +{a.added}</span>
              </div>
            ))}
            {run.failed.map((f: any, i: number) => (
              <div key={"f" + i} className="flex items-start gap-3 py-2 text-sm">
                <CircleSlash className="text-muted-foreground mt-0.5 size-4" />
                <div className="min-w-0">
                  <span className="font-medium">{f.rule}</span> <span className="text-muted-foreground">skipped</span>
                  <div className="text-muted-foreground line-clamp-2 text-xs">{f.file}:{f.line} · {f.reason}</div>
                </div>
              </div>
            ))}
          </div>
        </Section>
      )}

      {patch && (
        <Section title="Commit message & pull request">
          <AiPanel key={c.applied.length} pid={pid} kind="commit-message" label="Write commit message & PR description" filename={`${name}-pull-request.md`}
            description="A Conventional Commits message and a PR description (summary, changes, security impact, how to test) for these fixes." />
        </Section>
      )}

      <Section title="Changes" actions={patch ? <CopyButton text={patch} label="Copy patch" /> : undefined}>
        {patch ? <PatchLines lines={patch.split("\n")} /> : (
          <p className="text-muted-foreground text-sm">No changes yet. Use "Fix with AI" here, or "Apply to project" on a single finding.</p>
        )}
        {patch && <p className="text-muted-foreground mt-3 font-mono text-xs">git apply {name}-devmate.patch</p>}
      </Section>
    </div>
  )
}
