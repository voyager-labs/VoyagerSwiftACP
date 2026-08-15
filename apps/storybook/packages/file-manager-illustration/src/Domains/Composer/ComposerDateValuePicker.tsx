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
  readonly initialValue?: string
  readonly error?: string
  readonly onCommit?: (value: string) => void
}

const relativeUnits = ["Day", "Week", "Month", "Year"] as const

const parseInitialValue = (
  value: string | undefined,
): {
  dateMode: "absolute" | "relative"
  preset: (typeof relativePresets)[number]
  amount: string
  unit: (typeof relativeUnits)[number]
  values: readonly string[]
} => {
  const trimmed = value?.trim() ?? ""
  const preset = relativePresets.find(
    (candidate) => candidate !== "Custom" && candidate === trimmed,
  )
  if (preset != null) {
    return { dateMode: "relative", preset, amount: "1", unit: "Day", values: [] }
  }
  const custom = /^(\d+) (day|week|month|year)s? ago$/.exec(trimmed)
  if (custom != null) {
    const unit = relativeUnits.find((candidate) => candidate.toLowerCase() === custom[2])
    return {
      dateMode: "relative",
      preset: "Custom",
      amount: custom[1] ?? "1",
      unit: unit ?? "Day",
      values: [],
    }
  }
  return {
    dateMode: "absolute",
    preset: "7 days ago",
    amount: "1",
    unit: "Day",
    values: trimmed.length > 0 ? trimmed.split(" - ") : [],
  }
}

export const ComposerDateValuePicker: FC<ComposerDateValuePickerProps> = ({
  kind,
  initialValue,
  error: initialError,
  onCommit,
}) => {
  const isRange = kind === "dateRange"
  const initial = parseInitialValue(initialValue)
  const [values, setValues] = useState<readonly string[]>(() =>
    Array.from({ length: isRange ? 2 : 1 }, (_, index) => initial.values[index] ?? ""),
  )
  const [dateMode, setDateMode] = useState<"absolute" | "relative">(initial.dateMode)
  const [relativePreset, setRelativePreset] = useState<(typeof relativePresets)[number]>(
    initial.preset,
  )
  const [relativeAmount, setRelativeAmount] = useState(initial.amount)
  const [relativeUnit, setRelativeUnit] = useState<(typeof relativeUnits)[number]>(initial.unit)
  const [error, setError] = useState<string | undefined>(initialError)

  const commit = (nextValues: readonly string[]) => {
    if (nextValues.some((value) => value.trim().length === 0)) {
      setError("Value is required.")
      return
    }
    if (kind === "dateRange") {
      const [from, to] = nextValues
      if (from.localeCompare(to) > 0) {
        setError("From must be earlier than or equal to To.")
        return
      }
    }
    setError(undefined)
    onCommit?.(nextValues.join(" - "))
  }

  const relativeAmountValid =
    relativePreset !== "Custom" ||
    (relativeAmount.trim().length > 0 &&
      Number.isInteger(Number(relativeAmount)) &&
      Number(relativeAmount) > 0)

  const relativePreview =
    relativePreset === "Custom"
      ? `${relativeAmount} ${relativeUnit.toLowerCase()}${relativeAmount === "1" ? "" : "s"} ago`
      : relativePreset

  const submit = () => {
    if (kind === "date" && dateMode === "relative") {
      if (!relativeAmountValid) {
        setError("Enter a positive whole number of units.")
        return
      }
      commit([relativePreview])
      return
    }
    commit(values)
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
          submit()
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
                  aria-invalid={!relativeAmountValid}
                  className={!relativeAmountValid ? "invalid" : undefined}
                  inputMode="numeric"
                  placeholder="1"
                  value={relativeAmount}
                  onChange={(event) => setRelativeAmount(event.currentTarget.value)}
                />
                <select
                  aria-label="Relative unit"
                  value={relativeUnit}
                  onChange={(event) =>
                    setRelativeUnit(
                      relativeUnits.find((unit) => unit === event.currentTarget.value) ?? "Day",
                    )
                  }
                >
                  {relativeUnits.map((unit) => (
                    <option key={unit}>{unit}</option>
                  ))}
                </select>
              </div>
            )}
            <small>Preview: {relativePreview}</small>
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
