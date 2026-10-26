// Client for the DevMate FastAPI backend.
// Backend URL priority: ?api= in the link > /backend-url published by the Cloudflare Worker > saved > localhost.

const DEFAULT_URL = import.meta.env.VITE_API_URL ?? "http://localhost:8000"

let baseUrl = DEFAULT_URL
let token = ""

const store = {
  get: (k: string) => {
    try {
      return localStorage.getItem(k)
    } catch {
      return null
    }
  },
  set: (k: string, v: string) => {
    try {
      localStorage.setItem(k, v)
    } catch {
      /* private mode */
    }
  },
}

const clean = (u: string) => u.trim().replace(/\/+$/, "")

export async function initApi() {
  const q = new URLSearchParams(location.search)
  const fromQuery = q.get("api")
  if (fromQuery?.startsWith("http")) store.set("api_url", clean(fromQuery))
  if (q.has("token")) store.set("api_token", q.get("token") ?? "")
  if (q.has("api") || q.has("token")) history.replaceState(null, "", location.pathname) // keep the token out of the address bar

  baseUrl = store.get("api_url") ?? DEFAULT_URL
  token = store.get("api_token") ?? ""

  if (!fromQuery && location.protocol === "https:") {
    try {
      const r = await fetch("/backend-url", { cache: "no-store", signal: AbortSignal.timeout(4000) })
      const live = (await r.text()).trim()
      if (r.ok && live.startsWith("https://")) {
        baseUrl = clean(live)
        store.set("api_url", baseUrl)
      }
    } catch {
      /* offline or local dev */
    }
  }
}

export const getConfig = () => ({ baseUrl, token })

export function configure(url: string, newToken: string) {
  baseUrl = clean(url)
  token = newToken.trim()
  store.set("api_url", baseUrl)
  store.set("api_token", token)
}

export class ApiError extends Error {
  status: number
  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

function url(path: string, query?: Record<string, string | number | undefined>) {
  const u = new URL(`${baseUrl}/api${path}`)
  for (const [k, v] of Object.entries(query ?? {})) if (v !== undefined) u.searchParams.set(k, String(v))
  return u.toString()
}

const headers = (json = false): HeadersInit => ({
  ...(token ? { "X-DevMate-Token": token } : {}),
  ...(json ? { "Content-Type": "application/json" } : {}),
})

async function handle(r: Response) {
  if (!r.ok) {
    let msg = `HTTP ${r.status}`
    try {
      const j = await r.json()
      msg = typeof j.detail === "string" ? j.detail : JSON.stringify(j.detail)
    } catch {
      /* not JSON */
    }
    throw new ApiError(msg, r.status)
  }
  const ct = r.headers.get("content-type") ?? ""
  return ct.includes("json") ? r.json() : r.text()
}

export const api = {
  get: <T = any>(path: string, query?: Record<string, string | number | undefined>): Promise<T> =>
    fetch(url(path, query), { headers: headers() }).then(handle),
  post: <T = any>(path: string, body?: unknown, query?: Record<string, string | number | undefined>): Promise<T> =>
    fetch(url(path, query), { method: "POST", headers: headers(true), body: JSON.stringify(body ?? {}) }).then(handle),
  del: <T = any>(path: string): Promise<T> => fetch(url(path), { method: "DELETE", headers: headers() }).then(handle),
  text: (path: string, query?: Record<string, string>) => fetch(url(path, query), { headers: headers() }).then(handle) as Promise<string>,
  upload: (file: File) => {
    const fd = new FormData()
    fd.append("file", file)
    return fetch(url("/projects/upload"), { method: "POST", headers: headers(), body: fd }).then(handle)
  },
}

/** Triggers a real browser download (works on every browser, unlike file-picker plugins). */
export function saveBlob(blob: Blob, filename: string) {
  const a = document.createElement("a")
  a.href = URL.createObjectURL(blob)
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(a.href), 10_000)
}

export function saveText(text: string, filename: string, type = "text/markdown") {
  saveBlob(new Blob([text], { type: `${type};charset=utf-8` }), filename)
}

export async function download(path: string, filename: string, query?: Record<string, string>) {
  const r = await fetch(url(path, query), { headers: headers() })
  if (!r.ok) await handle(r)
  saveBlob(await r.blob(), filename)
}

// ---------------------------------------------------------------- types
export type Severity = "high" | "medium" | "low"
export interface Counts { high: number; medium: number; low: number }
export interface ProjectSummary {
  id: number
  name: string
  source: string
  status: string
  created_at: string
  summary: { files: number; lines: number; languages: Record<string, number>; classes: number; functions: number } | null
  health_score: number | null
  grade: string | null
  counts: Counts | null
  vulnerable_deps: number | null
  error: string | null
}
export interface Finding {
  tool: string
  rule: string
  severity: Severity
  category: "security" | "bug" | "smell"
  file: string
  line: number
  message: string
  owasp?: string
}
export interface Analysis {
  health_score: number
  code_score?: number
  grade: string
  counts: Counts
  by_category: { security: number; bug: number; smell: number }
  avg_complexity: number
  complex_functions: { file: string; function: string; line: number; complexity: number; nloc: number }[]
  findings: Finding[]
  tools: string[]
  duplication?: Duplication
}
export interface Duplication {
  blocks: { lines: number; occurrences: { file: string; start: number; end: number }[]; snippet: string }[]
  percentage: number
  duplicated_lines: number
}
export interface AiResult { markdown: string; ai: boolean; [k: string]: unknown }
