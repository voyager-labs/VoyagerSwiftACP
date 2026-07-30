import { useEffect, useRef, useState } from "react"
import type { FC, ReactNode } from "react"

/** Native sidebar min/max from FileManagerSidebarSync. */
const SIDEBAR_DEFAULT = 220
const SIDEBAR_MIN = 150
const SIDEBAR_MAX = 280
const INSPECTOR_DEFAULT = 300
const INSPECTOR_MIN = 230
const CONTENT_MIN = 400
const CONTENT_INSET = 4
const SPLIT_HANDLE_WIDTH = 5

const LS_SIDEBAR = "voyager.file-manager.sidebar-width.v1"
const LS_INSPECTOR = "voyager.file-manager.inspector-width.v1"

function loadClamped(key: string, fb: number, min: number, max: number): number {
  if (typeof window === "undefined") return fb
  const raw = window.localStorage.getItem(key)
  if (raw !== null) {
    const value = Number(raw)
    if (Number.isFinite(value)) return Math.max(min, Math.min(max, value))
  }
  return fb
}

function saveWidth(key: string, w: number): void {
  if (typeof window === "undefined") return
  window.localStorage.setItem(key, String(Math.round(w)))
}

function useSplitHandle(
  direction: "left" | "right",
  initial: number,
  min: number,
  max: number,
  lsKey: string,
  visible: boolean,
): [number, React.RefObject<HTMLDivElement | null>] {
  const [w, setW] = useState(initial)
  const ref = useRef<HTMLDivElement | null>(null)
  const wRef = useRef(w)
  wRef.current = w

  useEffect(() => {
    const clamped = Math.max(min, Math.min(max, wRef.current))
    if (clamped !== wRef.current) setW(clamped)
  }, [min, max])

  useEffect(() => {
    if (!visible) return
    const el = ref.current
    if (!el) return

    let removeDragListeners: (() => void) | null = null

    const onDown = (e: PointerEvent) => {
      e.preventDefault()
      el.setPointerCapture(e.pointerId)
      const startX = e.clientX
      const startW = wRef.current

      const onMove = (ev: PointerEvent) => {
        const delta = direction === "left" ? ev.clientX - startX : -(ev.clientX - startX)
        const next = Math.max(min, Math.min(max, startW + delta))
        setW(next)
      }

      const onUp = () => {
        saveWidth(lsKey, wRef.current)
        if (el.hasPointerCapture(e.pointerId)) el.releasePointerCapture(e.pointerId)
        removeDragListeners?.()
      }

      removeDragListeners?.()
      el.addEventListener("pointermove", onMove)
      el.addEventListener("pointerup", onUp)
      el.addEventListener("pointercancel", onUp)
      removeDragListeners = () => {
        el.removeEventListener("pointermove", onMove)
        el.removeEventListener("pointerup", onUp)
        el.removeEventListener("pointercancel", onUp)
        removeDragListeners = null
      }
    }

    const onKey = (e: KeyboardEvent) => {
      const step = e.shiftKey ? 20 : 5
      let next = wRef.current
      if (e.key === "ArrowLeft" && direction === "left") next = Math.max(min, next - step)
      if (e.key === "ArrowRight" && direction === "left") next = Math.min(max, next + step)
      if (e.key === "ArrowLeft" && direction === "right") next = Math.min(max, next + step)
      if (e.key === "ArrowRight" && direction === "right") next = Math.max(min, next - step)
      if (e.key === "Home") next = min
      if (e.key === "End") next = max
      if (next !== wRef.current) {
        e.preventDefault()
        setW(next)
        saveWidth(lsKey, next)
      }
    }

    el.addEventListener("pointerdown", onDown)
    el.addEventListener("keydown", onKey)
    return () => {
      removeDragListeners?.()
      el.removeEventListener("pointerdown", onDown)
      el.removeEventListener("keydown", onKey)
    }
  }, [visible, direction, min, max, lsKey])

  return [w, ref]
}

