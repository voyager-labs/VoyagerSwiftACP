import { type FC, useEffect, useState } from "react"
import { SFSymbol } from "../../Foundations/SFSymbol"

type ComposerCalendarProps = {
  readonly value: string
  readonly previewOnly?: boolean
  readonly onChange: (value: string) => void
}

const weekdays = [
  { name: "Sunday", label: "Su" },
  { name: "Monday", label: "Mo" },
  { name: "Tuesday", label: "Tu" },
  { name: "Wednesday", label: "We" },
  { name: "Thursday", label: "Th" },
  { name: "Friday", label: "Fr" },
  { name: "Saturday", label: "Sa" },
] as const

const parseDate = (value: string): Date => {
  const [year, month, day] = value.split("-").map(Number)
  return year != null && month != null && day != null && year > 0 && month > 0 && day > 0
    ? new Date(year, month - 1, day)
    : new Date()
}

const formatDate = (date: Date): string => {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, "0")
  const day = String(date.getDate()).padStart(2, "0")
  return `${year}-${month}-${day}`
}

const monthDays = (month: Date): readonly Date[] => {
  const first = new Date(month.getFullYear(), month.getMonth(), 1)
  const start = new Date(first)
  start.setDate(1 - first.getDay())
  return Array.from({ length: 42 }, (_, index) => {
    const date = new Date(start)
    date.setDate(start.getDate() + index)
    return date
  })
}

export const ComposerCalendar: FC<ComposerCalendarProps> = ({
  value,
  previewOnly = false,
  onChange,
}) => {
  const selectedDate = parseDate(value)
  const [displayedMonth, setDisplayedMonth] = useState(
    () => new Date(selectedDate.getFullYear(), selectedDate.getMonth(), 1),
  )

  // 활성 끝점 값(value 문자열)이 표시 월 밖으로 바뀌면 달력을 해당 월로 동기화한다.
  // 의존성은 안정적인 value여야 한다: Date 객체에 의존하면 매 렌더마다 실행되어 월 탐색이 되돌려진다
  useEffect(() => {
    const selected = parseDate(value)
    setDisplayedMonth((current) =>
      current.getFullYear() === selected.getFullYear() && current.getMonth() === selected.getMonth()
        ? current
        : new Date(selected.getFullYear(), selected.getMonth(), 1),
    )
  }, [value])

  const moveMonth = (offset: number) =>
    setDisplayedMonth((current) => new Date(current.getFullYear(), current.getMonth() + offset, 1))

  const selectToday = () => {
    const today = new Date()
    setDisplayedMonth(new Date(today.getFullYear(), today.getMonth(), 1))
    if (!previewOnly) onChange(formatDate(today))
  }

  return (
    <div
      className={`collection-composer-calendar${previewOnly ? " preview" : ""}`}
      aria-label="Calendar"
    >
      <div className="collection-composer-calendar-header">
        <strong>{displayedMonth.toLocaleDateString("en-US", { month: "short" })}</strong>
        <button
          type="button"
          aria-label="Previous month"
          disabled={previewOnly}
          onClick={() => moveMonth(-1)}
        >
          <SFSymbol name="chevron.left" size={10} weight={600} />
        </button>
        <button type="button" aria-label="Today" disabled={previewOnly} onClick={selectToday}>
          <SFSymbol name="circle.fill" size={7} weight={500} />
        </button>
        <button
          type="button"
          aria-label="Next month"
          disabled={previewOnly}
          onClick={() => moveMonth(1)}
        >
          <SFSymbol name="chevron.right" size={10} weight={600} />
        </button>
      </div>
      <div className="collection-composer-calendar-grid" aria-hidden="true">
        {weekdays.map((weekday) => (
          <span key={weekday.name}>{weekday.label}</span>
        ))}
      </div>
      <div className="collection-composer-calendar-grid">
        {monthDays(displayedMonth).map((date) => {
          const dateValue = formatDate(date)
          const outsideMonth = date.getMonth() !== displayedMonth.getMonth()
          return (
            <button
              type="button"
              key={dateValue}
              aria-label={date.toLocaleDateString("en-US", {
                day: "numeric",
                month: "long",
                year: "numeric",
              })}
              aria-pressed={dateValue === value}
              className={outsideMonth ? "outside-month" : undefined}
              disabled={previewOnly}
              onClick={() => onChange(dateValue)}
            >
              {date.getDate()}
            </button>
          )
        })}
      </div>
    </div>
  )
}

ComposerCalendar.displayName = "ComposerCalendar"
