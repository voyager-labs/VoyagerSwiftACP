import { type FC, useEffect, useRef, useState } from "react"

export type ComposerTokenValuePickerProps = {
  readonly suggestions?: readonly string[]
  readonly initialTokens?: readonly string[]
  readonly error?: string
  readonly onCommit?: (value: string) => void
}

export const ComposerTokenValuePicker: FC<ComposerTokenValuePickerProps> = ({
  suggestions,
  initialTokens,
  error: initialError,
  onCommit,
}) => {
  const [input, setInput] = useState("")
  const [tokens, setTokens] = useState<readonly string[]>(initialTokens ?? [])
  const [error, setError] = useState<string | undefined>(initialError)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    inputRef.current?.focus()
  }, [])

  const normalizedInput = input.trim().toLowerCase()
  const filteredSuggestions =
    suggestions?.filter(
      (suggestion) =>
        !tokens.some((token) => token.toLowerCase() === suggestion.toLowerCase()) &&
        (normalizedInput.length === 0 || suggestion.toLowerCase().includes(normalizedInput)),
    ) ?? []

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

  const removeToken = (token: string) => {
    setTokens((current) => current.filter((item) => item !== token))
    setError(undefined)
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
          onCommit?.(tokens.join("; "))
        }}
      >
        <div className="collection-composer-token-field">
          {tokens.map((token) => (
            <button
              type="button"
              key={token}
              aria-label={`Remove ${token}`}
              onClick={() => removeToken(token)}
            >
              {token} <span aria-hidden="true">×</span>
            </button>
          ))}
          <input
            aria-label="Value"
            ref={inputRef}
            placeholder="Value"
            value={input}
            onChange={(event) => setInput(event.currentTarget.value)}
          />
        </div>
        {suggestions != null && (
          <div className="collection-composer-token-suggestions">
            {filteredSuggestions.map((suggestion) => (
              <button type="button" key={suggestion} onClick={() => addToken(suggestion)}>
                {suggestion}
              </button>
            ))}
            {suggestions.length === 0 && (
              <small className="collection-composer-token-suggestions-empty">No tags</small>
            )}
            {suggestions.length > 0 &&
              normalizedInput.length > 0 &&
              filteredSuggestions.length === 0 && (
                <small className="collection-composer-token-suggestions-empty">
                  No matching tags
                </small>
              )}
          </div>
        )}
        {error != null && <output className="collection-composer-value-error">{error}</output>}
      </form>
    </dialog>
  )
}

ComposerTokenValuePicker.displayName = "ComposerTokenValuePicker"
