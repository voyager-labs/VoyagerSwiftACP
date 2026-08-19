import type { ChangeEvent, FC } from "react"
import type { AiChatInputMenuSelectorPresentation } from "../../model/types"

type AiChatNativeMenuSelectorProps = {
  readonly className: string
  readonly presentation: AiChatInputMenuSelectorPresentation
  readonly onChange?: (value: string) => void
}

export const AiChatNativeMenuSelector: FC<AiChatNativeMenuSelectorProps> = ({
  className,
  presentation,
  onChange,
}) => {
  function handleChange(event: ChangeEvent<HTMLSelectElement>) {
    onChange?.(event.currentTarget.value)
  }

  return (
    <span className={`fm-ai-chat-native-menu-selector ${className}`}>
      <select
        value={presentation.value}
        disabled={presentation.isDisabled}
        aria-label={`${presentation.accessibilityLabel}: ${presentation.accessibilityValue}`}
        onChange={handleChange}
      >
        {presentation.options.map((option) => (
          <option key={option.value} value={option.value} disabled={option.disabled}>
            {option.label}
          </option>
        ))}
      </select>
    </span>
  )
}

AiChatNativeMenuSelector.displayName = "AiChatNativeMenuSelector"
