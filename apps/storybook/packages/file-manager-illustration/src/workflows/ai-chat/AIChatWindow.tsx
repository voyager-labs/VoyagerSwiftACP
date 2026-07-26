import type { FC } from "react"
import { Button } from "../../Button"
import type { AiChatState } from "./types"

export interface AIChatWindowProps {
  readonly state: AiChatState
  /**
   * Presentation mode:
   * - "standalone" — full-stage window with sidebar (default, preserves existing stories)
   * - "content" — primary-content mode, omits stage/window/session-sidebar wrappers
   */
  readonly presentation?: "standalone" | "content"
}

const modelStateLabel: Record<AiChatState["modelState"], string> = {
  loading: "Loading models",
  loaded: "Ready",
  empty: "Connect provider",
  failed: "Model load failed",
  locked: "Locked during run",
  unavailable: "Unavailable",
}

export const AIChatWindow: FC<AIChatWindowProps> = ({ state, presentation = "standalone" }) => {
  /* Content presentation: render only the chat main area, no wrappers */
  if (presentation === "content") {
    return (
      <section
        className="ai-chat-content"
        aria-label="AI Chat"
        data-file-manager-illustration-workflow="ai-chat-content"
      >
        <section className="ai-message-list vc-scroll">
          {state.failure && (
            <div className="ai-chat-message assistant">
              <small>Execution failed</small>
              <p>{state.failure}</p>
            </div>
          )}
          {state.messages.length === 0 && !state.failure && (
            <div className="ai-chat-message assistant">
              <small>Voyager AI</small>
              <p>Connect an AI provider or select files to start a contextual chat.</p>
            </div>
          )}
          {state.messages.map((message) => (
            <article key={message.id} className={`ai-chat-message ${message.author}`}>
              <small>{message.meta}</small>
              <p>{message.text}</p>
            </article>
          ))}
          {state.streamingText && (
            <article className="ai-chat-message assistant">
              <small>Streaming…</small>
              <p>{state.streamingText}</p>
            </article>
          )}
        </section>

        <footer className="ai-chat-input">
          <input
            className="vc-form-field"
            defaultValue={state.draftText}
            placeholder="Ask Voyager about your files…"
            readOnly
          />
          <Button disabled={state.modelState === "empty"}>Send</Button>
        </footer>
      </section>
    )
  }

  /* Standalone presentation — original full view */
  return (
    <section className="vc-stage" data-file-manager-illustration-workflow="ai-chat">
      <div className="ai-chat-window vc-window">
        <aside className="ai-chat-sidebar">
          <div>
            <div className="vc-eyebrow">AI Chat</div>
            <h2>Sessions</h2>
          </div>
          <input
            className="vc-form-field"
            defaultValue={state.mode === "sessions" ? "collection" : ""}
            placeholder="Search sessions"
            readOnly
          />
          <div className="vc-list vc-scroll">
            {state.sessions.map((session) => (
              <div
                key={session.id}
                className={`ai-session-row vc-row${session.id === state.selectedSessionId ? " selected" : ""}`}
              >
                <div>
                  <strong>{session.title}</strong>
                  <br />
                  <small>{session.meta}</small>
                </div>
                <span className="vc-chip muted">{session.status}</span>
              </div>
            ))}
          </div>
        </aside>

        <main className="ai-chat-main">
          <header className="ai-chat-topbar">
            <div>
              <div className="vc-eyebrow">Conversation</div>
              <h1>{state.selectedSessionId ? "Review collection PDFs" : "New chat"}</h1>
            </div>
            <div className="ai-model-stack">
              <span className="vc-chip">{state.selectedModel}</span>
              <span className={`vc-chip${state.modelState === "locked" ? " accent" : ""}`}>
                {modelStateLabel[state.modelState]}
              </span>
            </div>
          </header>

          <section className="ai-context-card vc-panel">
            <div>
              <strong>{state.contextSummary}</strong>
              <br />
              <small>
                {state.contextCount} context item{state.contextCount === 1 ? "" : "s"}
              </small>
            </div>
            <div className="ai-model-stack">
              {state.attachments.map((attachment) => (
                <span
                  key={attachment.id}
                  className={`vc-chip${attachment.status === "resolved" ? " accent" : ""}`}
                >
                  {attachment.label} · {attachment.status}
                </span>
              ))}
            </div>
          </section>

          <section className="ai-message-list vc-scroll">
            {state.failure && (
              <div className="ai-chat-message assistant">
                <small>Execution failed</small>
                <p>{state.failure}</p>
              </div>
            )}
            {state.messages.length === 0 && !state.failure && (
              <div className="ai-chat-message assistant">
                <small>Voyager AI</small>
                <p>Connect an AI provider or select files to start a contextual chat.</p>
              </div>
            )}
            {state.messages.map((message) => (
              <article key={message.id} className={`ai-chat-message ${message.author}`}>
                <small>{message.meta}</small>
                <p>{message.text}</p>
              </article>
            ))}
            {state.streamingText && (
              <article className="ai-chat-message assistant">
                <small>Streaming…</small>
                <p>{state.streamingText}</p>
              </article>
            )}
          </section>

          <footer className="ai-chat-input">
            <input
              className="vc-form-field"
              defaultValue={state.draftText}
              placeholder="Ask Voyager about your files…"
              readOnly
            />
            <Button disabled={state.modelState === "empty"}>Send</Button>
          </footer>
        </main>
      </div>
    </section>
  )
}

AIChatWindow.displayName = "AIChatWindow"
