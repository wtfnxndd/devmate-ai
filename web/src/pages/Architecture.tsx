import { useMemo, useRef, useState } from "react"
import { Copy, ExternalLink, Minus, Plus } from "lucide-react"

import { CodeView, ErrorNote, Loading, PageHeader, Section, useApi } from "@/components/devmate"
import { Button } from "@/components/ui/button"
import { api } from "@/lib/api"
import { useProject } from "@/pages/ProjectLayout"

export default function Architecture() {
  const { pid } = useProject()
  const { data: d, error } = useApi<any>(() => api.get(`/projects/${pid}/architecture`), [pid])
  if (error) return <ErrorNote error={error} />
  if (!d) return <Loading />
  const edges: [string, string][] = d.dependencies.map((e: any) => [e.from, e.to])
  const state = btoa(unescape(encodeURIComponent(JSON.stringify({ code: d.mermaid, mermaid: { theme: "neutral" } }))))

  return (
    <div className="space-y-6">
      <PageHeader title="Architecture" description="How the modules import each other, parsed with Tree-sitter." />
      <Section
        title={`Module dependency graph · ${edges.length} imports`}
        actions={
          <div className="flex gap-1">
            <Button variant="ghost" size="sm" asChild>
              <a href={`https://mermaid.live/view#base64:${state}`} target="_blank" rel="noreferrer"><ExternalLink /> Mermaid Live</a>
            </Button>
            <Button variant="ghost" size="sm" onClick={() => navigator.clipboard.writeText(d.mermaid)}><Copy /> Mermaid</Button>
          </div>
        }
      >
        {edges.length ? <Graph edges={edges} /> : <p className="text-muted-foreground text-sm">No internal imports between files were detected.</p>}
      </Section>
      <Section title="Folder structure">
        <CodeView code={d.tree} className="max-h-[60vh]" />
      </Section>
    </div>
  )
}

/** Layered left→right graph: importers on the left, the modules they import on the right. */
function Graph({ edges }: { edges: [string, string][] }) {
  const W = 168, H = 36, COL = 80, ROW = 14, PAD = 20
  const [zoom, setZoom] = useState(1)
  const drag = useRef<{ x: number; y: number; sl: number; st: number } | null>(null)
  const box = useRef<HTMLDivElement>(null)

  const layout = useMemo(() => {
    const nodes = [...new Set(edges.flat())].sort()
    const deps = new Map(nodes.map((n) => [n, new Set<string>()]))
    const fanIn = new Map(nodes.map((n) => [n, 0]))
    for (const [a, b] of edges) { deps.get(a)!.add(b); fanIn.set(b, fanIn.get(b)! + 1) }
    const layer = new Map<string, number>()
    const depth = (n: string, seen: Set<string>): number => {
      if (layer.has(n)) return layer.get(n)!
      if (seen.has(n)) return 0
      seen.add(n)
      const d = Math.max(0, ...[...deps.get(n)!].map((m) => depth(m, seen) + 1))
      seen.delete(n)
      layer.set(n, d)
      return d
    }
    nodes.forEach((n) => depth(n, new Set()))
    const max = Math.max(...layer.values())
    const cols: string[][] = Array.from({ length: max + 1 }, () => [])
    nodes.forEach((n) => cols[max - layer.get(n)!].push(n))
    const tallest = Math.max(...cols.map((c) => c.length))
    const height = PAD * 2 + tallest * (H + ROW)
    const pos = new Map<string, { x: number; y: number }>()
    cols.forEach((col, c) => {
      const top = (height - col.length * (H + ROW)) / 2
      col.forEach((n, r) => pos.set(n, { x: PAD + c * (W + COL), y: top + r * (H + ROW) }))
    })
    return { nodes, pos, fanIn, deps, width: PAD * 2 + cols.length * (W + COL) - COL, height }
  }, [edges])

  return (
    <div className="relative">
      <div className="absolute top-2 right-2 z-10 flex gap-1">
        <Button variant="outline" size="icon" className="size-7" onClick={() => setZoom((z) => Math.min(2, z + 0.2))}><Plus /></Button>
        <Button variant="outline" size="icon" className="size-7" onClick={() => setZoom((z) => Math.max(0.3, z - 0.2))}><Minus /></Button>
      </div>
      <div
        ref={box}
        className="bg-surface h-[480px] cursor-grab overflow-auto rounded-xl border active:cursor-grabbing"
        onMouseDown={(e) => (drag.current = { x: e.clientX, y: e.clientY, sl: box.current!.scrollLeft, st: box.current!.scrollTop })}
        onMouseMove={(e) => {
          if (!drag.current || !box.current) return
          box.current.scrollLeft = drag.current.sl - (e.clientX - drag.current.x)
          box.current.scrollTop = drag.current.st - (e.clientY - drag.current.y)
        }}
        onMouseUp={() => (drag.current = null)}
        onMouseLeave={() => (drag.current = null)}
      >
        <svg width={layout.width * zoom} height={Math.max(layout.height, 200) * zoom} viewBox={`0 0 ${layout.width} ${Math.max(layout.height, 200)}`}>
          <defs>
            <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
              <path d="M0 0L10 5L0 10z" fill="var(--muted-foreground)" />
            </marker>
          </defs>
          {edges.map(([a, b], i) => {
            const p = layout.pos.get(a)!, q = layout.pos.get(b)!
            const fwd = q.x > p.x
            const x1 = fwd ? p.x + W : p.x, y1 = p.y + H / 2, x2 = fwd ? q.x : q.x + W, y2 = q.y + H / 2
            const bend = Math.abs(x2 - x1) / 2 + 30
            const s = fwd ? 1 : -1
            return (
              <path key={i} d={`M${x1},${y1} C${x1 + bend * s},${y1} ${x2 - bend * s},${y2} ${x2},${y2}`}
                fill="none" stroke="var(--muted-foreground)" strokeOpacity=".45" strokeWidth="1.3" markerEnd="url(#arrow)" />
            )
          })}
          {layout.nodes.map((n) => {
            const p = layout.pos.get(n)!
            const hub = layout.fanIn.get(n)! >= 3
            return (
              <g key={n} transform={`translate(${p.x},${p.y})`}>
                <title>{`${n}\nimports ${layout.deps.get(n)!.size} · imported by ${layout.fanIn.get(n)}`}</title>
                <rect width={W} height={H} rx="8" fill={hub ? "var(--foreground)" : "var(--card)"} stroke="var(--border)" />
                <text x={W / 2} y={H / 2 + 4} textAnchor="middle" fontSize="12" fontWeight="500" fill={hub ? "var(--background)" : "var(--foreground)"}>
                  {(n.split("/").pop() ?? n).slice(0, 24)}
                </text>
              </g>
            )
          })}
        </svg>
      </div>
      <p className="text-muted-foreground mt-2 text-xs">Drag to pan. Dark boxes are hubs imported by 3+ files. Hover a box for details.</p>
    </div>
  )
}
