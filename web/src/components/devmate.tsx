import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react"
import { Check, Copy, Download, FileText, RefreshCw, Sparkles, Square, Wand2 } from "lucide-react"
import { motion } from "motion/react"
import { useTheme } from "next-themes"
import { toast } from "sonner"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Response } from "@/components/ui/response"
import { ShimmeringText } from "@/components/ui/shimmering-text"
import { Skeleton } from "@/components/ui/skeleton"
import { CountUp, EASE } from "@/components/motion"
import { download, providerLabel, saveText, streamAi, type AiResult, type Severity } from "@/lib/api"
import { cn } from "@/lib/utils"

// ---------------------------------------------------------------- data hook
export function useApi<T>(fn: () => Promise<T>, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const run = useCallback(() => {
    setLoading(true)
    setError(null)
    fn()
      .then(setData)
      .catch((e) => setError(String(e.message ?? e)))
      .finally(() => setLoading(false))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps)
  useEffect(run, [run])
  return { data, error, loading, reload: run, setData }
}

export function Loading({ rows = 3 }: { rows?: number }) {
  return (
    <div className="space-y-3">
      {Array.from({ length: rows }).map((_, i) => (
        <Skeleton key={i} className="h-24 w-full rounded-xl" />
      ))}
    </div>
  )
}

export function ErrorNote({ error }: { error: string }) {
  return <div className="text-destructive rounded-xl border border-current/20 p-4 text-sm">{error}</div>
}

// ---------------------------------------------------------------- page chrome
export function PageHeader({ title, description, actions }: { title: string; description?: string; actions?: ReactNode }) {
  return (
    <div className="mb-8 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
        {description && <p className="text-muted-foreground mt-1 max-w-2xl text-sm">{description}</p>}
      </div>
      {actions && <div className="flex flex-wrap gap-2">{actions}</div>}
    </div>
  )
}

export function Section({ title, icon, actions, children, className }: {
  title: string
  icon?: ReactNode
  actions?: ReactNode
  children: ReactNode
  className?: string
}) {
  return (
    <Card className={cn("gap-4 shadow-none", className)}>
      <CardHeader className="flex flex-row items-center justify-between gap-2">
        <CardTitle className="flex items-center gap-2 text-sm font-medium">
          {icon}
          {title}
        </CardTitle>
        {actions}
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  )
}

export function Stat({ label, value, hint, tone }: { label: string; value: ReactNode; hint?: string; tone?: "good" | "bad" | "warn" }) {
  return (
    <Card className="hover:border-foreground/20 gap-1 px-5 py-4 shadow-none transition-all duration-300 hover:-translate-y-0.5">
      <div className="text-muted-foreground text-xs font-medium tracking-wide uppercase">{label}</div>
      <div
        className={cn(
          "text-2xl font-semibold tabular-nums",
          tone === "good" && "text-good",
          tone === "bad" && "text-sev-high",
          tone === "warn" && "text-sev-medium",
        )}
      >
        {typeof value === "number" ? <CountUp value={value} decimals={Number.isInteger(value) ? 0 : 1} /> : value}
      </div>
      {hint && <div className="text-muted-foreground text-xs">{hint}</div>}
    </Card>
  )
}

export function EmptyState({ icon, title, description }: { icon?: ReactNode; title: string; description?: string }) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 rounded-xl border border-dashed p-12 text-center">
      {icon && <div className="text-muted-foreground">{icon}</div>}
      <div className="font-medium">{title}</div>
      {description && <p className="text-muted-foreground max-w-md text-sm">{description}</p>}
    </div>
  )
}

// ---------------------------------------------------------------- score / severity
export const scoreColor = (s?: number | null) =>
  s == null ? "var(--muted-foreground)" : s >= 85 ? "var(--good)" : s >= 70 ? "oklch(0.75 0.17 130)" : s >= 55 ? "var(--sev-medium)" : "var(--sev-high)"

export function ScoreRing({ score, grade, size = 120 }: { score?: number | null; grade?: string | null; size?: number }) {
  const r = 44
  const c = 2 * Math.PI * r
  const pct = Math.max(0, Math.min(100, score ?? 0)) / 100
  return (
    <div className="relative shrink-0" style={{ width: size, height: size }}>
      <svg viewBox="0 0 100 100" className="size-full -rotate-90">
        <circle cx="50" cy="50" r={r} fill="none" stroke="var(--border)" strokeWidth="8" />
        <motion.circle
          cx="50" cy="50" r={r} fill="none" stroke={scoreColor(score)} strokeWidth="8" strokeLinecap="round"
          strokeDasharray={c} initial={{ strokeDashoffset: c }} animate={{ strokeDashoffset: c * (1 - pct) }}
          transition={{ duration: 1.1, ease: EASE }}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="font-semibold tabular-nums" style={{ fontSize: size * 0.26, color: scoreColor(score) }}>
          {score == null ? "–" : <CountUp value={score} duration={1.1} />}
        </span>
        {grade && <span className="text-muted-foreground" style={{ fontSize: size * 0.1 }}>Grade {grade}</span>}
      </div>
    </div>
  )
}

