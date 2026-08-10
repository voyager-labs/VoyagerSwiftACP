import type { ChangeEvent, FC } from "react"
import { SFSymbol } from "../Foundations/SFSymbol"
import { IconButton } from "../UI/Controls/IconButton"
import type { InspectorChatInputProps } from "../model/types"

export const InspectorChatInput: FC<InspectorChatInputProps> = ({
  requestText,
  onRequestTextChange,
}) => {
  function handleInput(event: ChangeEvent<HTMLTextAreaElement>) {
    onRequestTextChange(event.currentTarget.value)
  }

  return (
    <label className="fm-composer">
      <textarea value={requestText} onChange={handleInput} rows={5} placeholder="Ask anything…" />
      <span className="composer-footer">
        <SFSymbol name="plus" size={16} />
        <em>GPT-5.2</em>
        <IconButton aria-label="Send">
          <SFSymbol name="arrow.up" size={16} />
        </IconButton>
      </span>
    </label>
  )
}

InspectorChatInput.displayName = "InspectorChatInput"
