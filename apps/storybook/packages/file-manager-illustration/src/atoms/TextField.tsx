import type { ChangeEvent, FC } from "react"

export interface TextFieldProps {
  value?: string
  placeholder?: string
  multiline?: boolean
  rows?: number
  readOnly?: boolean
  ariaLabel?: string
  onChange?: (value: string) => void
}

export const TextField: FC<TextFieldProps> = ({
  value = "",
  placeholder,
  multiline = false,
  rows = 3,
  readOnly = false,
  ariaLabel,
  onChange,
}) => {
  function handleChange(event: ChangeEvent<HTMLTextAreaElement | HTMLInputElement>) {
    onChange?.(event.currentTarget.value)
  }

  if (multiline) {
    return (
      <textarea
        className="vc-form-field"
        value={value}
        placeholder={placeholder}
        rows={rows}
        readOnly={readOnly}
        aria-label={ariaLabel}
        spellCheck={false}
        onChange={handleChange}
      />
    )
  }

  return (
    <input
      className="vc-form-field"
      type="text"
      value={value}
      placeholder={placeholder}
      readOnly={readOnly}
      aria-label={ariaLabel}
      spellCheck={false}
      onChange={handleChange}
    />
  )
}

TextField.displayName = "TextField"
