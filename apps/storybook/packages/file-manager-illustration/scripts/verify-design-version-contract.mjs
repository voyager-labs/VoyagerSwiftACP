import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { resolve } from "node:path"

export function verifyDesignVersionContract(packageRoot, storybookRoot, css) {
  const designVersionSource = readFileSync(
    resolve(packageRoot, "src/Foundations/DesignVersion.tsx"),
    "utf8",
  )
  const previewSource = readFileSync(resolve(storybookRoot, ".storybook/preview.tsx"), "utf8")
  const aiChatInputBarSource = readFileSync(
    resolve(packageRoot, "src/Domains/Chat/AiChatInputBar.tsx"),
    "utf8",
  )
  const aiChatNativeMenuSource = readFileSync(
    resolve(packageRoot, "src/Domains/Chat/AiChatNativeMenuSelector.tsx"),
    "utf8",
  )
  const aiChatInputStorySource = readFileSync(
    resolve(packageRoot, "src/Domains/Chat/AiChatInputBar.stories.tsx"),
    "utf8",
  )

  assert.match(
    designVersionSource,
    /export const designVersionIDs = \{\s*current:\s*"current",\s*}\s*as const/s,
  )
  assert.match(previewSource, /designVersion:\s*designVersionIDs\.current/)
  assert.match(previewSource, /data-design-version=\{designVersion\}/)
  assert.match(aiChatInputBarSource, /fm-ai-chat-native-attachment/)
  assert.match(aiChatNativeMenuSource, /fm-ai-chat-native-menu-selector/)
  assert.doesNotMatch(designVersionSource, /candidate-material-controls/)
  assert.doesNotMatch(previewSource, /candidate-material-controls/)
  assert.doesNotMatch(aiChatInputBarSource, /candidate-material-controls/)
  assert.doesNotMatch(css, /candidate-material-controls|--fm-chat-candidate-input-background/)
  assert.match(
    aiChatInputStorySource,
    /parameters:\s*{\s*layout:\s*["']fullscreen["']\s*}/,
    "AiChatInputBar stories must use the full Storybook canvas width",
  )
  assert.match(
    aiChatInputStorySource,
    /className=["']fm-ai-chat-input-story-canvas["']/,
    "AiChatInputBar stories must separate the full-width canvas from the constrained specimen frame",
  )
  assert.match(
    css,
    /\.fm-ai-chat-input-story-canvas\s*{[^}]*width:\s*100%;/s,
    "AiChatInputBar story canvas must fill its available width",
  )
  assert.match(
    css,
    /\.fm-ai-chat-input-story-canvas\s*{[^}]*place-items:\s*start;/s,
    "AiChatInputBar specimen must stay at the canvas origin instead of floating in the center",
  )
  assert.match(
    css,
    /\.fm-ai-chat-input-story-frame\s*{[^}]*max-width:\s*100%;/s,
    "AiChatInputBar specimen must not widen the Storybook canvas below 300px",
  )
  assert.match(
    css,
    /\.fm-ai-chat-input\s*{[^}]*box-sizing:\s*border-box;[^}]*width:\s*100%;/s,
    "AiChatInputBar border and padding must remain inside the specimen width",
  )
  assert.match(
    css,
    /\.fm-ai-chat-context-groups\s*{[^}]*flex:\s*1 1 0;[^}]*overscroll-behavior-inline:\s*contain;/s,
    "Request-context scrolling must stay inside the remaining row width",
  )
  assert.doesNotMatch(css, /--fm-chat-candidate-control-material/)
}
