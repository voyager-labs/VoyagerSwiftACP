export type AiChatMarkdownTableAlignment = "left" | "center" | "right" | "none"

export interface AiChatMarkdownTableCell {
  readonly id: string
  readonly text: string
}

export interface AiChatMarkdownTableRow {
  readonly id: string
  readonly cells: readonly AiChatMarkdownTableCell[]
}

export type AssistantMarkdownBlock =
  | {
      readonly id: string
      readonly kind: "heading"
      readonly level: 1 | 2 | 3
      readonly text: string
    }
  | { readonly id: string; readonly kind: "paragraph"; readonly text: string }
  | { readonly id: string; readonly kind: "bullet"; readonly text: string }
  | {
      readonly id: string
      readonly kind: "numbered"
      readonly number: number
      readonly text: string
    }
  | { readonly id: string; readonly kind: "blockquote"; readonly text: string }
  | {
      readonly id: string
      readonly kind: "table"
      readonly alignments: readonly AiChatMarkdownTableAlignment[]
      readonly rows: readonly AiChatMarkdownTableRow[]
    }
  | {
      readonly id: string
      readonly kind: "code"
      readonly text: string
      readonly language?: string
    }

export function parseAssistantMarkdown(content: string): readonly AssistantMarkdownBlock[] {
  const lines = content.replace(/\r\n?/g, "\n").split("\n")
  const blocks: AssistantMarkdownBlock[] = []
  const paragraphLines: string[] = []
  let lineIndex = 0

  const flushParagraph = () => {
    if (paragraphLines.length === 0) return
    blocks.push({
      id: `paragraph-${lineIndex - paragraphLines.length}`,
      kind: "paragraph",
      text: paragraphLines.join(" "),
    })
    paragraphLines.length = 0
  }

  while (lineIndex < lines.length) {
    const sourceLine = lines[lineIndex] ?? ""
    const line = sourceLine.trimEnd()

    if (line.trimStart().startsWith("```")) {
      flushParagraph()
      const info = line.trimStart().slice(3).trim().split(/\s+/, 1)[0]
      const codeLines: string[] = []
      lineIndex += 1
      while (lineIndex < lines.length && !(lines[lineIndex] ?? "").trimStart().startsWith("```")) {
        codeLines.push(lines[lineIndex] ?? "")
        lineIndex += 1
      }
      if (lineIndex < lines.length) lineIndex += 1
      blocks.push(
        info === ""
          ? {
              id: `code-${lineIndex - codeLines.length - 1}`,
              kind: "code",
              text: codeLines.join("\n"),
            }
          : {
              id: `code-${lineIndex - codeLines.length - 1}`,
              kind: "code",
              text: codeLines.join("\n"),
              language: info,
            },
      )
      continue
    }

    if (line.trim() === "") {
      flushParagraph()
      lineIndex += 1
      continue
    }

    const tableHeader = tableCells(line)
    const tableAlignments = tableDelimiter(lines[lineIndex + 1] ?? "")
    if (tableHeader != null && tableAlignments != null) {
      flushParagraph()
      const tableStart = lineIndex
      const rows: AiChatMarkdownTableRow[] = [
        makeTableRow(tableHeader, tableAlignments.length, lineIndex),
      ]
      lineIndex += 2
      while (lineIndex < lines.length) {
        const row = tableCells(lines[lineIndex] ?? "")
        if (row == null) break
        rows.push(makeTableRow(row, tableAlignments.length, lineIndex))
        lineIndex += 1
      }
      blocks.push({ id: `table-${tableStart}`, kind: "table", alignments: tableAlignments, rows })
      continue
    }

    const heading = /^(#{1,3})\s+(.+)$/.exec(line)
    if (heading?.[1] != null && heading[2] != null) {
      flushParagraph()
      const level = heading[1].length === 1 ? 1 : heading[1].length === 2 ? 2 : 3
      blocks.push({ id: `heading-${lineIndex}`, kind: "heading", level, text: heading[2] })
      lineIndex += 1
      continue
    }

    const blockquote = /^\s*>\s?(.*)$/.exec(line)
    if (blockquote?.[1] != null) {
      flushParagraph()
      const quoteLines = [blockquote[1]]
      lineIndex += 1
      while (lineIndex < lines.length) {
        const continuation = /^\s*>\s?(.*)$/.exec(lines[lineIndex] ?? "")
        if (continuation?.[1] == null) break
        quoteLines.push(continuation[1])
        lineIndex += 1
      }
      blocks.push({
        id: `blockquote-${lineIndex - quoteLines.length}`,
        kind: "blockquote",
        text: quoteLines.join("\n"),
      })
      continue
    }

    const bullet = /^[-*]\s+(.+)$/.exec(line)
    if (bullet?.[1] != null) {
      flushParagraph()
      blocks.push({ id: `bullet-${lineIndex}`, kind: "bullet", text: bullet[1] })
      lineIndex += 1
      continue
    }

    const numbered = /^(\d+)\.\s+(.+)$/.exec(line)
    if (numbered?.[1] != null && numbered[2] != null) {
      flushParagraph()
      blocks.push({
        id: `numbered-${lineIndex}`,
        kind: "numbered",
        number: Number.parseInt(numbered[1], 10),
        text: numbered[2],
      })
      lineIndex += 1
      continue
    }

    paragraphLines.push(line.trim())
    lineIndex += 1
  }

  flushParagraph()
  return blocks
}

function tableCells(line: string): readonly string[] | undefined {
  const trimmed = line.trim()
  if (!trimmed.includes("|")) return undefined
  const cells = trimmed.split("|")
  if (trimmed.startsWith("|")) cells.shift()
  if (trimmed.endsWith("|")) cells.pop()
  return cells.length === 0 ? undefined : cells.map((cell) => cell.trim())
}

function tableDelimiter(line: string): readonly AiChatMarkdownTableAlignment[] | undefined {
  const cells = tableCells(line)
  if (cells == null) return undefined
  const alignments: AiChatMarkdownTableAlignment[] = []
  for (const cell of cells) {
    if (!/^:?-{3,}:?$/.test(cell)) return undefined
    if (cell.startsWith(":") && cell.endsWith(":")) alignments.push("center")
    else if (cell.startsWith(":")) alignments.push("left")
    else if (cell.endsWith(":")) alignments.push("right")
    else alignments.push("none")
  }
  return alignments
}

function makeTableRow(
  row: readonly string[],
  columnCount: number,
  sourceLine: number,
): AiChatMarkdownTableRow {
  return {
    id: `table-row-${sourceLine}`,
    cells: Array.from({ length: columnCount }, (_, columnIndex) => ({
      id: `table-cell-${sourceLine}-${columnIndex}`,
      text: row[columnIndex] ?? "",
    })),
  }
}
