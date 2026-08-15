// 네이티브 RelativeDateConditionLiteral 계약: voyager.relativeDate:v1:<direction>:<amount>:<unit>:<anchor>
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

// 조건 칩 표기: 정규 리터럴은 표시 문자열로, today는 "Today"로, 나머지는 원문 그대로
export const displayValueForLiteral = (value: string): string => {
  const relative = parseRelativeLiteral(value)
  if (relative != null) return relativeDisplay(relative.direction, relative.amount, relative.unit)
  if (value === todayLiteral()) return "Today"
  return value
}
