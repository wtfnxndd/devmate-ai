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

  await discoverBackend()
}

/** On the hosted site, the launcher publishes the backend's current tunnel URL at /backend-url.
 *  It always wins over saved or link-provided addresses, which go stale whenever the tunnel restarts. */
export async function discoverBackend() {
  if (location.protocol === "https:") {
    try {
      const r = await fetch("/backend-url", { cache: "no-store", signal: AbortSignal.timeout(8000) })
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
  put: <T = any>(path: string, body?: unknown): Promise<T> =>
    fetch(url(path), { method: "PUT", headers: headers(true), body: JSON.stringify(body ?? {}) }).then(handle),
  del: <T = any>(path: string): Promise<T> => fetch(url(path), { method: "DELETE", headers: headers() }).then(handle),
  text: (path: string, query?: Record<string, string>) => fetch(url(path, query), { headers: headers() }).then(handle) as Promise<string>,
  upload: (file: File) => {
    const fd = new FormData()
    fd.append("file", file)
    return fetch(url("/projects/upload"), { method: "POST", headers: headers(), body: fd }).then(handle)
  },
}

export type StreamEvent =
  | { type: "provider"; data: string }
  | { type: "delta"; data: string }
  | { type: "reset"; data: null }
  | { type: "done"; data: any }
  | { type: "error"; data: string }

/** Reads a Server-Sent Events response (POST, with token) and calls onEvent for each event. */
export async function readSSE(path: string, body: unknown, onEvent: (e: any) => void, signal?: AbortSignal) {
  const r = await fetch(url(path), { method: "POST", headers: headers(true), body: JSON.stringify(body ?? {}), signal })
  if (!r.ok || !r.body) await handle(r)
  const reader = r.body!.getReader()
  const dec = new TextDecoder()
  let buf = ""
  for (;;) {
    const { value, done } = await reader.read()
    if (done) break
    buf += dec.decode(value, { stream: true })
    let i
    while ((i = buf.indexOf("\n\n")) >= 0) {
      const chunk = buf.slice(0, i)
      buf = buf.slice(i + 2)
      const line = chunk.split("\n").find((l) => l.startsWith("data: "))
      if (line) {
        try {
          onEvent(JSON.parse(line.slice(6)))
        } catch {
          /* ignore partial */
        }
      }
    }
  }
}

/** Runs an AI feature with live streaming. Resolves with the final result. */
export async function streamAi(pid: number, kind: string, body: unknown, handlers: {
  onText?: (fullText: string) => void
  onProvider?: (name: string) => void
}, opts: { refresh?: boolean; signal?: AbortSignal } = {}): Promise<any> {
  let text = ""
  let result: any = null
  let error: string | null = null
  await readSSE(`/projects/${pid}/stream/${kind}${opts.refresh ? "?refresh=true" : ""}`, body, (e: StreamEvent) => {
    if (e.type === "provider") handlers.onProvider?.(e.data)
    else if (e.type === "delta") { text += e.data; handlers.onText?.(text) }
    else if (e.type === "reset") { text = ""; handlers.onText?.("") }
    else if (e.type === "done") result = e.data
    else if (e.type === "error") error = String((e as { data: unknown }).data)
  }, opts.signal)
  if (error) throw new ApiError(error, 500)
  return result
}

/** Pretty label for a provider id like "local:qwen2.5-coder:3b" or "groq:openai/gpt-oss-120b". */
export function providerLabel(p?: string | null) {
  if (!p) return ""
  const cached = p.endsWith("(cached)")
  const base = p.replace(" (cached)", "")
  const [kind, ...rest] = base.split(":")
  const model = rest.join(":").split("/").pop()
  const name = kind === "local" ? "Local" : kind === "groq" ? "Groq" : kind === "gemini" ? "Gemini" : kind
  return `${name} · ${model}${cached ? " · cached" : ""}`
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
