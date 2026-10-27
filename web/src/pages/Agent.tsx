import { useRef, useState } from "react"
import { Link } from "react-router-dom"
import { Bot, CheckCircle2, CircleSlash, Flag, Loader2, Play, Square, TrendingUp, Wrench } from "lucide-react"

import { PageHeader, ScoreRing, Section, Stat } from "@/components/devmate"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { ShimmeringText } from "@/components/ui/shimmering-text"
import { Slider } from "@/components/ui/slider"
import { readSSE } from "@/lib/api"
import { cn } from "@/lib/utils"
import { useProject } from "@/pages/ProjectLayout"
import { AnimatePresence, motion } from "motion/react"
import { AnimatedDiff, ScanningCode } from "@/components/fix-animation"
import { Burst, EASE, PulseDot } from "@/components/motion"

interface Ev { type: string; data: any; at: number }

export default function Agent() {
  const { pid, reanalyze } = useProject()
  const [rounds, setRounds] = useState(3)
  const [perRound, setPerRound] = useState(5)
  const [events, setEvents] = useState<Ev[]>([])
  const [running, setRunning] = useState(false)
  const abort = useRef<AbortController | null>(null)

  const start = async () => {
    abort.current = new AbortController()
    setEvents([])
    setRunning(true)
    try {
      await readSSE(`/projects/${pid}/agent`, { rounds, per_round: perRound }, (e) => setEvents((x) => [...x, { ...e, at: Date.now() }]), abort.current.signal)
    } catch (e) {
      if ((e as Error).name !== "AbortError") setEvents((x) => [...x, { type: "error", data: (e as Error).message, at: Date.now() }])
    } finally {
      setRunning(false)
    }
  }

  const first = events.find((e) => e.type === "start")?.data
  const done = events.find((e) => e.type === "done")?.data
  const lastVerified = [...events].reverse().find((e) => e.type === "verified")?.data
  const current = done?.end ?? lastVerified?.after ?? first?.score
  const fixed = events.filter((e) => e.type === "fixed").length
  const working = [...events].reverse().find((e) => e.type === "fixing" || e.type === "finalizing")
  const lastStep = [...events].reverse().find((e) => e.type === "fixing" || e.type === "fixed" || e.type === "skipped")
  const fixingNow = running && lastStep?.type === "fixing" ? lastStep : null
  const lastFixed = [...events].reverse().find((e) => e.type === "fixed" && e.data.original)

  return (
    <div className="space-y-6">
      <PageHeader
        title="AI agent"
        description="An autonomous loop: the agent fixes the most important issues, re-runs the analysis to verify its own work, and repeats while the health score keeps improving."
      />

      <Card className="gap-6 p-6 shadow-none">
        <div className="grid gap-6 md:grid-cols-2">
          <div>
            <div className="mb-2 flex justify-between text-sm"><span>Rounds</span><span className="font-medium">{rounds}</span></div>
            <Slider min={1} max={6} step={1} value={[rounds]} onValueChange={([v]) => setRounds(v)} disabled={running} />
          </div>
          <div>
            <div className="mb-2 flex justify-between text-sm"><span>Fixes per round</span><span className="font-medium">{perRound}</span></div>
            <Slider min={1} max={15} step={1} value={[perRound]} onValueChange={([v]) => setPerRound(v)} disabled={running} />
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          {running ? (
            <Button variant="outline" onClick={() => abort.current?.abort()}><Square /> Stop watching</Button>
          ) : (
            <Button size="lg" onClick={start}><Play /> Run agent</Button>
          )}
          <p className="text-muted-foreground text-xs">With local AI each fix takes about 30–60 seconds; with cloud AI a few seconds.</p>
        </div>
      </Card>

      {first && (
        <div className="grid items-center gap-4 md:grid-cols-[auto_1fr]">
          <Card className="relative flex-row items-center gap-6 p-6 shadow-none">
            <div className="text-center"><ScoreRing score={first.score} size={90} /><div className="text-muted-foreground mt-1 text-xs">Before</div></div>
            <motion.div animate={running ? { x: [0, 6, 0] } : {}} transition={{ duration: 1.2, repeat: Infinity }}>
              <TrendingUp className="text-muted-foreground size-6" />
            </motion.div>
            <div className="relative text-center">
              <ScoreRing key={current} score={current} size={90} />
              <div className="text-muted-foreground mt-1 text-xs">{done ? "After" : "Now"}</div>
              <Burst show={!!done && done.end > done.start} />
            </div>
          </Card>
          <div className="grid grid-cols-3 gap-4">
            <Stat label="Fixes applied" value={fixed} tone={fixed ? "good" : undefined} />
            <Stat label="Score change" value={`${current - first.score >= 0 ? "+" : ""}${current - first.score}`} tone={current > first.score ? "good" : undefined} />
            <Stat label="Status" value={done ? "Done" : running ? "Running" : "Stopped"} />
          </div>
        </div>
      )}

      {running && working && (
        <div className="flex items-center gap-2 text-sm">
          <PulseDot className="text-sev-low" />
          <ShimmeringText
            text={working.type === "finalizing" ? "Re-running the full analysis…" : `Fixing ${working.data.rule} in ${working.data.file}:${working.data.line}…`}
          />
        </div>
      )}

      {(fixingNow || lastFixed) && (
        <div className="grid gap-4 lg:grid-cols-2">
          <AnimatePresence mode="wait">
            {fixingNow ? (
              <motion.div key={`scan-${fixingNow.at}`} initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -10 }} transition={{ duration: 0.35, ease: EASE }}>
                <Section title={`Operating on ${fixingNow.data.file}`} icon={<Wrench className="size-4" />}>
                  <ScanningCode code={fixingNow.data.snippet || `${fixingNow.data.file}:${fixingNow.data.line}`} label={`${fixingNow.data.rule} · line ${fixingNow.data.line}`} />
                </Section>
              </motion.div>
            ) : <div />}
          </AnimatePresence>
          <AnimatePresence mode="wait">
            {lastFixed && (
              <motion.div key={`diff-${lastFixed.at}`} initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -10 }} transition={{ duration: 0.35, ease: EASE }}>
                <Section title={`Patched ${lastFixed.data.rule}`} icon={<CheckCircle2 className="text-good size-4" />}>
                  <div className="text-muted-foreground mb-2 font-mono text-xs">{lastFixed.data.file}:{lastFixed.data.line}</div>
                  <AnimatedDiff original={lastFixed.data.original} fixed={lastFixed.data.fixed} speed={1.3} />
                </Section>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      )}

      {events.length > 0 && (
        <Section title="Timeline" icon={<Bot className="size-4" />}>
          <ol className="relative space-y-3 border-l pl-6">
            <AnimatePresence initial={false}>
              {events.filter((e) => e.type !== "fixing").map((e, i) => <TimelineItem key={i} e={e} />)}
            </AnimatePresence>
            {running && <li className="text-muted-foreground flex items-center gap-2 text-sm"><Loader2 className="size-4 animate-spin" /> working…</li>}
          </ol>
          {done && (
            <div className="mt-5 flex flex-wrap gap-2 border-t pt-5">
              <Button asChild><Link to={`/p/${pid}/fix`}>Review changes & download</Link></Button>
              <Button variant="outline" asChild><Link to={`/p/${pid}/compare`}>Compare before / after</Link></Button>
              <Button variant="ghost" onClick={reanalyze}>Refresh dashboard</Button>
            </div>
          )}
        </Section>
      )}
    </div>
  )
}

