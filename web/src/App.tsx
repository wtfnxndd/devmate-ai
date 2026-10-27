import { lazy, Suspense } from "react"
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom"

import { Loading } from "@/components/devmate"
import Home from "@/pages/Home"
import ProjectLayout from "@/pages/ProjectLayout"

// Each screen is its own chunk, so the first page loads fast.
const Dashboard = lazy(() => import("@/pages/Dashboard"))
const Findings = lazy(() => import("@/pages/Findings"))
const Dependencies = lazy(() => import("@/pages/Dependencies"))
const Files = lazy(() => import("@/pages/Files"))
const Architecture = lazy(() => import("@/pages/Architecture"))
const Assist = lazy(() => import("@/pages/Assist"))
const Chat = lazy(() => import("@/pages/Chat"))
const Fix = lazy(() => import("@/pages/Fix"))
const Duplication = lazy(() => import("@/pages/Duplication"))
const Compare = lazy(() => import("@/pages/Compare"))
const AiSettings = lazy(() => import("@/pages/AiSettings"))
const Security = lazy(() => import("@/pages/Security"))
const Hotspots = lazy(() => import("@/pages/Hotspots"))
const Agent = lazy(() => import("@/pages/Agent"))

export default function App() {
  return (
    <BrowserRouter>
      <Suspense fallback={<div className="p-10"><Loading /></div>}>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/ai" element={<AiSettings />} />
          <Route path="/p/:pid" element={<ProjectLayout />}>
            <Route index element={<Dashboard />} />
            <Route path="findings" element={<Findings />} />
            <Route path="security" element={<Security />} />
            <Route path="hotspots" element={<Hotspots />} />
            <Route path="agent" element={<Agent />} />
            <Route path="dependencies" element={<Dependencies />} />
            <Route path="files" element={<Files />} />
            <Route path="architecture" element={<Architecture />} />
            <Route path="review" element={<Assist kind="review" />} />
            <Route path="docs" element={<Assist kind="docs" />} />
            <Route path="tests" element={<Assist kind="tests" />} />
            <Route path="debug" element={<Assist kind="debug" />} />
            <Route path="report" element={<Assist kind="report" />} />
            <Route path="chat" element={<Chat />} />
            <Route path="fix" element={<Fix />} />
            <Route path="duplication" element={<Duplication />} />
            <Route path="compare" element={<Compare />} />
          </Route>
          <Route path="*" element={<Navigate to="/" />} />
        </Routes>
      </Suspense>
    </BrowserRouter>
  )
}
