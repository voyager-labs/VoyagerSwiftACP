import { type FC, useState } from "react"

const relativePresets = [
  "Custom",
  "Today",
  "Yesterday",
  "7 days ago",
  "30 days ago",
  "3 months ago",
  "1 year ago",
] as const

export type ComposerDateValuePickerProps = {
  readonly kind: "date" | "dateRange"
  readonly error?: string
  readonly onCommit?: (value: string) => void
}

export const ComposerDateValuePicker: FC<ComposerDateValuePickerProps> = ({
  kind,
  error: initialError,
  onCommit,
}) => {
  const isRange = kind === "dateRange"
  const [values, setValues] = useState<readonly string[]>(isRange ? ["", ""] : [""])
  const [dateMode, setDateMode] = useState<"absolute" | "relative">("absolute")
  const [relativePreset, setRelativePreset] =
    useState<(typeof relativePresets)[number]>("7 days ago")
  const [relativeAmount, setRelativeAmount] = useState("1")
  const [relativeUnit, setRelativeUnit] = useState("Day")
  const [error, setError] = useState<string | undefined>(initialError)

  const commit = (nextValues: readonly string[]) => {
    if (nextValues.some((value) => value.trim().length === 0)) {
      setError("Value is required.")
      return
    }
    setError(undefined)
    onCommit?.(nextValues.join(" - "))
  }

  return (
    <dialog
      className="collection-composer-value-picker form date"
      open
      aria-label="Condition value picker"
    >
      <form
        className="collection-composer-value-form"
        onSubmit={(event) => {
          event.preventDefault()
          commit(
            kind === "date" && dateMode === "relative"
              ? [
                  relativePreset === "Custom"
                    ? `${relativeAmount} ${relativeUnit.toLowerCase()}${relativeAmount === "1" ? "" : "s"} ago`
                    : relativePreset,
                ]
              : values,
          )
        }}
      >
        {kind === "date" && (
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
        {kind === "date" && dateMode === "relative" ? (
          <>
            <label>
              <span>Preset</span>
              <select
                value={relativePreset}
                onChange={(event) =>
                  setRelativePreset(
                    relativePresets.find((preset) => preset === event.currentTarget.value) ??
                      "7 days ago",
                  )
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
              const label = isRange ? (index === 0 ? "From" : "To") : "Date"
              return (
                <label key={label}>
                  <span>{label}</span>
                  <input
                    type="date"
                    aria-label={isRange ? label : "Value"}
                    value={value}
                    onChange={(event) => {
                      const nextValue = event.currentTarget.value
                      setValues((current) =>
                        current.map((item, itemIndex) => (itemIndex === index ? nextValue : item)),
                      )
                    }}
                  />
                </label>
              )
            })}
          </div>
        )}
        {error != null && <output className="collection-composer-value-error">{error}</output>}
        <button type="submit">Apply</button>
      </form>
    </dialog>
  )
}

ComposerDateValuePicker.displayName = "ComposerDateValuePicker"
