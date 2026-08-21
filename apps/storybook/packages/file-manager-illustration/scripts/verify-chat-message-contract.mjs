import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { resolve } from "node:path"

export function verifyChatMessageContract(packageRoot, css) {
  const assistantCardSource = readFileSync(
    resolve(packageRoot, "src/Domains/Chat/AiChatAssistantCard.tsx"),
    "utf8",
  )
  const assistantStorySource = readFileSync(
    resolve(packageRoot, "../../src/FileManager/Domains/Chat/AiChatAssistantCard.stories.tsx"),
    "utf8",
  )
  const assistantPresentationSource = readFileSync(
    resolve(packageRoot, "src/Domains/Chat/AiChatAssistantPresentation.ts"),
    "utf8",
  )
  const assistantMarkdownSource = readFileSync(
    resolve(packageRoot, "src/Domains/Chat/AiChatAssistantMarkdownText.tsx"),
    "utf8",
  )
  const assistantMarkdownParserSource = readFileSync(
    resolve(packageRoot, "src/Domains/Chat/AiChatMarkdownParser.ts"),
    "utf8",
  )
  const userStorySource = readFileSync(
    resolve(packageRoot, "../../src/FileManager/Domains/Chat/AiChatUserMessageBubble.stories.tsx"),
    "utf8",
  )
  const conversationSource = readFileSync(
    resolve(packageRoot, "src/Domains/Chat/AiChatConversationSurface.tsx"),
    "utf8",
  )
  const userBubbleSource = readFileSync(
    resolve(packageRoot, "src/Domains/Chat/AiChatUserMessageBubble.tsx"),
    "utf8",
  )
  const chatTypesSource = readFileSync(resolve(packageRoot, "src/model/types.ts"), "utf8")
  const chatFixtureSource = readFileSync(
    resolve(packageRoot, "src/Domains/Chat/chat-fixtures.ts"),
    "utf8",
  )

  assert.match(assistantCardSource, /AiChatAssistantMarkdownText/)
  assert.match(assistantCardSource, /readonly presentation: AiChatAssistantPresentation/)
  assert.match(assistantCardSource, /switch \(presentation\.kind\)/)
  assert.match(assistantCardSource, /assertNever/)
  assert.match(
    assistantCardSource,
    /case "completed":[\s\S]*?presentation\.failure[\s\S]*?<AssistantFailure failure=\{presentation\.failure\}/,
  )
  assert.doesNotMatch(
    assistantCardSource,
    /export interface AiChatAssistantCardProps\s*\{[^}]*readonly (content|isProcessing|failure|headerPresentation)[?:]/s,
  )
  assert.match(assistantPresentationSource, /export type AiChatAssistantPresentation\s*=/)
  assert.match(assistantPresentationSource, /export function resolveAiChatAssistantPresentation/)
  assert.match(assistantMarkdownParserSource, /readonly kind: "blockquote"/)
  assert.match(assistantMarkdownParserSource, /readonly kind: "table"/)
  assert.match(
    assistantMarkdownParserSource,
    /readonly kind: "code"[^}]*readonly language\?: string/s,
  )
  assert.match(assistantMarkdownSource, /className="chat-markdown-blockquote"/)
  assert.match(assistantMarkdownSource, /className="chat-markdown-table-scroll"/)
  assert.match(assistantMarkdownSource, /className="chat-markdown-code-header"/)
  assert.match(assistantMarkdownSource, /className="chat-inline-code"/)
  assert.match(assistantMarkdownSource, /className="chat-inline-link"/)
  assert.match(assistantMarkdownSource, /className="[^"]*chat-selectable-output[^"]*"/)
  assert.match(conversationSource, /resolveAiChatAssistantPresentation/)
  assert.match(conversationSource, /data-chat-role="assistant"/)
  assert.match(conversationSource, /className="chat-regenerate-label"/)
  assert.match(conversationSource, /className="chat-user-bubble-frame"/)
  assert.match(chatTypesSource, /readonly role: "user" \| "assistant" \| "system" \| "tool"/)
  assert.match(chatFixtureSource, /role: "system"/)
  assert.match(chatFixtureSource, /role: "tool"/)
  assert.match(
    chatFixtureSource,
    /System context: selected research PDFs are available for analysis\./,
  )
  assert.match(chatFixtureSource, /Tool result: grouped 6 PDFs into 3 recurring themes\./)
  assert.match(conversationSource, /className="chat-status-row"/)
  assert.match(
    chatTypesSource,
    /readonly timestamp\?:\s*\{[^}]*readonly label: string[^}]*readonly isTimestampVisuallySuppressed\?: boolean/s,
  )
  assert.match(conversationSource, /timestamp\.isTimestampVisuallySuppressed/)
  assert.match(chatFixtureSource, /isTimestampVisuallySuppressed:\s*true/)
  assert.match(userBubbleSource, /data-chat-role="user"/)
  assert.match(assistantStorySource, /export const StructuredResponse/)
  assert.match(assistantStorySource, /export const RichMarkdown/)
  assert.match(userStorySource, /export const CopyFeedback/)
  assert.match(assistantStorySource, /presentation:/)
  assert.match(assistantStorySource, /className="chat-message-assistant"/)
  assert.match(assistantStorySource, /className="fm-chat-message-story-frame"/)
  assert.match(userStorySource, /className="fm-chat-message-story-frame"/)
  assert.match(userStorySource, /className="chat-message-user"/)
  assert.match(userStorySource, /className="chat-user-bubble-frame"/)
  assert.match(css, /\.chat-assistant-markdown\s*{[^}]*gap:\s*var\(--fm-space-4\)/s)
  assert.match(css, /\.chat-markdown-code\s*{[^}]*font-family:\s*var\(--fm-font-mono\)/s)
  assert.match(css, /\.chat-bubble\s*{[^}]*box-sizing:\s*border-box/s)
  assert.match(css, /\.chat-bubble\s*{[^}]*width:\s*fit-content/s)
  assert.match(
    css,
    /\.chat-user-bubble-frame\s*{[^}]*max-width:\s*calc\(100% - var\(--fm-chat-user-leading-gutter\)\)/s,
  )
  assert.match(css, /\.chat-bubble\s*{[^}]*line-height:\s*var\(--fm-chat-line-body\)/s)
  assert.match(css, /\.chat-bubble\s*{[^}]*font-size:\s*var\(--fm-font-size-body\)/s)
  assert.match(
    css,
    /\.chat-markdown-paragraph,[^}]*\.chat-markdown-list-row\s*{[^}]*font-size:\s*var\(--fm-font-size-body\)/s,
  )
  assert.match(css, /\.chat-markdown-code\s*{[^}]*line-height:\s*var\(--fm-chat-line-caption\)/s)
  assert.match(
    css,
    /\.chat-markdown-code\s*{[^}]*border:\s*1px solid var\(--fm-chat-input-border\)/s,
  )
  assert.match(
    css,
    /\.chat-markdown-blockquote\s*{[^}]*border-left:\s*2px solid var\(--fm-separator\)/s,
  )
  assert.match(css, /\.chat-markdown-table\s*{[^}]*border:\s*1px solid var\(--fm-separator\)/s)
  assert.match(css, /\.chat-copy-feedback\s*{[^}]*background:\s*var\(--fm-control\)/s)
  assert.match(css, /\.chat-failure-icon\s*{[^}]*flex:\s*0 0 12px/s)
  assert.match(css, /\.chat-failure-message\s*{[^}]*min-width:\s*0/s)
  assert.match(css, /\.chat-failure-message\s*{[^}]*overflow-wrap:\s*anywhere/s)
  assert.match(
    css,
    /\.chat-timestamp-user\s*{[^}]*left:\s*calc\(-1 \* var\(--fm-chat-timestamp-offset\)\)/s,
  )
  assert.match(
    css,
    /\.fm-chat-message-story-frame\s*{[^}]*width:\s*var\(--fm-window-inspector-width\)/s,
  )
  assert.match(css, /\.chat-regenerate\s*{[^}]*padding:\s*0/s)
  assert.match(css, /\.chat-regenerate-label\s*{[^}]*border:\s*1px solid var\(--fm-separator\)/s)
  assert.match(css, /\.chat-regenerate-label\s*{[^}]*background:\s*var\(--fm-chat-popover-bg\)/s)
  assert.match(css, /\.chat-status-row\s*{[^}]*font-size:\s*var\(--fm-font-size-caption\)/s)
  assert.match(css, /\.chat-timestamp\s*{[^}]*font-size:\s*var\(--fm-font-size-caption-2\)/s)
  assert.match(css, /\.chat-bubble\s*{[^}]*overflow-wrap:\s*anywhere/s)
  assert.match(css, /\.chat-markdown-paragraph[^}]*overflow-wrap:\s*anywhere/s)
}
