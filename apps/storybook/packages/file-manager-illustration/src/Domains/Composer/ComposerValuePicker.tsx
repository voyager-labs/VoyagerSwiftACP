import { type FC, useEffect, useRef, useState } from "react"
import { ComposerDateValuePicker } from "./ComposerDateValuePicker"
import { ComposerTokenValuePicker } from "./ComposerTokenValuePicker"
import type { ComposerValueEditor } from "./composer-condition-options"
import type { ComposerValuePicker as ComposerValuePickerFixture } from "./composer-fixtures"

export type ComposerValuePickerProps = {
  readonly picker: ComposerValuePickerFixture
  readonly onCommit?: (value: string) => void
}

const editorError = (
  editor: ComposerValueEditor,
  values: readonly string[],
): string | undefined => {
  if (editor.kind === "none") return undefined
  if (values.some((value) => value.trim().length === 0)) return "Value is required."
  if (
    (editor.kind === "number" || editor.kind === "numberRange") &&
    values.some((value) => Number.isNaN(Number(value)))
  ) {
    return editor.kind === "number" ? "Enter a valid number." : "Enter valid numbers."
  }
  if (editor.kind === "numberRange") {
    const [from, to] = values.map(Number)
    if (!Number.isNaN(from) && !Number.isNaN(to) && from > to) {
      return "From must be less than or equal to To."
    }
  }
  return undefined
}

export const ComposerValuePicker: FC<ComposerValuePickerProps> = ({ picker, onCommit }) => {
  const editor = picker.editor
  const fieldCount = editor.kind === "numberRange" ? 2 : 1
  const supportsUnit = editor.kind === "number" || editor.kind === "numberRange"
  const initial = picker.selectedValue?.trim() ?? ""
  const initialUnit = supportsUnit
    ? editor.units?.find((unit) => initial.endsWith(` ${unit}`))
    : undefined
  const initialBody = initialUnit == null ? initial : initial.slice(0, -initialUnit.length - 1)
  // 범위 구분자 분해는 numberRange 전용: 단일 값 editor는 원문 전체를 보존한다
  const initialParts =
    editor.kind === "numberRange"
      ? initialBody.length > 0
        ? initialBody.split(" - ")
        : []
      : initialBody.length > 0
        ? [initialBody]
        : []
  const [values, setValues] = useState<readonly string[]>(() =>
    Array.from({ length: fieldCount }, (_, index) => initialParts[index] ?? ""),
  )
  const [unit, setUnit] = useState(supportsUnit ? (initialUnit ?? editor.units?.[0]) : undefined)
  const [error, setError] = useState<string | undefined>(picker.error)
  const firstValueFieldRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    firstValueFieldRef.current?.focus()
  }, [])

  const setValue = (index: number, value: string) =>
    setValues((current) => current.map((item, itemIndex) => (itemIndex === index ? value : item)))

  const commit = (nextValues: readonly string[]) => {
    const nextError = editorError(editor, nextValues)
    setError(nextError)
    if (nextError != null) return
    onCommit?.(`${nextValues.join(" - ")}${unit == null ? "" : ` ${unit}`}`)
  }

  if (editor.kind === "boolean") {
    return <BooleanValuePicker picker={picker} onCommit={onCommit} />
  }

  if (editor.kind === "none") {
    return (
      <dialog
        className="collection-composer-value-picker form"
        open
        aria-label="Condition value picker"
      >
        <div className="collection-composer-value-form">
          <span>No value needed for this operator.</span>
          <button type="button" onClick={() => onCommit?.("")}>
            Apply
          </button>
        </div>
      </dialog>
    )
  }

  if (editor.kind === "list") {
    return (
      <ComposerTokenValuePicker
        suggestions={editor.suggestions}
        initialTokens={picker.selectedValue
          ?.split(",")
          .map((token) => token.trim())
          .filter((token) => token.length > 0)}
        error={error}
        onCommit={onCommit}
      />
    )
  }

  if (editor.kind === "date" || editor.kind === "dateRange") {
    return (
      <ComposerDateValuePicker
        kind={editor.kind}
        initialValue={picker.selectedValue}
        error={error}
        onCommit={onCommit}
      />
    )
  }

  const isRange = editor.kind === "numberRange"
  return (
    <dialog
      className="collection-composer-value-picker form"
      open
      aria-label="Condition value picker"
    >
      <form
        className="collection-composer-value-form"
        onSubmit={(event) => {
          event.preventDefault()
          commit(values)
        }}
      >
        <div className="collection-composer-value-fields">
          {values.map((value, index) => {
            const label = isRange
              ? index === 0
                ? "From"
                : "To"
              : editor.kind === "text"
                ? "Text"
                : "Number"
            return (
              <label key={label}>
                <span>{label}</span>
                <input
                  type="text"
                  inputMode={editor.kind === "text" ? "text" : "decimal"}
                  aria-label={isRange ? label : "Value"}
                  aria-invalid={error != null}
                  className={error != null ? "invalid" : undefined}
                  ref={index === 0 ? firstValueFieldRef : undefined}
                  placeholder={editor.kind === "text" ? "Enter text" : "0"}
                  value={value}
                  onChange={(event) => setValue(index, event.currentTarget.value)}
                />
              </label>
            )
          })}
        </div>
        {(editor.kind === "number" || editor.kind === "numberRange") && editor.units != null && (
          <label>
            <span>Unit</span>
            <select value={unit} onChange={(event) => setUnit(event.currentTarget.value)}>
              {editor.units.map((option) => (
                <option key={option}>{option}</option>
              ))}
            </select>
          </label>
        )}
        {error != null && <output className="collection-composer-value-error">{error}</output>}
        <button type="submit">Apply</button>
      </form>
    </dialog>
  )
}

ComposerValuePicker.displayName = "ComposerValuePicker"

const BooleanValuePicker: FC<{
  readonly picker: ComposerValuePickerFixture
  readonly onCommit?: (value: string) => void
}> = ({ picker, onCommit }) => {
  const [value, setValue] = useState(picker.selectedValue)
  const firstOptionRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    firstOptionRef.current?.focus()
  }, [])

  return (
    <dialog
      className="collection-composer-value-picker boolean"
      open
      aria-label="Condition value picker"
    >
      <div className="collection-composer-picker-list">
        {(["True", "False"] as const).map((option) => (
          <button
            type="button"
            ref={option === (value === "False" ? "False" : "True") ? firstOptionRef : undefined}
            aria-pressed={value === option}
            key={option}
            onClick={() => {
              setValue(option)
              onCommit?.(option)
            }}
          >
            {option}
          </button>
        ))}
      </div>
    </dialog>
  )
}
