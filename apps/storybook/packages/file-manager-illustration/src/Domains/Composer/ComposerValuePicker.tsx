import { type FC, useState } from "react"
import { ComposerTokenValuePicker } from "./ComposerTokenValuePicker"
import type { ComposerValueEditor } from "./composer-condition-options"
import type { ComposerValuePicker as ComposerValuePickerFixture } from "./composer-fixtures"

export type ComposerValuePickerProps = {
  readonly picker: ComposerValuePickerFixture
  readonly onCommit?: (value: string) => void
}

const relativePresets = [
  "Custom",
  "Today",
  "Yesterday",
  "7 days ago",
  "30 days ago",
  "3 months ago",
  "1 year ago",
] as const

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
  return undefined
}

export const ComposerValuePicker: FC<ComposerValuePickerProps> = ({ picker, onCommit }) => {
  const editor = picker.editor
  const fieldCount = editor.kind === "numberRange" || editor.kind === "dateRange" ? 2 : 1
  const [values, setValues] = useState<readonly string[]>(
    Array.from({ length: fieldCount }, () => ""),
  )
  const [unit, setUnit] = useState(
    editor.kind === "number" || editor.kind === "numberRange" ? editor.units?.[0] : undefined,
  )
  const [dateMode, setDateMode] = useState<"absolute" | "relative">("absolute")
  const [relativePreset, setRelativePreset] =
    useState<(typeof relativePresets)[number]>("7 days ago")
  const [relativeAmount, setRelativeAmount] = useState("1")
  const [relativeUnit, setRelativeUnit] = useState("Day")
  const [error, setError] = useState<string | undefined>(picker.error)

  const setValue = (index: number, value: string) =>
    setValues((current) => current.map((item, itemIndex) => (itemIndex === index ? value : item)))

  const commit = (nextValues: readonly string[]) => {
    const nextError = editorError(editor, nextValues)
    setError(nextError)
    if (nextError != null) return
    onCommit?.(`${nextValues.join(" - ")}${unit == null ? "" : ` ${unit}`}`)
  }

  if (editor.kind === "boolean") {
    return (
      <dialog
        className="collection-composer-value-picker boolean"
        open
        aria-label="Condition value picker"
      >
        <div className="collection-composer-picker-list">
          {(["True", "False"] as const).map((value) => (
            <button type="button" key={value} onClick={() => onCommit?.(value)}>
              {value}
            </button>
          ))}
        </div>
      </dialog>
    )
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
        error={error}
        onCommit={onCommit}
      />
    )
  }

  const isDate = editor.kind === "date" || editor.kind === "dateRange"
  const isRange = editor.kind === "numberRange" || editor.kind === "dateRange"
  return (
    <dialog
      className={`collection-composer-value-picker form ${isDate ? "date" : ""}`}
      open
      aria-label="Condition value picker"
    >
      <form
        className="collection-composer-value-form"
        onSubmit={(event) => {
          event.preventDefault()
          commit(
            editor.kind === "date" && dateMode === "relative"
              ? [
                  relativePreset === "Custom"
                    ? `${relativeAmount} ${relativeUnit.toLowerCase()}${relativeAmount === "1" ? "" : "s"} ago`
                    : relativePreset,
                ]
              : values,
          )
        }}
      >
        {editor.kind === "date" && (
          <label>
            <span>Date Type</span>
            <select
              value={dateMode}
              onChange={(event) =>
                setDateMode(event.currentTarget.value === "relative" ? "relative" : "absolute")
              }
            >
              <option value="absolute">On date</option>
              <option value="relative">Relative</option>
            </select>
          </label>
        )}
        {editor.kind === "date" && dateMode === "relative" ? (
          <>
            <label>
              <span>Preset</span>
              <select
                value={relativePreset}
                onChange={(event) =>
                  setRelativePreset(event.currentTarget.value as (typeof relativePresets)[number])
                }
              >
                {relativePresets.map((preset) => (
                  <option key={preset}>{preset}</option>
                ))}
              </select>
            </label>
            {relativePreset === "Custom" && (
              <div className="collection-composer-relative-custom">
                <input
                  aria-label="Amount"
                  inputMode="numeric"
                  placeholder="1"
                  value={relativeAmount}
                  onChange={(event) => setRelativeAmount(event.currentTarget.value)}
                />
                <select
                  aria-label="Relative unit"
                  value={relativeUnit}
                  onChange={(event) => setRelativeUnit(event.currentTarget.value)}
                >
                  <option>Day</option>
                  <option>Week</option>
                  <option>Month</option>
                  <option>Year</option>
                </select>
              </div>
            )}
            <small>Preview based on today</small>
          </>
        ) : (
          <div className="collection-composer-value-fields">
            {values.map((value, index) => {
              const label = isRange
                ? index === 0
                  ? "From"
                  : "To"
                : isDate
                  ? "Date"
                  : editor.kind === "text"
                    ? "Text"
                    : "Number"
              return (
                <label key={label}>
                  <span>{label}</span>
                  <input
                    type={isDate ? "date" : "text"}
                    inputMode={editor.kind === "text" ? "text" : "decimal"}
                    aria-label={isRange ? label : "Value"}
                    value={value}
                    onChange={(event) => setValue(index, event.currentTarget.value)}
                  />
                </label>
              )
            })}
          </div>
        )}
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
