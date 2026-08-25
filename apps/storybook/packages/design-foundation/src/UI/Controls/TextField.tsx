import type { CSSProperties, ChangeEvent, FC } from "react"

export type TextFieldVariant = "default" | "rounded" | "plain"
export type TextFieldSize = "small" | "regular"

export interface TextFieldProps {
  value?: string
  placeholder?: string
  multiline?: boolean
  rows?: number
  readOnly?: boolean
  disabled?: boolean
  invalid?: boolean
  variant?: TextFieldVariant
  size?: TextFieldSize
  className?: string
  style?: CSSProperties
  ariaLabel?: string
  onChange?: (value: string) => void
}

export const TextField: FC<TextFieldProps> = ({
  value = "",
  placeholder,
  multiline = false,
  rows = 3,
  readOnly = false,
  disabled = false,
  invalid = false,
  variant = "default",
  size = "regular",
  className = "",
  style,
  ariaLabel,
  onChange,
}) => {
  function handleChange(event: ChangeEvent<HTMLTextAreaElement | HTMLInputElement>) {
    onChange?.(event.currentTarget.value)
  }

  const classes = [
    "vc-form-field",
    variant !== "default" ? `vc-form-field--${variant}` : "",
    size !== "regular" ? `vc-form-field--${size}` : "",
    invalid ? "vc-form-field--invalid" : "",
    className,
  ]
    .filter(Boolean)
    .join(" ")

  if (multiline) {
    return (
      <textarea
        className={classes}
        value={value}
        placeholder={placeholder}
        rows={rows}
        readOnly={readOnly}
        disabled={disabled}
        aria-label={ariaLabel}
        spellCheck={false}
        style={style}
        onChange={handleChange}
      />
    )
  }

  return (
    <input
      className={classes}
      type="text"
      value={value}
      placeholder={placeholder}
      readOnly={readOnly}
      disabled={disabled}
      aria-label={ariaLabel}
      spellCheck={false}
      style={style}
      onChange={handleChange}
    />
  )
}

TextField.displayName = "TextField"
