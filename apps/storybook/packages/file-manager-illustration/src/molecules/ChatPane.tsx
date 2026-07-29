import type { FC, FormEvent } from "react"
import { IconButton } from "../atoms/IconButton"
import type { Entry } from "../model/types"

export interface ChatPaneProps {
  readonly requestText: string
  readonly selectedEntries: readonly Entry[]
  readonly primaryEntry: Entry | null
  onRequestTextChange: (value: string) => void
}

export const ChatPane: FC<ChatPaneProps> = ({
  requestText,
  selectedEntries,
  primaryEntry,
  onRequestTextChange,
}) => {
  function handleInput(event: FormEvent<HTMLTextAreaElement>) {
    onRequestTextChange(event.currentTarget.value)
  }

  return (
    <section className="vc-chat-pane">
      <div className="vc-quiet-card">
        <span className="vc-eyebrow">Selected Entries</span>
        <strong>{selectedEntries.length} selected</strong>
        {primaryEntry != null ? (
          <p>{primaryEntry.name}</p>
        ) : (
          <p className="vc-empty-text">No files to inspect</p>
        )}
      </div>
      <label className="vc-composer">
        <textarea rows={5} placeholder="Ask anything…" value={requestText} onInput={handleInput} />
        <span className="vc-composer-footer">
          <span>＋</span>
          <em>GPT-5.2</em>
          <IconButton aria-label="Send">↑</IconButton>
        </span>
      </label>
    </section>
  )
}

ChatPane.displayName = "ChatPane"
