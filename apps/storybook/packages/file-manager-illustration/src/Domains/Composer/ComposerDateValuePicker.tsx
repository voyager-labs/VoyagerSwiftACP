import { type FC, useState } from "react"
import { ComposerCalendar } from "./ComposerCalendar"
import {
  encodeRelativeLiteral,
  relativeDisplay,
  resolveRelativeDate,
  todayLiteral,
} from "./composer-date-literal"
import {
  type RelativePreset,
  type RelativeUnit,
  parseDatePickerInitialValue,
  relativePresets,
  relativeUnits,
  resolveRelativeValue,
  unitToNative,
} from "./composer-date-picker-state"

export type ComposerDateValuePickerProps = {
  readonly kind: "date" | "dateRange"
  readonly initialValue?: string
  readonly initialDateMode?: "absolute" | "relative"
  readonly editingIndex?: 0 | 1
  readonly error?: string
  readonly onCommit?: (value: string) => void
}

export const ComposerDateValuePicker: FC<ComposerDateValuePickerProps> = ({
  kind,
  initialValue,
  initialDateMode,
  editingIndex = 0,
  error: initialError,
  onCommit,
}) => {
  const isRange = kind === "dateRange"
  const initial = parseDatePickerInitialValue(initialValue, initialDateMode)
  const [values, setValues] = useState<readonly string[]>(() =>
    Array.from({ length: isRange ? 2 : 1 }, (_, index) => initial.values[index] ?? ""),
  )
  const [dateMode, setDateMode] = useState<"absolute" | "relative">(initial.dateMode)
  const [relativePreset, setRelativePreset] = useState<RelativePreset>(initial.preset)
  const [relativeAmount, setRelativeAmount] = useState(initial.amount)
  const [relativeUnit, setRelativeUnit] = useState<RelativeUnit>(initial.unit)
  // 네이티브는 future 방향 상태를 유지한다(프리셋 UI는 past 전용)
  const [relativeDirection, setRelativeDirection] = useState<"past" | "future">(initial.direction)
  const [error, setError] = useState<string | undefined>(initialError)
  // 범위 편집 중인 끝점. prop은 스토리 arg 호환을 위한 초기값으로만 존중한다
  const [editingEndpoint, setEditingEndpoint] = useState<0 | 1>(editingIndex)

  const setSelectedDate = (value: string) => {
    setValues((current) => current.map((item, index) => (index === editingEndpoint ? value : item)))
    // 첫 끝점을 채운 직후 To가 비어 있으면 다음 끝점으로 자동 이동
    if (isRange && editingEndpoint === 0 && (values[1]?.trim().length ?? 0) === 0) {
      setEditingEndpoint(1)
    }
  }

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

  // 네이티브는 파싱 불가능한 수량을 상태에 반영하지 않는다: 유효하지 않으면 앵커·프리뷰 계산에서 제외한다
  const rawAmount = Number(relativeAmount)
  const safeAmount = Number.isInteger(rawAmount) && rawAmount > 0 ? rawAmount : 1
  const resolvedRelative = resolveRelativeValue(relativePreset, safeAmount, relativeUnit)

  // 네이티브 displayText: Today는 별도 mode로 표시하고, 나머지는 "N unit(s) ago" 형식
  const relativePreview =
    relativePreset === "Today"
      ? "Today"
      : relativeDisplay(
          relativeDirection,
          resolvedRelative.amount,
          unitToNative[resolvedRelative.unit],
        )

  // 상대 프리뷰·달력·절대 전환 공유 앵커 날짜
  const relativeAnchorDate =
    relativePreset === "Today"
      ? todayLiteral()
      : resolveRelativeDate(
          relativeDirection,
          resolvedRelative.amount,
          unitToNative[resolvedRelative.unit],
        )

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
        resolvedRelative.amount,
        unitToNative[resolvedRelative.unit],
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
        className="collection-composer-value-form collection-composer-date-form"
        onSubmit={(event) => {
          event.preventDefault()
          submit()
        }}
      >
        {kind === "date" && (
          <fieldset className="collection-composer-date-type">
            <legend>Date Type</legend>
            <div>
              <button
                type="button"
                aria-pressed={dateMode === "absolute"}
                onClick={() => {
                  // 네이티브 syncRelativeSelectedDate 계약: 실제 relative→absolute 전환에서 유효한 수량일 때만 프리뷰 날짜를 복사한다
                  if (dateMode === "relative" && relativeAmountValid) {
                    setSelectedDate(relativeAnchorDate)
                  }
                  setDateMode("absolute")
                }}
              >
                On date
              </button>
              <button
                type="button"
                aria-pressed={dateMode === "relative"}
                onClick={() => {
                  // 네이티브 setDateMode(.relative) 계약: 절대→상대 전환은 Custom 프리셋으로 진입한다(기본 프리셋 은닉 방지)
                  if (dateMode === "absolute") {
                    setRelativePreset("Custom")
                  }
                  setDateMode("relative")
                }}
              >
                Relative
              </button>
            </div>
          </fieldset>
        )}
        {isRange && (
          <fieldset className="collection-composer-date-type">
            <legend>Editing date</legend>
            <div>
              <button
                type="button"
                aria-pressed={editingEndpoint === 0}
                onClick={() => setEditingEndpoint(0)}
              >
                {`From ${values[0]?.trim() || "—"}`}
              </button>
              <button
                type="button"
                aria-pressed={editingEndpoint === 1}
                onClick={() => setEditingEndpoint(1)}
              >
                {`To ${values[1]?.trim() || "—"}`}
              </button>
            </div>
          </fieldset>
        )}
        {kind === "date" && dateMode === "relative" ? (
          <div className="collection-composer-relative-date-fields">
            <select
              aria-label="Preset"
              value={relativePreset}
              onChange={(event) => {
                const next =
                  relativePresets.find((preset) => preset === event.currentTarget.value) ??
                  "7 days ago"
                // 네이티브 applyRelativePreset 계약: 프리셋마다 amount·unit도 저장해 Custom 전환 시 이어받는다
                const resolved = resolveRelativeValue(next, Number(relativeAmount), relativeUnit)
                setRelativeAmount(String(resolved.amount))
                setRelativeUnit(resolved.unit)
                setRelativeDirection("past")
                setRelativePreset(next)
              }}
            >
              {relativePresets.map((preset) => (
                <option key={preset}>{preset}</option>
              ))}
            </select>
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
            <small>{relativePreview}</small>
            <ComposerCalendar value={relativeAnchorDate} previewOnly onChange={setSelectedDate} />
            <small>Preview based on today</small>
          </div>
        ) : (
          <ComposerCalendar
            value={values[editingEndpoint] ?? todayLiteral()}
            onChange={setSelectedDate}
          />
        )}
        {error != null && <output className="collection-composer-value-error">{error}</output>}
        <div className="collection-composer-date-actions">
          <button type="submit">Apply</button>
        </div>
      </form>
    </dialog>
  )
}

ComposerDateValuePicker.displayName = "ComposerDateValuePicker"
