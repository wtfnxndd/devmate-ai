import { useEffect, useRef, type ReactNode } from "react"
import { animate, motion, useInView, useMotionValue, useTransform, type Variants } from "motion/react"

import { cn } from "@/lib/utils"

export const EASE = [0.22, 1, 0.36, 1] as const

/** Fades and lifts content in when it enters the viewport. */
export function FadeIn({ children, delay = 0, y = 12, className }: { children: ReactNode; delay?: number; y?: number; className?: string }) {
  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, y }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-40px" }}
      transition={{ duration: 0.5, delay, ease: EASE }}
    >
      {children}
    </motion.div>
  )
}

const container: Variants = { hidden: {}, show: { transition: { staggerChildren: 0.05, delayChildren: 0.05 } } }
const item: Variants = {
  hidden: { opacity: 0, y: 14, scale: 0.98 },
  show: { opacity: 1, y: 0, scale: 1, transition: { duration: 0.45, ease: EASE } },
}

/** Children wrapped in <StaggerItem> appear one after another. */
export function Stagger({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <motion.div className={className} variants={container} initial="hidden" whileInView="show" viewport={{ once: true, margin: "-40px" }}>
      {children}
    </motion.div>
  )
}

export function StaggerItem({ children, className }: { children: ReactNode; className?: string }) {
  return <motion.div className={className} variants={item}>{children}</motion.div>
}

/** Page-level enter animation, keyed by route. */
export function PageTransition({ children, id }: { children: ReactNode; id: string }) {
  return (
    <motion.div
      key={id}
      initial={{ opacity: 0, y: 10, filter: "blur(4px)" }}
      animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
      transition={{ duration: 0.35, ease: EASE }}
    >
      {children}
    </motion.div>
  )
}

/** Animated number that counts from its previous value to the new one. */
export function CountUp({ value, decimals = 0, className, duration = 1 }: { value: number; decimals?: number; className?: string; duration?: number }) {
  const ref = useRef<HTMLSpanElement>(null)
  const inView = useInView(ref, { once: true })
  const mv = useMotionValue(0)
  const text = useTransform(mv, (v) => v.toLocaleString(undefined, { minimumFractionDigits: decimals, maximumFractionDigits: decimals }))
  useEffect(() => {
    if (!inView) return
    const c = animate(mv, value, { duration, ease: EASE })
    return () => c.stop()
  }, [value, inView, duration, mv])
  return <motion.span ref={ref} className={cn("tabular-nums", className)}>{text}</motion.span>
}

/** Soft pulsing dot used for "live" / "working" indicators. */
export function PulseDot({ className }: { className?: string }) {
  return (
    <span className={cn("relative inline-flex size-2", className)}>
      <motion.span
        className="absolute inline-flex size-full rounded-full bg-current opacity-60"
        animate={{ scale: [1, 2.2], opacity: [0.6, 0] }}
        transition={{ duration: 1.4, repeat: Infinity, ease: "easeOut" }}
      />
      <span className="relative inline-flex size-2 rounded-full bg-current" />
    </span>
  )
}

/** Celebration burst (lightweight, no canvas). */
export function Burst({ show }: { show: boolean }) {
  if (!show) return null
  const pieces = Array.from({ length: 22 })
  return (
    <div className="pointer-events-none absolute inset-0 overflow-visible">
      {pieces.map((_, i) => {
        const angle = (i / pieces.length) * Math.PI * 2
        const dist = 70 + (i % 4) * 22
        return (
          <motion.span
            key={i}
            className="absolute top-1/2 left-1/2 size-1.5 rounded-full"
            style={{ background: ["var(--good)", "var(--sev-low)", "var(--sev-medium)", "var(--foreground)"][i % 4] }}
            initial={{ x: 0, y: 0, opacity: 1, scale: 1 }}
            animate={{ x: Math.cos(angle) * dist, y: Math.sin(angle) * dist, opacity: 0, scale: 0.4 }}
            transition={{ duration: 1.1, ease: "easeOut", delay: (i % 3) * 0.04 }}
          />
        )
      })}
    </div>
  )
}