function TimelineItem({ e }: { e: Ev }) {
  const d = e.data
  const icon = {
    start: <Flag className="size-4" />, round: <Bot className="size-4" />, fixed: <CheckCircle2 className="text-good size-4" />,
    skipped: <CircleSlash className="text-muted-foreground size-4" />, verified: <TrendingUp className="size-4" />,
    stop: <Square className="size-4" />, done: <CheckCircle2 className="text-good size-4" />, error: <CircleSlash className="text-sev-high size-4" />,
    finalizing: <Wrench className="size-4" />,
  }[e.type] ?? <Bot className="size-4" />
  const text = (() => {
    switch (e.type) {
      case "start": return <>Started with score <b>{d.score}</b> and {d.issues} issues.</>
      case "round": return <b>Round {d.round}</b>
      case "fixed": return <>Fixed <b>{d.rule}</b> <span className="text-muted-foreground font-mono text-xs">{d.file}:{d.line} · −{d.removed} +{d.added}</span></>
      case "skipped": return <>Skipped <b>{d.rule}</b> <span className="text-muted-foreground text-xs">{d.reason}</span></>
      case "verified": return <>Verified: score <b>{d.before} → {d.after}</b>, {d.issues} issues left.</>
      case "stop": return <span className="text-muted-foreground">{d.reason}</span>
      case "finalizing": return <span className="text-muted-foreground">{d.message}</span>
      case "done": return <>Finished: <b>{d.start} → {d.end}</b> with {d.fixes} fixes.</>
      case "error": return <span className="text-sev-high">{String(d)}</span>
      default: return null
    }
  })()
  return (
    <motion.li
      className={cn("relative text-sm", e.type === "round" && "pt-2")}
      initial={{ opacity: 0, x: -12 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ duration: 0.35, ease: EASE }}
    >
      <motion.span
        className="bg-background absolute top-0.5 -left-[33px] grid size-5 place-items-center rounded-full"
        initial={{ scale: 0 }} animate={{ scale: 1 }} transition={{ type: "spring", stiffness: 400, damping: 18, delay: 0.05 }}
      >
        {icon}
      </motion.span>
      {text}
    </motion.li>
  )
}
