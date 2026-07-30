import { type FC, useId } from "react"

export interface SegmentedOption {
  value: string
  label: string
}

export interface SegmentedControlProps {
  options: readonly SegmentedOption[]
  value: string
  onChange: (value: string) => void
  className?: string
}

export const SegmentedControl: FC<SegmentedControlProps> = ({
  options,
  value,
  onChange,
  className = "",
}) => {
  const groupName = useId()

  return (
    <div className={`vc-segmented-control ${className}`.trim()} role="radiogroup">
      {options.map((opt) => (
        <label key={opt.value} className={opt.value === value ? "active" : ""}>
          <input
            type="radio"
            name={groupName}
            value={opt.value}
            checked={opt.value === value}
            onChange={() => onChange(opt.value)}
          />
          <span>{opt.label}</span>
        </label>
      ))}
    </div>
  )
}

SegmentedControl.displayName = "SegmentedControl"
