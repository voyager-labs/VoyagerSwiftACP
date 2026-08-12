import { type FC, useState } from "react"

export type ComposerTokenValuePickerProps = {
  readonly suggestions?: readonly string[]
  readonly error?: string
  readonly onCommit?: (value: string) => void
}

export const ComposerTokenValuePicker: FC<ComposerTokenValuePickerProps> = ({
  suggestions,
  error: initialError,
  onCommit,
}) => {
  const [input, setInput] = useState("")
  const [tokens, setTokens] = useState<readonly string[]>([])
  const [error, setError] = useState<string | undefined>(initialError)
  const addToken = (token: string) => {
    const normalized = token.trim()
    if (normalized.length === 0) return
    setTokens((current) =>
      current.some((item) => item.toLowerCase() === normalized.toLowerCase())
        ? current
        : [...current, normalized],
    )
    setInput("")
  }

  return (
    <dialog
      className="collection-composer-value-picker list"
      open
      aria-label="Condition value picker"
    >
      <form
        className="collection-composer-value-form"
        onSubmit={(event) => {
          event.preventDefault()
          if (input.trim().length > 0) return addToken(input)
          if (tokens.length === 0) return setError("Value is required.")
          onCommit?.(tokens.join(", "))
        }}
      >
        <div className="collection-composer-token-field">
          {tokens.map((token) => (
            <button
              type="button"
              key={token}
              onClick={() => setTokens((current) => current.filter((item) => item !== token))}
            >
              {token} ×
            </button>
          ))}
          <input
            aria-label="Value"
            placeholder="Value"
            value={input}
            onChange={(event) => setInput(event.currentTarget.value)}
          />
        </div>
        <div className="collection-composer-token-suggestions">
          {suggestions?.map((suggestion) => (
            <button type="button" key={suggestion} onClick={() => addToken(suggestion)}>
              {suggestion}
            </button>
          ))}
        </div>
        {error != null && <output className="collection-composer-value-error">{error}</output>}
        <small>Press Enter to add. Press Enter again to apply.</small>
      </form>
    </dialog>
  )
}

ComposerTokenValuePicker.displayName = "ComposerTokenValuePicker"
