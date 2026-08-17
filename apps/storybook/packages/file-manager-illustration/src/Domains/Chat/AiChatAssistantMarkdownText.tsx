import hljs from "highlight.js/lib/common"
import type { FC, ReactNode } from "react"
import { AiChatCopyFeedback, type AiChatCopyFeedbackState } from "./AiChatCopyFeedback"
import {
  type AiChatMarkdownTableAlignment,
  type AssistantMarkdownBlock,
  parseAssistantMarkdown,
} from "./AiChatMarkdownParser"

export interface AiChatAssistantMarkdownTextProps {
  readonly content: string
  readonly copyFeedback?: AiChatCopyFeedbackState
}

export const AiChatAssistantMarkdownText: FC<AiChatAssistantMarkdownTextProps> = ({
  content,
  copyFeedback,
}) => (
  <div className="chat-assistant-markdown chat-selectable-output">
    {parseAssistantMarkdown(content).map(renderBlock)}
    {copyFeedback == null ? null : <AiChatCopyFeedback state={copyFeedback} />}
  </div>
)

AiChatAssistantMarkdownText.displayName = "AiChatAssistantMarkdownText"

function renderBlock(block: AssistantMarkdownBlock): ReactNode {
  const key = block.id
  switch (block.kind) {
    case "heading":
      return renderHeading(block.level, block.text, key)
    case "paragraph":
      return (
        <p key={key} className="chat-markdown-paragraph">
          {renderInline(block.text, key)}
        </p>
      )
    case "bullet":
      return renderListRow("•", block.text, key, "chat-markdown-bullet")
    case "numbered":
      return renderListRow(`${block.number}.`, block.text, key, "chat-markdown-number")
    case "blockquote":
      return (
        <blockquote key={key} className="chat-markdown-blockquote">
          {renderInline(block.text, key)}
        </blockquote>
      )
    case "table":
      return (
        <div key={key} className="chat-markdown-table-scroll">
          <table className="chat-markdown-table">
            <tbody>
              {block.rows.map((row, rowIndex) => (
                <tr key={row.id}>
                  {row.cells.map((cell, columnIndex) =>
                    renderTableCell(
                      cell.text,
                      block.alignments[columnIndex] ?? "none",
                      rowIndex,
                      cell.id,
                    ),
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )
    case "code":
      return (
        <figure key={key} className="chat-markdown-code">
          <figcaption className="chat-markdown-code-header">{block.language ?? "Code"}</figcaption>
          <pre>
            <code>{renderCode(block.text, block.language)}</code>
          </pre>
        </figure>
      )
    default:
      return assertNever(block)
  }
}

function renderHeading(level: 1 | 2 | 3, text: string, key: string): ReactNode {
  const content = renderInline(text, key)
  switch (level) {
    case 1:
      return (
        <h2 key={key} className="chat-markdown-heading" data-level={level}>
          {content}
        </h2>
      )
    case 2:
      return (
        <h3 key={key} className="chat-markdown-heading" data-level={level}>
          {content}
        </h3>
      )
    case 3:
      return (
        <h4 key={key} className="chat-markdown-heading" data-level={level}>
          {content}
        </h4>
      )
    default:
      return assertNever(level)
  }
}

function renderListRow(marker: string, text: string, key: string, markerClass: string): ReactNode {
  return (
    <div key={key} className="chat-markdown-list-row">
      <span className={markerClass} aria-hidden="true">
        {marker}
      </span>
      <span>{renderInline(text, key)}</span>
    </div>
  )
}

function renderTableCell(
  text: string,
  alignment: AiChatMarkdownTableAlignment,
  rowIndex: number,
  key: string,
): ReactNode {
  const Cell = rowIndex === 0 ? "th" : "td"
  return (
    <Cell key={key} data-alignment={alignment}>
      {renderInline(text, key)}
    </Cell>
  )
}

function renderInline(text: string, keyPrefix: string): readonly ReactNode[] {
  const nodes: ReactNode[] = []
  const tokenPattern = /(`[^`]+`|\*\*[^*]+\*\*|__[^_]+__|\*[^*]+\*|_[^_]+_|\[[^\]]+\]\([^)]+\))/g
  let cursor = 0
  for (const match of text.matchAll(tokenPattern)) {
    const index = match.index
    const token = match[0]
    if (index > cursor) nodes.push(text.slice(cursor, index))
    nodes.push(renderInlineToken(token, `${keyPrefix}-inline-${index}`))
    cursor = index + token.length
  }
  if (cursor < text.length) nodes.push(text.slice(cursor))
  return nodes
}

function renderInlineToken(token: string, key: string): ReactNode {
  if (token.startsWith("`"))
    return (
      <code key={key} className="chat-inline-code">
        {token.slice(1, -1)}
      </code>
    )
  if (token.startsWith("**") || token.startsWith("__")) {
    return <strong key={key}>{renderInline(token.slice(2, -2), key)}</strong>
  }
  if (token.startsWith("*") || token.startsWith("_")) {
    return <em key={key}>{renderInline(token.slice(1, -1), key)}</em>
  }
  const link = /^\[([^\]]+)\]\(([^)]+)\)$/.exec(token)
  if (link?.[1] != null && link[2] != null && isSafeLink(link[2])) {
    const isExternal = /^https:/i.test(link[2])
    return (
      <a
        key={key}
        className="chat-inline-link"
        href={link[2]}
        {...(isExternal ? { target: "_blank", rel: "noreferrer" } : {})}
      >
        {renderInline(link[1], key)}
      </a>
    )
  }
  return token
}

function isSafeLink(destination: string): boolean {
  return /^(https?:|mailto:)/i.test(destination)
}

// highlight.js가 생성한 HTML을 React 노드로 변환한다.
// 언어가 없거나 highlight.js가 지원하지 않으면 원문 그대로 반환한다(네이티브 fallback 계약과 동일).
function renderCode(code: string, language: string | undefined): ReactNode {
  if (language == null || hljs.getLanguage(language) == null) return code
  try {
    const body = new DOMParser().parseFromString(
      hljs.highlight(code, { language }).value,
      "text/html",
    ).body
    const nodes: ReactNode[] = []
    body.childNodes.forEach((node, index) => nodes.push(fromNode(node, index)))
    return nodes
  } catch {
    return code
  }
}

function fromNode(node: Node, index: number): ReactNode {
  if (node.nodeType === Node.TEXT_NODE) return node.textContent
  if (node.nodeType === Node.ELEMENT_NODE) {
    const element = node as Element
    const children: ReactNode[] = []
    element.childNodes.forEach((child, childIndex) => children.push(fromNode(child, childIndex)))
    return children.length === 0 ? (
      ""
    ) : (
      <span key={index} className={element.className}>
        {children}
      </span>
    )
  }
  return null
}

function assertNever(value: never): never {
  throw new Error(`Unsupported assistant markdown value: ${JSON.stringify(value)}`)
}
