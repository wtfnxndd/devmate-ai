import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { MotionConfig } from "motion/react"
import { ThemeProvider } from "next-themes"

import App from "./App"
import { Toaster } from "@/components/ui/sonner"
import { initApi } from "@/lib/api"
// Fonts are bundled (no external stylesheet that could block startup on slow networks).
import "@fontsource-variable/inter"
import "@fontsource-variable/jetbrains-mono"
import "./index.css"

initApi().finally(() => {
  createRoot(document.getElementById("root")!).render(
    <StrictMode>
      <ThemeProvider attribute="class" defaultTheme="light" enableSystem disableTransitionOnChange>
        <MotionConfig reducedMotion="user">
          <App />
        </MotionConfig>
        <Toaster position="bottom-right" />
      </ThemeProvider>
    </StrictMode>,
  )
})
