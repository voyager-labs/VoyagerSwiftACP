// 네이티브 RelativeDateConditionLiteral 계약: voyager.relativeDate:v1:<direction>:<amount>:<unit>:<anchor>
import type { ComposerValueEditor } from "./composer-condition-options"

export type ParsedRelativeLiteral = {
  readonly direction: "past" | "future"
  readonly amount: number
  readonly unit: "day" | "week" | "month" | "year"
}

const unitLabels = {
  day: { one: "day", many: "days" },
  week: { one: "week", many: "weeks" },
  month: { one: "month", many: "months" },
  year: { one: "year", many: "years" },
} as const

const isValidDateOnlyLiteral = (text: string): boolean => /^\d{4}-\d{2}-\d{2}$/.test(text)

export const parseRelativeLiteral = (text: string): ParsedRelativeLiteral | undefined => {
  const parts = text.trim().split(":")
  if (parts.length !== 6 || parts[0] !== "voyager.relativeDate" || parts[1] !== "v1")
    return undefined
  if (parts[2] !== "past" && parts[2] !== "future") return undefined
  const amount = Number(parts[3])
  if (!Number.isInteger(amount) || amount <= 0) return undefined
  if (parts[4] !== "day" && parts[4] !== "week" && parts[4] !== "month" && parts[4] !== "year")
    return undefined
  if (!isValidDateOnlyLiteral(parts[5] ?? "")) return undefined
  return { direction: parts[2], amount, unit: parts[4] }
}

export const encodeRelativeLiteral = (
  direction: "past" | "future",
  amount: number,
  unit: ParsedRelativeLiteral["unit"],
): string | undefined => {
  if (!Number.isInteger(amount) || amount <= 0) return undefined
  return `voyager.relativeDate:v1:${direction}:${amount}:${unit}:${todayLiteral()}`
}

// 앵커(오늘)와 amount/unit으로 상대 날짜를 YYYY-MM-DD로 계산한다 (네이티브 syncRelativeSelectedDate 대응)
export const resolveRelativeDate = (
  direction: "past" | "future",
  amount: number,
  unit: ParsedRelativeLiteral["unit"],
): string => {
  const offset = direction === "past" ? -amount : amount
  const now = new Date()
  const format = (year: number, monthIndex: number, day: number): string =>
    `${year}-${String(monthIndex + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`

  if (unit === "day" || unit === "week") {
    const date = new Date(now)
    date.setDate(date.getDate() + offset * (unit === "week" ? 7 : 1))
    return format(date.getFullYear(), date.getMonth(), date.getDate())
  }
  // 네이티브 Calendar.date(byAdding:)의 말일 보정 대응: JS 오버플로(예: 5/31 - 3개월 = 3/3)를 목표 월 말일 클램프로 대체한다
  const targetYear = unit === "year" ? now.getFullYear() + offset : now.getFullYear()
  const targetMonth = unit === "month" ? now.getMonth() + offset : now.getMonth()
  const lastDay = new Date(targetYear, targetMonth + 1, 0).getDate()
  return format(targetYear, targetMonth, Math.min(now.getDate(), lastDay))
}

export const todayLiteral = (): string => {
  const now = new Date()
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(
    now.getDate(),
  ).padStart(2, "0")}`
}

export const relativeDisplay = (
  direction: "past" | "future",
  amount: number,
  unit: ParsedRelativeLiteral["unit"],
): string => {
  if (amount <= 0) return "Value"
  const labels = unitLabels[unit]
  const unitLabel = amount === 1 ? labels.one : labels.many
  return direction === "past" ? `${amount} ${unitLabel} ago` : `In ${amount} ${unitLabel}`
}

// 목록 값은 JSON 배열로 직렬화되므로 칩 표시 시 디코딩한다
const displayListValue = (value: string): string => {
  try {
    const parsed = JSON.parse(value)
    if (Array.isArray(parsed)) {
      return parsed.filter((token): token is string => typeof token === "string").join(", ")
    }
  } catch {
    // 비-배열 JSON 또는 평문은 그대로
  }
  return value
}

// 조건 칩 표기: list는 목록 JSON 디코딩, date/dateRange만 정규 리터럴·Today 변환, 나머지는 원문 그대로
export const displayValueForLiteral = (
  value: string,
  editorKind?: ComposerValueEditor["kind"],
): string => {
  if (editorKind === "list" && value.startsWith("[")) {
    const decoded = displayListValue(value)
    if (decoded !== value) return decoded
  }
  if (editorKind === "date" || editorKind === "dateRange") {
    const relative = parseRelativeLiteral(value)
    if (relative != null) return relativeDisplay(relative.direction, relative.amount, relative.unit)
    if (value === todayLiteral()) return "Today"
  }
  return value
}
