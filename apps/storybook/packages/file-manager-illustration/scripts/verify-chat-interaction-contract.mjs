import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { resolve } from "node:path"

export function verifyChatInteractionContract(packageRoot) {
  const source = (relativePath) => readFileSync(resolve(packageRoot, relativePath), "utf8")

  const inputSource = source("src/Domains/Chat/AiChatInputBar.tsx")
  const inputStorySource = source("src/Domains/Chat/AiChatInputBar.stories.tsx")
  const viewSource = source("src/Domains/Chat/AiChatView.tsx")
  const viewStorySource = source("src/Domains/Chat/AiChatView.stories.tsx")
  const conversationSource = source("src/Domains/Chat/AiChatConversationSurface.tsx")
  const rootSource = source("src/FileManagerIllustration.tsx")
  const rootStorySource = source("src/Stories/FileManagerIllustration.stories.tsx")
  const typesSource = source("src/model/types.ts")

  assert.match(inputSource, /presentation\.action\.kind === "submit"/)
  assert.match(inputSource, /actions\?\.onSubmit\?\.\(\)/)
  assert.match(inputSource, /actions\?\.onStop/)
  assert.match(inputSource, /onChange=\{actions\?\.onModelSelected\}/)
  assert.match(inputSource, /onChange=\{actions\?\.onThinkingSelected\}/)
  assert.match(inputSource, /actions\?\.onRemoveContextItem\?\./)
  assert.match(inputSource, /presentation\.isComposerEditingDisabled/)
  assert.match(inputSource, /text\/uri-list/)
  assert.match(inputSource, /actions\.onAttachmentsDropped\(\{ files, urls \}\)/)
  assert.match(typesSource, /readonly onAttachmentsDropped\?:/)

  assert.match(inputStorySource, /export const ReadyDraft[\s\S]*?play:/)
  assert.match(inputStorySource, /export const Selectors[\s\S]*?play:/)
  assert.match(inputStorySource, /export const PendingResolution[\s\S]*?play:/)
  assert.match(inputStorySource, /export const ProcessingNextTurn[\s\S]*?play:/)
  assert.match(inputStorySource, /export const WithRequestContext[\s\S]*?play:/)

  assert.match(conversationSource, /failure: streamingAssistant\.failure/)
  assert.match(conversationSource, /onErrorRecovery=\{onErrorRecovery\}/)
  assert.match(viewSource, /onErrorRecovery=\{onErrorRecovery\}/)
  assert.match(rootSource, /chatOnErrorRecovery/)
  assert.match(rootStorySource, /export const ChatRecovery[\s\S]*?chatOnErrorRecovery/)
  assert.match(viewStorySource, /export const Recovery[\s\S]*?onErrorRecovery/)
}
