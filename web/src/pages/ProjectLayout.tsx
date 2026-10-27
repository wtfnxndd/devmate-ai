import { useCallback, useState } from "react"
import { Link, NavLink, Outlet, useLocation, useOutletContext, useParams } from "react-router-dom"
import {
  ArrowLeft, BookOpen, Boxes, Bug, Copy, FileCode2, FlaskConical, GitCompare, LayoutDashboard, Loader2,
  MessagesSquare, Network, RefreshCw, ScrollText, Stethoscope, Wand2, ClipboardCheck, Cpu,
} from "lucide-react"
import { toast } from "sonner"

import { Logo, ThemeToggle } from "@/components/chrome"
import { useApi } from "@/components/devmate"
import { Button } from "@/components/ui/button"
import { Separator } from "@/components/ui/separator"
import {
  Sidebar, SidebarContent, SidebarFooter, SidebarGroup, SidebarGroupContent, SidebarGroupLabel, SidebarHeader, SidebarInset,
  SidebarMenu, SidebarMenuButton, SidebarMenuItem, SidebarProvider, SidebarTrigger,
} from "@/components/ui/sidebar"
import { api, type ProjectSummary } from "@/lib/api"

const NAV = [
  { group: "Analysis", items: [
    { to: "", label: "Dashboard", icon: LayoutDashboard },
    { to: "findings", label: "Findings", icon: Bug },
    { to: "dependencies", label: "Dependencies", icon: Boxes },
    { to: "files", label: "Files", icon: FileCode2 },
    { to: "architecture", label: "Architecture", icon: Network },
  ] },
  { group: "AI assistant", items: [
    { to: "review", label: "Code review", icon: ClipboardCheck },
    { to: "docs", label: "Documentation", icon: BookOpen },
    { to: "tests", label: "Test generator", icon: FlaskConical },
    { to: "debug", label: "Debugger", icon: Stethoscope },
    { to: "chat", label: "Chat", icon: MessagesSquare },
    { to: "report", label: "Health report", icon: ScrollText },
  ] },
  { group: "Improve", items: [
    { to: "fix", label: "Fix & export", icon: Wand2 },
    { to: "duplication", label: "Duplication", icon: Copy },
    { to: "compare", label: "Compare", icon: GitCompare },
  ] },
]

export interface ProjectCtx {
  pid: number
  project: ProjectSummary | null
  version: number
  reanalyze: () => Promise<void>
}

export const useProject = () => useOutletContext<ProjectCtx>()

export default function ProjectLayout() {
  const pid = Number(useParams().pid)
  const loc = useLocation()
  const [version, setVersion] = useState(0)
  const [busy, setBusy] = useState(false)
  const { data: project } = useApi<ProjectSummary>(() => api.get(`/projects/${pid}`), [pid, version])

  const reanalyze = useCallback(async () => {
    setBusy(true)
    try {
      await api.post(`/projects/${pid}/reanalyze`)
      for (;;) {
        await new Promise((r) => setTimeout(r, 2000))
        const p = await api.get<ProjectSummary>(`/projects/${pid}`)
        if (p.status === "ready" || p.status.startsWith("error")) break
      }
      setVersion((v) => v + 1)
      toast.success("Analysis updated")
    } catch (e) {
      toast.error((e as Error).message)
    } finally {
      setBusy(false)
    }
  }, [pid])

  const current = NAV.flatMap((g) => g.items).find((i) => loc.pathname.endsWith(`/${pid}${i.to ? "/" + i.to : ""}`))

  return (
    <SidebarProvider>
      <Sidebar variant="inset">
        <SidebarHeader className="px-3 pt-4">
          <Link to="/"><Logo /></Link>
        </SidebarHeader>
        <SidebarContent>
          {NAV.map((g) => (
            <SidebarGroup key={g.group}>
              <SidebarGroupLabel>{g.group}</SidebarGroupLabel>
              <SidebarGroupContent>
                <SidebarMenu>
                  {g.items.map((i) => (
                    <SidebarMenuItem key={i.label}>
                      <NavLink to={`/p/${pid}${i.to ? "/" + i.to : ""}`} end>
                        {({ isActive }) => (
                          <SidebarMenuButton isActive={isActive}>
                            <i.icon /> <span>{i.label}</span>
                          </SidebarMenuButton>
                        )}
                      </NavLink>
                    </SidebarMenuItem>
                  ))}
                </SidebarMenu>
              </SidebarGroupContent>
            </SidebarGroup>
          ))}
        </SidebarContent>
        <SidebarFooter>
          <SidebarMenu>
            <SidebarMenuItem>
              <SidebarMenuButton asChild><Link to="/ai"><Cpu /> <span>AI settings</span></Link></SidebarMenuButton>
            </SidebarMenuItem>
          </SidebarMenu>
        </SidebarFooter>
      </Sidebar>
      <SidebarInset className="min-w-0">
        <header className="bg-background/80 sticky top-0 z-10 flex h-14 items-center gap-2 border-b px-4 backdrop-blur">
          <SidebarTrigger />
          <Separator orientation="vertical" className="mx-1 !h-4" />
          <Button variant="ghost" size="sm" asChild className="text-muted-foreground">
            <Link to="/"><ArrowLeft /> Projects</Link>
          </Button>
          <div className="min-w-0 truncate text-sm">
            <span className="font-medium">{project?.name ?? "…"}</span>
            {current && <span className="text-muted-foreground"> / {current.label}</span>}
          </div>
          <div className="ml-auto flex items-center gap-1">
            <Button variant="outline" size="sm" onClick={reanalyze} disabled={busy}>
              {busy ? <Loader2 className="animate-spin" /> : <RefreshCw />} Re-analyze
            </Button>
            <ThemeToggle />
          </div>
        </header>
        <div className="mx-auto w-full max-w-6xl p-6 md:p-10" key={version}>
          <Outlet context={{ pid, project: project ?? null, version, reanalyze } satisfies ProjectCtx} />
        </div>
      </SidebarInset>
    </SidebarProvider>
  )
}
