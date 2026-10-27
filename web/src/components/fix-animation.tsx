import { useMemo } from "react"
import { AnimatePresence, motion } from "motion/react"
import { Check, Sparkles } from "lucide-react"

import { EASE } from "@/components/motion"
import { cn } from "@/lib/utils"

type Row = { kind: " " | "-" | "+"; text: string }

export function diffRows(original: string, fixed: string): Row[] {
  const a = original.split("\n"), b = fixed.split("\n")
  const n = a.length, m = b.length
  const dp = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0))
  for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1])
  const out: Row[] = []
  let i = 0, j = 0
  while (i < n || j < m) {
    if (i < n && j < m && a[i] === b[j]) { out.push({ kind: " ", text: a[i] }); i++; j++ }
    else if (i < n && (j >= m || dp[i + 1][j] >= dp[i][j + 1])) out.push({ kind: "-", text: a[i++] })
    else out.push({ kind: "+", text: b[j++] })
  }
  return out
}

/** Code with a scanning beam: shown while the AI is analysing / writing a fix. */
export function ScanningCode({ code, label = "Analysing…", className }: { code: string; label?: string; className?: string }) {
  const lines = code.split("\n")
  return (
    <div className={cn("bg-surface relative overflow-hidden rounded-xl border font-mono text-[12.5px] leading-relaxed", className)}>
      <div className="py-3">
        {lines.map((l, i) => (
          <motion.div
            key={i}
            className="px-4 whitespace-pre"
            initial={{ opacity: 0, x: -6 }}
            animate={{ opacity: [0.55, 1, 0.55] }}
            transition={{ duration: 2.2, repeat: Infinity, delay: i * 0.08 }}
          >
            {l || " "}
          </motion.div>
        ))}
      </div>
      {/* scanning beam */}
      <motion.div
        className="pointer-events-none absolute inset-x-0 h-14"
        style={{ background: "linear-gradient(180deg, transparent, color-mix(in oklch, var(--sev-low) 22%, transparent), transparent)" }}
        initial={{ top: "-15%" }}
        animate={{ top: ["-15%", "100%"] }}
        transition={{ duration: 1.6, repeat: Infinity, ease: "easeInOut" }}
      />
      <motion.div
        className="bg-background/90 absolute top-2 right-2 flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] backdrop-blur"
        animate={{ opacity: [0.7, 1, 0.7] }}
        transition={{ duration: 1.4, repeat: Infinity }}
      >
        <Sparkles className="size-3" /> {label}
      </motion.div>
    </div>
  )
}

/** Animated before→after: removed lines turn red and strike out, new lines slide in green, then a check pops. */
export function AnimatedDiff({ original, fixed, className, speed = 1 }: { original: string; fixed: string; className?: string; speed?: number }) {
  const rows = useMemo(() => diffRows(original, fixed), [original, fixed])
  const removed = rows.filter((r) => r.kind === "-").length
  let removeIdx = 0, addIdx = 0
  const step = 0.09 / speed
  const addStart = 0.35 / speed + removed * step
  const total = addStart + rows.filter((r) => r.kind === "+").length * step + 0.3

  return (
    <div className={cn("bg-surface relative overflow-hidden rounded-xl border py-3 font-mono text-[12.5px] leading-relaxed", className)}>
      {rows.map((r, i) => {
        if (r.kind === " ")
          return (
            <motion.div key={i} className="px-4 whitespace-pre" initial={{ opacity: 0 }} animate={{ opacity: 0.85 }} transition={{ duration: 0.3 }}>
              {"  " + (r.text || " ")}
            </motion.div>
          )
        if (r.kind === "-") {
          const d = 0.2 / speed + removeIdx++ * step
          return (
            <motion.div
              key={i}
              className="relative px-4 whitespace-pre"
              initial={{ backgroundColor: "rgba(0,0,0,0)", opacity: 1 }}
              animate={{ backgroundColor: "color-mix(in oklch, var(--sev-high) 16%, transparent)", opacity: 0.75 }}
              transition={{ delay: d, duration: 0.35 }}
            >
              <span className="text-sev-high">- </span>
              {r.text || " "}
              <motion.span
                className="bg-sev-high/70 absolute top-1/2 left-8 h-px"
                initial={{ width: 0 }}
                animate={{ width: "calc(100% - 3rem)" }}
                transition={{ delay: d + 0.15, duration: 0.35, ease: EASE }}
              />
            </motion.div>
          )
        }
        const d = addStart + addIdx++ * step
        return (
          <motion.div
            key={i}
            className="overflow-hidden px-4 whitespace-pre"
            initial={{ opacity: 0, x: -14, height: 0 }}
            animate={{ opacity: 1, x: 0, height: "auto", backgroundColor: "color-mix(in oklch, var(--good) 16%, transparent)" }}
            transition={{ delay: d, duration: 0.4, ease: EASE }}
          >
            <span className="text-good">+ </span>
            {r.text || " "}
          </motion.div>
        )
      })}
      <AnimatePresence>
        <motion.div
          className="bg-good absolute top-2 right-2 grid size-7 place-items-center rounded-full text-white shadow-lg"
          initial={{ scale: 0, rotate: -90 }}
          animate={{ scale: [0, 1.25, 1], rotate: 0 }}
          transition={{ delay: total, duration: 0.5, ease: EASE }}
        >
          <Check className="size-4" />
        </motion.div>
      </AnimatePresence>
      {/* green sweep once the fix lands */}
      <motion.div
        className="pointer-events-none absolute inset-0"
        style={{ background: "linear-gradient(90deg, transparent, color-mix(in oklch, var(--good) 18%, transparent), transparent)" }}
        initial={{ x: "-100%" }}
        animate={{ x: "100%" }}
        transition={{ delay: total - 0.1, duration: 0.8, ease: "easeInOut" }}
      />
    </div>
  )
}
