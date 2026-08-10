import { useId } from "react"
import type { ChangeEvent, DragEvent, FC, KeyboardEvent } from "react"
import { designVersionIDs, useDesignVersion } from "../../Foundations/DesignVersion"
import { SFSymbol } from "../../Foundations/SFSymbol"
import { IconButton } from "../../UI/Controls/IconButton"
import { PopUpButton } from "../../UI/Controls/PopUpButton"
import type { AiChatInputBarProps } from "../../model/types"
import { AiChatNativeMenuSelector } from "./AiChatNativeMenuSelector"

const actionSymbols = {
  submit: "arrow.up",
  stop: "stop.fill",
} as const

export const AiChatInputBar: FC<AiChatInputBarProps> = ({
  requestText,
  onRequestTextChange,
  presentation,
  actions,
}) => {
  const inputHintID = useId()
  const designVersion = useDesignVersion()

  function handleInput(event: ChangeEvent<HTMLTextAreaElement>) {
    onRequestTextChange(event.currentTarget.value)
  }

  function handleKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (
      event.key === "Enter" &&
      !event.shiftKey &&
      presentation.action.kind === "submit" &&
      presentation.action.isEnabled
    ) {
      event.preventDefault()
      actions?.onSubmit?.()
    }
  }

  function handleDragOver(event: DragEvent<HTMLElement>) {
    if (!presentation.isComposerEditingDisabled && actions?.onAttachmentsDropped != null) {
      event.preventDefault()
    }
  }

  function handleDrop(event: DragEvent<HTMLElement>) {
    if (presentation.isComposerEditingDisabled || actions?.onAttachmentsDropped == null) return
    const files = Array.from(event.dataTransfer.files)
    const urls = event.dataTransfer
      .getData("text/uri-list")
      .split(/\r?\n/)
      .map((value) => value.trim())
      .filter((value) => value !== "" && !value.startsWith("#") && URL.canParse(value))
      .map((value) => new URL(value))
    if (files.length === 0 && urls.length === 0) return
    event.preventDefault()
    actions.onAttachmentsDropped({ files, urls })
  }

  const actionHandler = presentation.action.kind === "submit" ? actions?.onSubmit : actions?.onStop
  const usesCandidateControls = designVersion === designVersionIDs.materialControls

  return (
    <section
      className="fm-ai-chat-input"
      aria-label="Chat composer"
      data-editing-disabled={presentation.isComposerEditingDisabled || undefined}
      onDragOver={handleDragOver}
      onDrop={handleDrop}
    >
      {presentation.contextSections.length > 0 ? (
        <div className="fm-ai-chat-input-context">
          {presentation.contextSections.map((section) => (
            <div key={section.id} className="fm-ai-chat-context-section" aria-label={section.label}>
              <span className="fm-ai-chat-context-section-label">{section.label}</span>
              <div className="fm-ai-chat-context-groups">
                {section.groups.map((group) => (
                  <div key={group.id} className="fm-ai-chat-context-group">
                    <span className="fm-ai-chat-context-group-label">{group.label}</span>
                    {group.items.map((item) => (
                      <span key={item.id} className="fm-ai-chat-context-chip" title={item.detail}>
                        {item.symbolName != null ? (
                          <SFSymbol name={item.symbolName} size={11} weight={500} />
                        ) : null}
                        <span className="fm-ai-chat-context-chip-title">{item.title}</span>
                        {item.trailingSymbolName != null ? (
                          <SFSymbol name={item.trailingSymbolName} size={10} weight={600} />
                        ) : null}
                        {section.isEditable && item.isRemovable ? (
                          <button
                            type="button"
                            className="fm-ai-chat-context-remove"
                            aria-label={`Remove ${item.title}`}
                            onClick={() => actions?.onRemoveContextItem?.(item.id)}
                          >
                            <SFSymbol name="xmark" size={7} weight={700} />
                          </button>
                        ) : null}
                      </span>
                    ))}
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      ) : null}

      <textarea
        value={requestText}
        disabled={presentation.isComposerEditingDisabled}
        rows={1}
        placeholder={presentation.placeholder}
        aria-label={presentation.inputAccessibilityLabel}
        aria-describedby={inputHintID}
        onChange={handleInput}
        onKeyDown={handleKeyDown}
      />
      <span id={inputHintID} className="fm-ai-chat-input-hint">
        {presentation.inputAccessibilityHint}
      </span>

      <div className="fm-ai-chat-input-footer">
        {usesCandidateControls ? (
          <IconButton
            className="fm-ai-chat-attachment subtle"
            disabled={presentation.isComposerEditingDisabled}
            aria-label={presentation.contextAffordanceLabel}
            title={presentation.contextAffordanceLabel}
            onClick={actions?.onAddAttachment}
          >
            <SFSymbol name="plus" size={10} weight={600} />
          </IconButton>
        ) : (
          <button
            type="button"
            className="fm-ai-chat-native-attachment"
            disabled={presentation.isComposerEditingDisabled}
            aria-label={presentation.contextAffordanceLabel}
            title={presentation.contextAffordanceLabel}
            onClick={actions?.onAddAttachment}
          >
            +
          </button>
        )}

        <div className="fm-ai-chat-input-selectors">
          {usesCandidateControls ? (
            <>
              <PopUpButton
                className="fm-ai-chat-menu-selector fm-ai-chat-model-selector"
                options={presentation.modelSelector.options}
                value={presentation.modelSelector.value}
                disabled={presentation.modelSelector.isDisabled}
                accessibilityLabel={`${presentation.modelSelector.accessibilityLabel}: ${presentation.modelSelector.accessibilityValue}`}
                onChange={(value) => actions?.onModelSelected?.(value)}
              />
              <PopUpButton
                className="fm-ai-chat-menu-selector fm-ai-chat-thinking-selector"
                options={presentation.thinkingSelector.options}
                value={presentation.thinkingSelector.value}
                disabled={presentation.thinkingSelector.isDisabled}
                accessibilityLabel={`${presentation.thinkingSelector.accessibilityLabel}: ${presentation.thinkingSelector.accessibilityValue}`}
                onChange={(value) => actions?.onThinkingSelected?.(value)}
              />
            </>
          ) : (
            <>
              <AiChatNativeMenuSelector
                className="fm-ai-chat-model-selector"
                presentation={presentation.modelSelector}
                onChange={actions?.onModelSelected}
              />
              <AiChatNativeMenuSelector
                className="fm-ai-chat-thinking-selector"
                presentation={presentation.thinkingSelector}
                onChange={actions?.onThinkingSelected}
              />
            </>
          )}
        </div>

        {usesCandidateControls ? (
          <IconButton
            className="fm-ai-chat-input-action"
            data-action={presentation.action.kind}
            disabled={!presentation.action.isEnabled}
            aria-label={presentation.action.accessibilityLabel}
            title={presentation.action.help}
            onClick={actionHandler}
          >
            <SFSymbol name={actionSymbols[presentation.action.kind]} size={8} weight={600} />
          </IconButton>
        ) : (
          <button
            type="button"
            className="fm-ai-chat-input-action"
            data-action={presentation.action.kind}
            disabled={!presentation.action.isEnabled}
            aria-label={presentation.action.accessibilityLabel}
            title={presentation.action.help}
            onClick={actionHandler}
          >
            <SFSymbol name={actionSymbols[presentation.action.kind]} size={8} weight={600} />
          </button>
        )}
      </div>
    </section>
  )
}

AiChatInputBar.displayName = "AiChatInputBar"
