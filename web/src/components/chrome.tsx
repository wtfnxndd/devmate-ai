import { useState } from "react"
import { Moon, Settings2, Sun } from "lucide-react"
import { useTheme } from "next-themes"

import { Button } from "@/components/ui/button"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { configure, getConfig } from "@/lib/api"

export function Logo({ className = "" }: { className?: string }) {
  return (
    <span className={`inline-flex items-center gap-2 font-semibold tracking-tight ${className}`}>
      <span className="bg-foreground text-background grid size-7 place-items-center rounded-lg">
        <svg viewBox="0 0 16 16" className="size-3.5" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
          <path d="M4 3v10M8 3v10M12 3v10" />
        </svg>
      </span>
      DevMate
    </span>
  )
}

export function ThemeToggle() {
  const { resolvedTheme, setTheme } = useTheme()
  return (
    <Button variant="ghost" size="icon" aria-label="Toggle theme" onClick={() => setTheme(resolvedTheme === "dark" ? "light" : "dark")}>
      {resolvedTheme === "dark" ? <Sun /> : <Moon />}
    </Button>
  )
}

export function BackendSettings({ onSaved }: { onSaved?: () => void }) {
  const cfg = getConfig()
  const [open, setOpen] = useState(false)
  const [url, setUrl] = useState(cfg.baseUrl)
  const [token, setToken] = useState(cfg.token)
  return (
    <Dialog open={open} onOpenChange={(o) => { setOpen(o); if (o) { setUrl(getConfig().baseUrl); setToken(getConfig().token) } }}>
      <DialogTrigger asChild>
        <Button variant="ghost" size="icon" aria-label="Backend settings"><Settings2 /></Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Backend connection</DialogTitle>
          <DialogDescription>
            Where the DevMate API runs. On the hosted site this is found automatically while DevMate Online is running.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="url">URL</Label>
            <Input id="url" value={url} onChange={(e) => setUrl(e.target.value)} placeholder="http://localhost:8000" />
          </div>
          <div className="space-y-2">
            <Label htmlFor="token">Access token</Label>
            <Input id="token" type="password" value={token} onChange={(e) => setToken(e.target.value)} placeholder="Only needed for the online server" />
          </div>
        </div>
        <DialogFooter>
          <Button onClick={() => { configure(url, token); setOpen(false); onSaved?.() }}>Save</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