export interface FileManagerWindowLayoutProps {
  readonly sidebarOpen: boolean
  readonly inspectorOpen: boolean
  readonly sidebar: ReactNode
  readonly toolbar: ReactNode
  readonly breadcrumb: ReactNode
  readonly content: ReactNode
  readonly inspector: ReactNode
}

export const FileManagerWindowLayout: FC<FileManagerWindowLayoutProps> = ({
  sidebarOpen,
  inspectorOpen,
  sidebar,
  toolbar,
  breadcrumb,
  content,
  inspector,
}) => {
  const mainRef = useRef<HTMLDivElement | null>(null)
  const [mainWidth, setMainWidth] = useState(735)

  useEffect(() => {
    const main = mainRef.current
    if (!main || typeof ResizeObserver === "undefined") return
    const observer = new ResizeObserver(([entry]) => {
      if (entry) setMainWidth(entry.contentRect.width)
    })
    observer.observe(main)
    return () => observer.disconnect()
  }, [])

  const inspectorMax = Math.max(INSPECTOR_MIN, mainWidth - CONTENT_MIN - SPLIT_HANDLE_WIDTH)

  const [sW, sRef] = useSplitHandle(
    "left",
    loadClamped(LS_SIDEBAR, SIDEBAR_DEFAULT, SIDEBAR_MIN, SIDEBAR_MAX),
    SIDEBAR_MIN,
    SIDEBAR_MAX,
    LS_SIDEBAR,
    sidebarOpen,
  )
  const [iW, iRef] = useSplitHandle(
    "right",
    loadClamped(LS_INSPECTOR, INSPECTOR_DEFAULT, INSPECTOR_MIN, inspectorMax),
    INSPECTOR_MIN,
    inspectorMax,
    LS_INSPECTOR,
    inspectorOpen,
  )

  return (
    <div className="fm-window-layout">
      {sidebarOpen && (
        <div
          id="fm-sidebar-pane"
          className="fm-layout-sidebar"
          style={{ width: sW, minWidth: SIDEBAR_MIN }}
        >
          {sidebar}
        </div>
      )}
      {sidebarOpen && (
        <div
          className="fm-layout-split-handle"
          ref={sRef}
          role="separator"
          tabIndex={0}
          aria-orientation="vertical"
          aria-valuemin={SIDEBAR_MIN}
          aria-valuemax={SIDEBAR_MAX}
          aria-valuenow={sW}
          aria-valuetext={`${Math.round(sW)} pixels`}
          aria-controls="fm-sidebar-pane"
        />
      )}
      <div
        className="fm-layout-main"
        ref={mainRef}
        style={{
          marginTop: CONTENT_INSET,
          marginBottom: CONTENT_INSET,
          marginRight: CONTENT_INSET,
          marginLeft: sidebarOpen ? 0 : CONTENT_INSET,
          minWidth: CONTENT_MIN,
        }}
      >
        <div id="fm-content-pane" className="fm-layout-main-inner">
          <div className="fm-layout-toolbar-area">{toolbar}</div>
          <div className="fm-layout-content-area">{content}</div>
          <div className="fm-layout-breadcrumb-area">{breadcrumb}</div>
        </div>
        {inspectorOpen && (
          <div
            className="fm-layout-split-handle"
            ref={iRef}
            role="separator"
            tabIndex={0}
            aria-orientation="vertical"
            aria-valuemin={INSPECTOR_MIN}
            aria-valuemax={inspectorMax}
            aria-valuenow={iW}
            aria-valuetext={`${Math.round(iW)} pixels`}
            aria-controls="fm-inspector-pane"
          />
        )}
        {inspectorOpen && (
          <div
            id="fm-inspector-pane"
            className="fm-layout-inspector"
            style={{ width: iW, minWidth: INSPECTOR_MIN }}
          >
            {inspector}
          </div>
        )}
      </div>
    </div>
  )
}

FileManagerWindowLayout.displayName = "FileManagerWindowLayout"
