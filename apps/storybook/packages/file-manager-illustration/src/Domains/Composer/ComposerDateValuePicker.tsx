import { type FC, useState } from "react"
import {
  type ParsedRelativeLiteral,
  encodeRelativeLiteral,
  parseRelativeLiteral,
  relativeDisplay,
  todayLiteral,
} from "./composer-date-literal"

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

type RelativeUnit = (typeof relativeUnits)[number]

const presetAmounts: Record<
  Exclude<(typeof relativePresets)[number], "Custom" | "Today">,
  number
> = {
  Yesterday: 1,
  "7 days ago": 7,
  "30 days ago": 30,
  "3 months ago": 3,
  "1 year ago": 1,
}

const presetUnits: Record<
  Exclude<(typeof relativePresets)[number], "Custom" | "Today">,
  RelativeUnit
> = {
  Yesterday: "Day",
  "7 days ago": "Day",
  "30 days ago": "Day",
  "3 months ago": "Month",
  "1 year ago": "Year",
}

const unitToNative: Record<RelativeUnit, ParsedRelativeLiteral["unit"]> = {
  Day: "day",
  Week: "week",
  Month: "month",
  Year: "year",
}

const nativeToUnit: Record<ParsedRelativeLiteral["unit"], RelativeUnit> = {
  day: "Day",
  week: "Week",
  month: "Month",
  year: "Year",
}

type InitialState = {
  dateMode: "absolute" | "relative"
  preset: (typeof relativePresets)[number]
  amount: string
  unit: RelativeUnit
  direction: "past" | "future"
  values: readonly string[]
}

const parseInitialValue = (value: string | undefined): InitialState => {
  const trimmed = value?.trim() ?? ""
  // 네이티브 정규 리터럴 우선 파싱
  const literal = parseRelativeLiteral(trimmed)
  if (literal != null) {
    const matchedPreset = (
      Object.keys(presetAmounts) as readonly (keyof typeof presetAmounts)[]
    ).find(
      (preset) =>
        presetAmounts[preset] === literal.amount &&
        presetUnits[preset] === nativeToUnit[literal.unit],
    )
    return {
      dateMode: "relative",
      preset: matchedPreset ?? "Custom",
      amount: String(literal.amount),
      unit: nativeToUnit[literal.unit],
      direction: literal.direction,
      values: [],
    }
  }
  if (trimmed === todayLiteral()) {
    return {
      dateMode: "relative",
      preset: "Today",
      amount: "1",
      unit: "Day",
      direction: "past",
      values: [],
    }
  }
  const legacyPreset = relativePresets.find(
    (candidate) => candidate !== "Custom" && candidate === trimmed,
  )
  if (legacyPreset != null) {
    return {
      dateMode: "relative",
      preset: legacyPreset,
      amount: "1",
      unit: "Day",
      direction: "past",
      values: [],
    }
  }
  const custom = /^(\d+) (day|week|month|year)s? ago$/.exec(trimmed)
  if (custom != null) {
    const native = custom[2] as ParsedRelativeLiteral["unit"]
    return {
      dateMode: "relative",
      preset: "Custom",
      amount: custom[1] ?? "1",
      unit: nativeToUnit[native],
      direction: "past",
      values: [],
    }
  }
  return {
    dateMode: "absolute",
    preset: "7 days ago",
    amount: "1",
    unit: "Day",
    direction: "past",
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
  const [relativeUnit, setRelativeUnit] = useState<RelativeUnit>(initial.unit)
  // 네이티브는 future 방향 상태를 유지한다(프리셋 UI는 past 전용)
  const [relativeDirection] = useState<"past" | "future">(initial.direction)
  const [error, setError] = useState<string | undefined>(initialError)

  const commitAbsolute = (nextValues: readonly string[]) => {
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

  const customAmount = relativePreset === "Custom" ? Number(relativeAmount) : undefined
  const resolvedAmount =
    customAmount ?? presetAmounts[relativePreset as keyof typeof presetAmounts] ?? 1
  const resolvedUnit =
    relativePreset === "Custom"
      ? relativeUnit
      : (presetUnits[relativePreset as keyof typeof presetUnits] ?? "Day")

  // 네이티브 displayText: Today는 별도 mode로 표시하고, 나머지는 "N unit(s) ago" 형식
  const relativePreview =
    relativePreset === "Today"
      ? "Today"
      : relativeDisplay(relativeDirection, resolvedAmount, unitToNative[resolvedUnit])

  const submit = () => {
    if (kind === "date" && dateMode === "relative") {
      if (!relativeAmountValid) {
        setError("Enter a positive whole number of units.")
        return
      }
      // 네이티브 today 모드: raw = 오늘 날짜, 표시 = "Today"
      if (relativePreset === "Today") {
        setError(undefined)
        onCommit?.(todayLiteral())
        return
      }
      const literal = encodeRelativeLiteral(
        relativeDirection,
        resolvedAmount,
        unitToNative[resolvedUnit],
      )
      if (literal == null) {
        setError("Enter a positive whole number of units.")
        return
      }
      setError(undefined)
      onCommit?.(literal)
      return
    }
    commitAbsolute(values)
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
