import { useEffect, useState } from "react"
import type { FC } from "react"

// AiChatWaitingIndicator 번역 — 0.4s 주기로 "."/".."/"..." 순환, reduce-motion 시 정지.
// 원본: TimelineView(.periodic(0.4)), 13pt semibold secondary, a11y "Waiting for assistant response".

export const AiChatWaitingIndicator: FC = () => {
  const reduceMotion =
    typeof window !== "undefined" &&
    typeof window.matchMedia === "function" &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches
  const [step, setStep] = useState(0)

  useEffect(() => {
    if (reduceMotion) return
    const id = window.setInterval(() => {
      setStep((prev) => (prev + 1) % 3)
    }, 400)
    return () => window.clearInterval(id)
  }, [reduceMotion])

  const dots = ".".repeat((reduceMotion ? 2 : step) + 1)
  return (
    <span className="chat-waiting" aria-label="Waiting for assistant response">
      {dots}
    </span>
  )
}

AiChatWaitingIndicator.displayName = "AiChatWaitingIndicator"