const SEV_CLASS: Record<string, string> = {
  high: "bg-sev-high/12 text-sev-high border-sev-high/25",
  medium: "bg-sev-medium/12 text-sev-medium border-sev-medium/25",
  low: "bg-sev-low/12 text-sev-low border-sev-low/25",
}

export function SeverityBadge({ severity }: { severity: Severity | string }) {
  return (
    <Badge variant="outline" className={cn("font-mono text-[10px] tracking-wider uppercase", SEV_CLASS[severity])}>
      {severity}
    </Badge>
  )
}

export function AiBadge({ ai }: { ai: boolean }) {
  return (
    <Badge variant={ai ? "default" : "secondary"} className="gap-1">
      {ai ? <Sparkles className="size-3" /> : null}
      {ai ? "AI" : "Static analysis"}
    </Badge>
  )
}

// ---------------------------------------------------------------- code
export function languageFor(file: string) {
  const ext = file.split(".").pop()?.toLowerCase() ?? ""
  return (
    {
      py: "python", js: "javascript", jsx: "jsx", ts: "typescript", tsx: "tsx", java: "java", kt: "kotlin", go: "go",
      rs: "rust", c: "c", h: "c", cpp: "cpp", cs: "csharp", rb: "ruby", php: "php", dart: "dart", swift: "swift",
    } as Record<string, string>
  )[ext] ?? "text"
}

/** Syntax-highlighted code (Shiki, loaded on demand) with line numbers and an optional highlighted line. */
export function CodeView({ code, lang = "text", start = 1, highlight, className }: {
  code: string
  lang?: string
  start?: number
  highlight?: number
  className?: string
}) {
  const { resolvedTheme } = useTheme()
  const [html, setHtml] = useState<string | null>(null)
  useEffect(() => {
    let alive = true
    import("shiki").then(async ({ codeToHtml }) => {
      const out = await codeToHtml(code, {
        lang,
        theme: resolvedTheme === "dark" ? "github-dark-default" : "github-light-default",
        transformers: [
          {
            line(node, line) {
              node.properties["data-line"] = String(start + line - 1)
              if (start + line - 1 === highlight) this.addClassToHast(node, "code-line-hl")
            },
          },
        ],
      }).catch(() => null)
      if (alive) setHtml(out)
    })
    return () => {
      alive = false
    }
  }, [code, lang, start, highlight, resolvedTheme])

  return (
    <div className={cn("bg-surface overflow-auto rounded-xl border text-[13px] leading-relaxed", className)}>
      {html ? (
        <div
          className="[&_.line]:before:text-muted-foreground/60 [&_pre]:!bg-transparent [&_pre]:p-4 [&_.line]:inline-block [&_.line]:w-full [&_.line]:before:mr-4 [&_.line]:before:inline-block [&_.line]:before:w-8 [&_.line]:before:text-right [&_.line]:before:content-[attr(data-line)]"
          dangerouslySetInnerHTML={{ __html: html }}
        />
      ) : (
        <pre className="p-4 font-mono">{code}</pre>
      )}
    </div>
  )
}

/** Line-level diff (LCS) between original and fixed code. */
export function DiffView({ original, fixed }: { original: string; fixed: string }) {
  const rows = useMemo(() => {
    const a = original.split("\n"), b = fixed.split("\n")
    const n = a.length, m = b.length
    const dp = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0))
    for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1])
    const out: [string, string][] = []
    let i = 0, j = 0
    while (i < n || j < m) {
      if (i < n && j < m && a[i] === b[j]) { out.push([" ", a[i]]); i++; j++ }
      else if (i < n && (j >= m || dp[i + 1][j] >= dp[i][j + 1])) out.push(["-", a[i++]])
      else out.push(["+", b[j++]])
    }
    return out
  }, [original, fixed])
  return <PatchLines lines={rows.map(([s, t]) => s + " " + t)} />
}

export function PatchLines({ lines }: { lines: string[] }) {
  return (
    <div className="bg-surface overflow-auto rounded-xl border py-3 font-mono text-[12.5px] leading-relaxed">
      {lines.map((l, i) => {
        const head = l.startsWith("+++") || l.startsWith("---")
        return (
          <div
            key={i}
            className={cn(
              "px-4 whitespace-pre",
              !head && l.startsWith("+") && "bg-good/15",
              !head && l.startsWith("-") && "bg-sev-high/15",
              l.startsWith("@@") && "text-sev-low",
              head && "text-muted-foreground font-semibold",
            )}
          >
            {l || " "}
          </div>
        )
      })}
    </div>
  )
}

