import type { ParsedRelativeLiteral } from "./composer-date-literal"
import { parseRelativeLiteral, todayLiteral } from "./composer-date-literal"

export const relativePresets = [
  "Custom",
  "Today",
  "Yesterday",
  "7 days ago",
  "30 days ago",
  "3 months ago",
  "1 year ago",
] as const

export const relativeUnits = ["Day", "Week", "Month", "Year"] as const

export type RelativePreset = (typeof relativePresets)[number]
export type RelativeUnit = (typeof relativeUnits)[number]

const presetValues = {
  Yesterday: { amount: 1, unit: "Day" },
  "7 days ago": { amount: 7, unit: "Day" },
  "30 days ago": { amount: 30, unit: "Day" },
  "3 months ago": { amount: 3, unit: "Month" },
  "1 year ago": { amount: 1, unit: "Year" },
} as const satisfies Record<string, { readonly amount: number; readonly unit: RelativeUnit }>

type NamedRelativePreset = keyof typeof presetValues

export const unitToNative: Record<RelativeUnit, ParsedRelativeLiteral["unit"]> = {
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

export type DatePickerInitialState = {
  readonly dateMode: "absolute" | "relative"
  readonly preset: RelativePreset
  readonly amount: string
  readonly unit: RelativeUnit
  readonly direction: "past" | "future"
  readonly values: readonly string[]
}

const isNamedPreset = (preset: RelativePreset): preset is NamedRelativePreset =>
  preset !== "Custom" && preset !== "Today"

const parseNativeUnit = (value: string | undefined): ParsedRelativeLiteral["unit"] | undefined => {
  if (value === "day" || value === "week" || value === "month" || value === "year") return value
  return undefined
}

const absoluteDateState = (trimmed: string): DatePickerInitialState => ({
  dateMode: "absolute",
  preset: "7 days ago",
  amount: "1",
  unit: "Day",
  direction: "past",
  values: trimmed.length > 0 ? trimmed.split(" - ") : [],
})

export const parseDatePickerInitialValue = (
  value: string | undefined,
  preferredMode?: DatePickerInitialState["dateMode"],
): DatePickerInitialState => {
  const trimmed = value?.trim() ?? ""
  if (preferredMode === "absolute") return absoluteDateState(trimmed)
  const literal = parseRelativeLiteral(trimmed)
  if (literal != null) {
    const matchedPreset = relativePresets.find(
      (preset) =>
        isNamedPreset(preset) &&
        presetValues[preset].amount === literal.amount &&
        presetValues[preset].unit === nativeToUnit[literal.unit],
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
  const nativeUnit = parseNativeUnit(custom?.[2])
  if (custom != null && nativeUnit != null) {
    return {
      dateMode: "relative",
      preset: "Custom",
      amount: custom[1] ?? "1",
      unit: nativeToUnit[nativeUnit],
      direction: "past",
      values: [],
    }
  }
  return absoluteDateState(trimmed)
}

export const resolveRelativeValue = (
  preset: RelativePreset,
  customAmount: number,
  customUnit: RelativeUnit,
): { readonly amount: number; readonly unit: RelativeUnit } => {
  if (preset === "Custom") return { amount: customAmount, unit: customUnit }
  if (preset === "Today") return { amount: 1, unit: "Day" }
  return presetValues[preset]
}
