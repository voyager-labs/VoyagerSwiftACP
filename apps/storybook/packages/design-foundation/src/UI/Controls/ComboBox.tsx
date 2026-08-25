import { useCallback, useEffect, useId, useRef, useState } from "react"
import type { CSSProperties, FC, FocusEvent, KeyboardEvent, MouseEvent } from "react"
import type { ControlOption } from "./ControlOption"
import { MenuItem } from "./MenuItem"

export interface ComboBoxProps<Value = string> {
  /** 옵션 목록 */
  options: readonly ControlOption<Value>[]
  /** 현재 선택된 값 */
  value?: Value
  /** 플레이스홀더 텍스트 */
  placeholder?: string
  /** 리스트박스 열림/닫힘 제어 (미지정 시 내부 상태 사용) */
  open?: boolean
  /** 비활성화 */
  disabled?: boolean
  className?: string
  style?: CSSProperties
  /** 옵션 선택 시 콜백 */
  onSelect?: (value: Value) => void
  /** 열림/닫힘 변경 시 콜백 */
  onOpenChange?: (open: boolean) => void
}

export const ComboBox: FC<ComboBoxProps> = <Value = string>({
  options,
  value,
  placeholder,
  open: controlledOpen,
  disabled = false,
  className = "",
  style,
  onSelect,
  onOpenChange,
}: ComboBoxProps<Value>) => {
  const [internalOpen, setInternalOpen] = useState(false)
  const isOpen = controlledOpen ?? internalOpen
  const containerRef = useRef<HTMLDivElement>(null)
  const triggerRef = useRef<HTMLButtonElement>(null)
  const listboxRef = useRef<HTMLDivElement>(null)
  const listboxId = useId()
  const labelId = useId()

  const selectedOption = value != null ? (options.find((o) => o.value === value) ?? null) : null

  // 외부 클릭 시 닫기
  useEffect(() => {
    if (!isOpen) return

    function handleClickOutside(event: MouseEvent | Event) {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setInternalOpen(false)
        onOpenChange?.(false)
      }
    }

    // mousedown 이벤트로 변경 (click보다 먼저 발생)
    document.addEventListener("mousedown", handleClickOutside, true)
    return () => document.removeEventListener("mousedown", handleClickOutside, true)
  }, [isOpen, onOpenChange])

  // Escape 키로 닫기
  useEffect(() => {
    if (!isOpen) return

    function handleKeyDown(event: KeyboardEvent | globalThis.KeyboardEvent) {
      if (event.key === "Escape") {
        setInternalOpen(false)
        onOpenChange?.(false)
        triggerRef.current?.focus()
      }
    }

    document.addEventListener("keydown", handleKeyDown, true)
    return () => document.removeEventListener("keydown", handleKeyDown, true)
  }, [isOpen, onOpenChange])

  const handleTriggerClick = useCallback(() => {
    if (disabled) return
    const next = !isOpen
    setInternalOpen(next)
    onOpenChange?.(next)
  }, [disabled, isOpen, onOpenChange])

  const handleTriggerKeyDown = useCallback(
    (event: KeyboardEvent<HTMLButtonElement>) => {
      if (event.key === "ArrowDown" || event.key === "Enter" || event.key === " ") {
        event.preventDefault()
        if (!isOpen) {
          setInternalOpen(true)
          onOpenChange?.(true)
        }
      }
      if (event.key === "ArrowUp" && isOpen) {
        event.preventDefault()
        // 포커스를 마지막 옵션으로 이동
        const options = listboxRef.current?.querySelectorAll<HTMLButtonElement>(
          ".vc-combo-box-option:not(:disabled)",
        )
        if (options && options.length > 0) {
          options[options.length - 1]?.focus()
        }
      }
    },
    [isOpen, onOpenChange],
  )

  const handleOptionClick = useCallback(
    (optionValue: Value) => {
      onSelect?.(optionValue)
      setInternalOpen(false)
      onOpenChange?.(false)
      triggerRef.current?.focus()
    },
    [onSelect, onOpenChange],
  )

  const handleOptionKeyDown = useCallback(
    (event: KeyboardEvent<HTMLButtonElement>, optionValue: Value) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault()
        handleOptionClick(optionValue)
        return
      }

      const options = listboxRef.current?.querySelectorAll<HTMLButtonElement>(
        ".vc-combo-box-option:not(:disabled)",
      )
      if (!options || options.length === 0) return

      const currentIndex = Array.from(options).indexOf(event.currentTarget)

      if (event.key === "ArrowDown") {
        event.preventDefault()
        const nextIndex = (currentIndex + 1) % options.length
        options[nextIndex]?.focus()
      } else if (event.key === "ArrowUp") {
        event.preventDefault()
        const prevIndex = (currentIndex - 1 + options.length) % options.length
        options[prevIndex]?.focus()
      }
    },
    [handleOptionClick],
  )

  const handleBlur = useCallback(
    (event: FocusEvent<HTMLDivElement>) => {
      // 포커스가 컨테이너 밖으로 나가면 닫기
      if (!containerRef.current?.contains(event.relatedTarget as Node)) {
        setInternalOpen(false)
        onOpenChange?.(false)
      }
    },
    [onOpenChange],
  )

  const chevronPath =
    "M3.646 5.646a.5.5 0 0 1 .708 0L8 9.293l3.646-3.647a.5.5 0 0 1 .708.708l-4 4a.5.5 0 0 1-.708 0l-4-4a.5.5 0 0 1 0-.708z"

  return (
    <div
      ref={containerRef}
      className={["vc-combo-box", className].filter(Boolean).join(" ")}
      style={style}
      onBlur={handleBlur}
    >
      <button
        ref={triggerRef}
        type="button"
        aria-haspopup="menu"
        aria-expanded={isOpen}
        aria-controls={listboxId}
        aria-labelledby={labelId}
        aria-activedescendant={isOpen && selectedOption ? String(selectedOption.value) : undefined}
        className="vc-combo-box-trigger"
        disabled={disabled}
        onClick={handleTriggerClick}
        onKeyDown={handleTriggerKeyDown}
      >
        <span className="vc-combo-box-trigger-label">
          {selectedOption ? (
            selectedOption.label
          ) : (
            <span className="vc-combo-box-trigger-placeholder">{placeholder ?? ""}</span>
          )}
        </span>
        <svg
          className="vc-combo-box-chevron"
          aria-expanded={isOpen}
          viewBox="0 0 16 16"
          fill="currentColor"
          aria-hidden="true"
        >
          <path d={chevronPath} />
        </svg>
      </button>

      {isOpen && (
        <div
          ref={listboxRef}
          id={listboxId}
          role="menu"
          aria-labelledby={labelId}
          className="vc-combo-box-popover"
        >
          {options.map((option) => {
            const isSelected = option.value === value
            return (
              <MenuItem
                key={String(option.value)}
                className="vc-combo-box-option"
                role="menuitemradio"
                label={option.label}
                detail={option.detail}
                checked={isSelected}
                disabled={option.disabled}
                onClick={() => handleOptionClick(option.value)}
                onKeyDown={(e) => handleOptionKeyDown(e, option.value)}
              />
            )
          })}
        </div>
      )}
    </div>
  )
}

ComboBox.displayName = "ComboBox"