// ---------------------------------------------------------------- markdown
export function Markdown({ children }: { children: string }) {
  return (
    <Response className="prose-sm max-w-none text-sm leading-relaxed [&_h1]:text-xl [&_h1]:font-semibold [&_h2]:mt-6 [&_h2]:text-lg [&_h2]:font-semibold [&_h3]:font-semibold [&_table]:text-xs">
      {children}
    </Response>
  )
}

export function CopyButton({ text, label }: { text: string; label?: string }) {
  const [done, setDone] = useState(false)
  return (
    <Button
      variant="outline"
      size="sm"
      onClick={() => {
        navigator.clipboard.writeText(text)
        setDone(true)
        setTimeout(() => setDone(false), 1500)
      }}
    >
      {done ? <Check /> : <Copy />}
      {label ?? (done ? "Copied" : "Copy")}
    </Button>
  )
}

export function ProviderBadge({ provider }: { provider?: string | null }) {
  if (!provider) return null
  const local = provider.startsWith("local:")
  return (
    <Badge variant="outline" className="gap-1.5 font-normal">
      <span className={cn("size-1.5 rounded-full", local ? "bg-good" : "bg-sev-low")} />
      {providerLabel(provider)}
    </Badge>
  )
}

/** Runs an AI feature with live streaming and shows the Markdown, with copy / .md / PDF download. */
export function AiPanel({ pid, kind, body, label, description, filename, pdf, autoRun, icon }: {
  pid: number
  kind: string
  body?: unknown
  label: string
  description?: string
  filename: string
  pdf?: { path: string; kind: string }
  autoRun?: boolean
  icon?: ReactNode
}) {
  const [result, setResult] = useState<AiResult | null>(null)
  const [live, setLive] = useState("")
  const [provider, setProvider] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [pdfLoading, setPdfLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const abort = useRef<AbortController | null>(null)

  const run = useCallback(
    async (refresh = false) => {
      abort.current?.abort()
      abort.current = new AbortController()
      setLoading(true)
      setError(null)
      setLive("")
      setProvider(null)
      try {
        const r = await streamAi(pid, kind, body, { onText: setLive, onProvider: setProvider }, { refresh, signal: abort.current.signal })
        setResult(r)
      } catch (e) {
        if ((e as Error).name !== "AbortError") setError(String((e as Error).message))
      } finally {
        setLoading(false)
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [pid, kind, JSON.stringify(body)],
  )

  useEffect(() => {
    if (autoRun) run()
    return () => abort.current?.abort()
  }, [autoRun, run])

  const getPdf = async () => {
    if (!pdf) return
    setPdfLoading(true)
    try {
      await download(pdf.path, filename.replace(/\.md$/, ".pdf"), { kind: pdf.kind })
      toast.success("PDF downloaded")
    } catch (e) {
      toast.error(`PDF failed: ${(e as Error).message}`)
    } finally {
      setPdfLoading(false)
    }
  }

  const shown = loading ? live : result?.markdown
  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center gap-2">
        {loading ? (
          <Button variant="outline" onClick={() => abort.current?.abort()}>
            <Square /> Stop
          </Button>
        ) : (
          <Button onClick={() => run(result != null)}>
            {result ? <RefreshCw /> : icon ?? <Wand2 />}
            {result ? "Regenerate" : label}
          </Button>
        )}
        <ProviderBadge provider={provider} />
        {result && !loading && (
          <>
            <AiBadge ai={result.ai} />
            <CopyButton text={result.markdown} />
            <Button variant="outline" size="sm" onClick={() => saveText(result.markdown, filename)}>
              <Download /> .md
            </Button>
            {pdf && (
              <Button variant="outline" size="sm" onClick={getPdf} disabled={pdfLoading}>
                {pdfLoading ? <RefreshCw className="animate-spin" /> : <FileText />} PDF
              </Button>
            )}
          </>
        )}
      </div>
      {!result && !loading && description && <p className="text-muted-foreground text-sm">{description}</p>}
      {loading && !live && (
        <div className="space-y-3 py-2">
          <ShimmeringText text={provider?.startsWith("local:") ? "Running on your computer…" : "DevMate is thinking…"} className="text-sm" />
          <Skeleton className="h-4 w-3/4" />
          <Skeleton className="h-4 w-2/3" />
        </div>
      )}
      {error && <ErrorNote error={error} />}
      {shown && (
        <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4, ease: EASE }}>
          <Markdown>{shown}</Markdown>
        </motion.div>
      )}
    </div>
  )
}
