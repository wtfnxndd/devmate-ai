import { useState } from "react"
import { Copy, CopyCheck, Sparkles } from "lucide-react"

import { AiPanel, CodeView, EmptyState, ErrorNote, languageFor, Loading, PageHeader, Section, Stat, useApi } from "@/components/devmate"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { api, type Duplication as Dup } from "@/lib/api"
import { useProject } from "@/pages/ProjectLayout"

export default function Duplication() {
  const { pid } = useProject()
  const { data: d, error } = useApi<Dup>(() => api.get(`/projects/${pid}/duplicates`), [pid])
  if (error) return <ErrorNote error={error} />
  if (!d) return <Loading />
  const pct = d.percentage ?? 0
  return (
    <div className="space-y-6">
      <PageHeader title="Duplication" description="Copy-pasted blocks of 6+ meaningful lines across files, like PMD CPD or jscpd." />
      <div className="grid grid-cols-3 gap-4">
        <Stat label="Duplicated code" value={`${pct}%`} hint="target: under 5%" tone={pct > 10 ? "bad" : pct > 5 ? "warn" : "good"} />
        <Stat label="Clone groups" value={d.blocks.length} />
        <Stat label="Duplicated lines" value={d.duplicated_lines ?? 0} />
      </div>
      {d.blocks.length === 0 ? (
        <EmptyState icon={<CopyCheck className="size-8" />} title="No duplicated code found" />
      ) : (
        d.blocks.map((b, i) => <Clone key={i} pid={pid} index={i} block={b} />)
      )}
    </div>
  )
}

function Clone({ pid, index, block }: { pid: number; index: number; block: Dup["blocks"][number] }) {
  const [ai, setAi] = useState(false)
  const first = block.occurrences[0]
  return (
    <Section
      title={`${block.lines} lines × ${block.occurrences.length} copies`}
      icon={<Copy className="size-4" />}
      actions={!ai && <Button variant="outline" size="sm" onClick={() => setAi(true)}><Sparkles /> Suggest refactor</Button>}
    >
      <div className="mb-3 flex flex-wrap gap-2">
        {block.occurrences.map((o) => (
          <Badge key={o.file + o.start} variant="secondary" className="font-mono">{o.file}:{o.start}–{o.end}</Badge>
        ))}
      </div>
      <CodeView code={block.snippet} lang={languageFor(first.file)} start={first.start} />
      {ai && (
        <div className="mt-5 border-t pt-5">
          <AiPanel endpoint={`/projects/${pid}/duplicates/${index}/refactor`} label="Suggest refactor" filename={`refactor-duplicate-${index + 1}.md`} autoRun />
        </div>
      )}
    </Section>
  )
}
