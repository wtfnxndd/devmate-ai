import { useEffect, useState } from "react"
import { ArrowUp, MessagesSquare } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Conversation, ConversationContent, ConversationEmptyState, ConversationScrollButton } from "@/components/ui/conversation"
import { Message, MessageContent } from "@/components/ui/message"
import { Response } from "@/components/ui/response"
import { ShimmeringText } from "@/components/ui/shimmering-text"
import { Textarea } from "@/components/ui/textarea"
import { api, streamAi } from "@/lib/api"
import { ProviderBadge } from "@/components/devmate"
import { useProject } from "@/pages/ProjectLayout"

interface Msg { role: "user" | "assistant"; content: string; sources?: string; provider?: string }

const SUGGESTIONS = ["Give me an overview of this codebase", "Where is the main entry point?", "Which parts are risky to change?", "How is data stored?"]

export default function Chat() {
  const { pid } = useProject()
  const [msgs, setMsgs] = useState<Msg[]>([])
  const [input, setInput] = useState("")
  const [sending, setSending] = useState(false)
  const [live, setLive] = useState("")
  const [provider, setProvider] = useState<string | null>(null)

  useEffect(() => {
    api.get<Msg[]>(`/projects/${pid}/chat`).then(setMsgs).catch(() => {})
  }, [pid])

  const send = async (text = input) => {
    const t = text.trim()
    if (!t || sending) return
    setInput("")
    setMsgs((m) => [...m, { role: "user", content: t }])
    setSending(true)
    setLive("")
    setProvider(null)
    let used: string | null = null
    try {
      const r = await streamAi(pid, "chat", { message: t }, { onText: setLive, onProvider: (p) => { used = p; setProvider(p) } })
      const sources = (r.sources as any[]).map((s) => `\`${s.file}:${s.start}\``).join(" · ")
      setMsgs((m) => [...m, { role: "assistant", content: r.markdown, sources, provider: used ?? undefined }])
    } catch (e) {
      setMsgs((m) => [...m, { role: "assistant", content: `Error: ${(e as Error).message}` }])
    } finally {
      setSending(false)
      setLive("")
    }
  }

  return (
    <Card className="flex h-[calc(100vh-10rem)] flex-col gap-0 overflow-hidden p-0 shadow-none">
      <Conversation className="flex-1">
        <ConversationContent className="mx-auto w-full max-w-3xl">
          {msgs.length === 0 ? (
            <ConversationEmptyState
              icon={<MessagesSquare className="size-10" />}
              title="Ask anything about this codebase"
              description="Answers use the most relevant code, found with retrieval (RAG)."
            >
              <div className="flex flex-col items-center gap-4">
                <MessagesSquare className="text-muted-foreground size-10" />
                <div className="text-center">
                  <h3 className="font-medium">Ask anything about this codebase</h3>
                  <p className="text-muted-foreground text-sm">Answers use the most relevant code, found with retrieval (RAG).</p>
                </div>
                <div className="flex flex-wrap justify-center gap-2">
                  {SUGGESTIONS.map((s) => (
                    <Button key={s} variant="outline" size="sm" className="rounded-full" onClick={() => send(s)}>{s}</Button>
                  ))}
                </div>
              </div>
            </ConversationEmptyState>
          ) : (
            msgs.map((m, i) => (
              <Message key={i} from={m.role}>
                <MessageContent variant={m.role === "user" ? "contained" : "flat"}>
                  {m.role === "user" ? m.content : <Response>{m.content}</Response>}
                  {(m.sources || m.provider) && (
                    <div className="text-muted-foreground flex flex-wrap items-center gap-2 border-t pt-2 text-xs">
                      <ProviderBadge provider={m.provider} />
                      {m.sources && <span className="flex flex-wrap gap-1">Sources: <Response>{m.sources}</Response></span>}
                    </div>
                  )}
                </MessageContent>
              </Message>
            ))
          )}
          {sending && (
            <Message from="assistant">
              <MessageContent variant="flat">
                {live ? <Response>{live}</Response> : (
                  <ShimmeringText text={provider?.startsWith("local:") ? "Running on your computer…" : "Reading your code…"} />
                )}
                {provider && <div><ProviderBadge provider={provider} /></div>}
              </MessageContent>
            </Message>
          )}
        </ConversationContent>
        <ConversationScrollButton />
      </Conversation>
      <form
        className="mx-auto w-full max-w-3xl p-4"
        onSubmit={(e) => {
          e.preventDefault()
          send()
        }}
      >
        <div className="bg-background flex items-end gap-2 rounded-2xl border p-2 shadow-sm">
          <Textarea
            rows={1}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault()
                send()
              }
            }}
            placeholder="Ask about the code…"
            className="max-h-40 min-h-9 resize-none border-0 shadow-none focus-visible:ring-0 dark:bg-transparent"
          />
          <Button type="submit" size="icon" className="shrink-0 rounded-full" disabled={sending || !input.trim()}><ArrowUp /></Button>
        </div>
      </form>
    </Card>
  )
}
