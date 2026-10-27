import { KeyRound, ShieldCheck } from "lucide-react"
import { Link } from "react-router-dom"

import { EmptyState, ErrorNote, Loading, PageHeader, Section, SeverityBadge, Stat, useApi } from "@/components/devmate"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { api } from "@/lib/api"
import { useProject } from "@/pages/ProjectLayout"

const ADVICE = [
  "Remove the value from the code and load it from an environment variable or a secret manager.",
  "Rotate (revoke and re-create) the key: anything ever committed to git should be treated as leaked.",
  "Add the file (e.g. .env) to .gitignore, and scrub history with git filter-repo if the repo is public.",
]

export default function Security() {
  const { pid } = useProject()
  const { data: d, error } = useApi<any>(() => api.get(`/projects/${pid}/secrets`), [pid])
  if (error) return <ErrorNote error={error} />
  if (!d) return <Loading />
  const list = d.secrets as any[]
  return (
    <div className="space-y-6">
      <PageHeader
        title="Secrets"
        description="Leaked credentials found in source and config files: 25+ known key formats (AWS, GitHub, Stripe, OpenAI, Google, Slack, database URLs, private keys…) plus high-entropy strings. Values are masked."
      />
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <Stat label="High risk" value={d.counts.high} tone={d.counts.high ? "bad" : "good"} />
        <Stat label="Medium" value={d.counts.medium} tone={d.counts.medium ? "warn" : undefined} />
        <Stat label="Low (tests)" value={d.counts.low} />
        <Stat label="Files scanned" value={d.files_scanned} />
      </div>
      {list.length === 0 ? (
        <EmptyState icon={<ShieldCheck className="size-8" />} title="No secrets found" description="No credentials or high-entropy tokens were detected." />
      ) : (
        <>
          <Section title="How to fix a leaked secret" icon={<KeyRound className="size-4" />}>
            <ol className="text-muted-foreground list-decimal space-y-1 pl-5 text-sm">{ADVICE.map((a) => <li key={a}>{a}</li>)}</ol>
          </Section>
          <Section title={`Findings (${list.length})`}>
            <div className="divide-y">
              {list.map((s, i) => (
                <div key={i} className="flex flex-wrap items-center gap-3 py-3">
                  <SeverityBadge severity={s.severity} />
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-medium">{s.description}</div>
                    <div className="text-muted-foreground font-mono text-xs">{s.file}:{s.line}</div>
                  </div>
                  <code className="bg-muted rounded px-2 py-0.5 text-xs">{s.masked}</code>
                  {s.env_file && <Badge variant="outline">.env file</Badge>}
                  {s.in_test && <Badge variant="secondary">test code</Badge>}
                  <Badge variant="outline" className="font-mono">{s.rule}</Badge>
                </div>
              ))}
            </div>
            <Button variant="link" asChild className="mt-2 px-0">
              <Link to={`/p/${pid}/findings`}>Open in Findings to fix with AI →</Link>
            </Button>
          </Section>
        </>
      )}
    </div>
  )
}
