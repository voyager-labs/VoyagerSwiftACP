import Foundation

enum AiChatMarkdownParser {
    static func parse(_ source: String) -> AiChatMarkdownDocument {
        var parser = Parser(source: source)
        return parser.parse()
    }
}

private struct Parser {
    let source: String
    let lines: [SourceLine]
    var blockIndex = 0
    var fingerprintOccurrences: [String: Int] = [:]

    init(source: String) {
        self.source = source
        lines = SourceLine.split(source)
    }

    mutating func parse() -> AiChatMarkdownDocument {
        var blocks: [AiChatMarkdownDocument.Block] = []
        while blockIndex < lines.count {
            let draft: BlockDraft = if lines[blockIndex].content.isEmpty {
                makeFallbackDraft(until: consumeBlankLines(from: blockIndex))
            } else {
                parseBlock()
            }
            if let block = makeBlock(from: draft) {
                blocks.append(block)
            }
            blockIndex = draft.lineRange.upperBound
        }
        return AiChatMarkdownDocument(rawSource: source, blocks: blocks)
    }

    private mutating func parseBlock() -> BlockDraft {
        if let opening = FenceOpening(lines[blockIndex].content) {
            return parseFence(opening)
        }
        if let table = parseTable() {
            return table
        }
        if isBlockquote(lines[blockIndex].content) {
            return parseBlockquote()
        }
        if let heading = parseHeading(lines[blockIndex].content) {
            return singleLineBlock(kind: .heading(level: heading.level), text: heading.text)
        }
        if let bullet = parseBullet(lines[blockIndex].content) {
            return singleLineBlock(kind: .bullet, text: bullet)
        }
        if let numbered = parseNumbered(lines[blockIndex].content) {
            return singleLineBlock(kind: .numbered(number: numbered.number), text: numbered.text)
        }
        if isUnsupportedStart(at: blockIndex) {
            return makeFallbackDraft(until: paragraphEnd(from: blockIndex))
        }
        return parseParagraph()
    }

    private mutating func parseFence(_ opening: FenceOpening) -> BlockDraft {
        guard let closingIndex = closingFenceIndex(after: blockIndex, opening: opening) else {
            return makeFallbackDraft(until: lines.count)
        }
        let coreEnd = closingIndex + 1
        let end = consumeBlankLines(from: coreEnd)
        let payloadStart = lines[blockIndex].endUTF8
        let payloadEnd = lines[closingIndex].startUTF8
        let payload = sourceSlice(payloadStart ..< payloadEnd)
        let code = AiChatMarkdownDocument.CodePayload(
            payload: payload,
            originalLanguage: opening.language,
            normalizedLanguage: normalizeLanguage(opening.language),
            openingIndentation: opening.indentation,
            fenceDelimiter: opening.delimiter,
            originalInfoString: opening.infoString,
            trailingMetadata: opening.trailingMetadata,
        )
        return BlockDraft(
            kind: .code,
            lineRange: blockIndex ..< end,
            identityLineRange: blockIndex ..< coreEnd,
            projections: .init(rendered: payload, search: payload, plain: payload),
            code: code,
        )
    }

    private func closingFenceIndex(after openingIndex: Int, opening: FenceOpening) -> Int? {
        guard openingIndex + 1 < lines.count else { return nil }
        return (openingIndex + 1 ..< lines.count).first { opening.matchesClosing(lines[$0].content) }
    }

    private mutating func parseTable() -> BlockDraft? {
        guard blockIndex + 1 < lines.count,
              let headerCells = tableCells(lines[blockIndex].content),
              let alignments = tableDelimiter(lines[blockIndex + 1].content),
              headerCells.count == alignments.count
        else {
            return nil
        }

        var rows = [headerCells]
        var cursor = blockIndex + 2
        while cursor < lines.count,
              !lines[cursor].content.isEmpty,
              let cells = tableCells(lines[cursor].content),
              cells.count == headerCells.count
        {
            rows.append(cells)
            cursor += 1
        }
        let coreEnd = cursor
        let end = consumeBlankLines(from: coreEnd)
        let projectedCells = rows.map { row in
            row.map { cell in
                let inline = InlineProjection(text: cell)
                return AiChatMarkdownDocument.TableCell(text: inline.text, inlineIntents: inline.intents)
            }
        }
        let projectedRows = projectedCells.map { $0.map(\.text) }
        let rendered = projectedRows.flatMap(\.self).joined(separator: " ")
        let plain = projectedRows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
        return BlockDraft(
            kind: .table,
            lineRange: blockIndex ..< end,
            identityLineRange: blockIndex ..< coreEnd,
            projections: .init(rendered: rendered, search: rendered, plain: plain),
            table: .init(cells: projectedCells, alignments: alignments),
        )
    }

    private mutating func parseBlockquote() -> BlockDraft {
        var cursor = blockIndex
        var contents: [String] = []
        while cursor < lines.count, let content = blockquoteContent(lines[cursor].content) {
            contents.append(content)
            cursor += 1
        }
        let coreEnd = cursor
        let end = consumeBlankLines(from: coreEnd)
        let inline = InlineProjection(text: contents.joined(separator: "\n"))
        return BlockDraft(
            kind: .blockquote,
            lineRange: blockIndex ..< end,
            identityLineRange: blockIndex ..< coreEnd,
            projections: .init(rendered: inline.text, search: inline.text, plain: inline.text),
            inlineIntents: inline.intents,
        )
    }

    private mutating func singleLineBlock(kind: AiChatMarkdownDocument.BlockKind, text: String) -> BlockDraft {
        let inline = InlineProjection(text: text)
        let coreEnd = blockIndex + 1
        let end = consumeBlankLines(from: coreEnd)
        return BlockDraft(
            kind: kind,
            lineRange: blockIndex ..< end,
            identityLineRange: blockIndex ..< coreEnd,
            projections: .init(rendered: inline.text, search: inline.text, plain: inline.text),
            inlineIntents: inline.intents,
        )
    }

    private mutating func parseParagraph() -> BlockDraft {
        let end = paragraphEnd(from: blockIndex)
        let coreEnd = firstBlankLine(in: blockIndex ..< end) ?? end
        let content = lines[blockIndex ..< coreEnd].map(\.content).joined(separator: "\n")
        let inline = InlineProjection(text: content)
        return BlockDraft(
            kind: .paragraph,
            lineRange: blockIndex ..< end,
            identityLineRange: blockIndex ..< coreEnd,
            projections: .init(rendered: inline.text, search: inline.text, plain: inline.text),
            inlineIntents: inline.intents,
        )
    }

    private func paragraphEnd(from start: Int) -> Int {
        var cursor = start
        while cursor < lines.count {
            if lines[cursor].content.isEmpty {
                return consumeBlankLines(from: cursor)
            }
            if cursor > start, beginsRecognizedBlock(at: cursor) {
                break
            }
            cursor += 1
        }
        return cursor
    }

    private func beginsRecognizedBlock(at index: Int) -> Bool {
        FenceOpening(lines[index].content) != nil
            || isBlockquote(lines[index].content)
            || parseHeading(lines[index].content) != nil
            || parseBullet(lines[index].content) != nil
            || parseNumbered(lines[index].content) != nil
            || isTableStart(at: index)
    }

    private func isUnsupportedStart(at index: Int) -> Bool {
        let trimmed = lines[index].content.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            return true
        }
        if trimmed.hasPrefix("<"), trimmed.hasSuffix(">") {
            return true
        }
        return trimmed.hasPrefix("|") && !isTableStart(at: index)
    }

    private func isTableStart(at index: Int) -> Bool {
        guard index + 1 < lines.count,
              let header = tableCells(lines[index].content),
              let delimiter = tableDelimiter(lines[index + 1].content)
        else {
            return false
        }
        return !header.isEmpty && header.count == delimiter.count
    }

    private func consumeBlankLines(from start: Int) -> Int {
        var cursor = start
        while cursor < lines.count, lines[cursor].content.isEmpty {
            cursor += 1
        }
        return cursor
    }

    private func firstBlankLine(in range: Range<Int>) -> Int? {
        range.first { lines[$0].content.isEmpty }
    }

    private func makeFallbackDraft(until end: Int) -> BlockDraft {
        let range = sourceRange(for: blockIndex ..< end)
        let raw = sourceSlice(range)
        return BlockDraft(
            kind: .paragraph,
            lineRange: blockIndex ..< end,
            identityLineRange: blockIndex ..< end,
            projections: .init(rendered: raw, search: raw, plain: raw),
        )
    }

    private mutating func makeBlock(from draft: BlockDraft) -> AiChatMarkdownDocument.Block? {
        let range = sourceRange(for: draft.lineRange)
        let identityRange = sourceRange(for: draft.identityLineRange)
        let raw = sourceSlice(range)
        let identityRaw = sourceSlice(identityRange)
        let fingerprint = stableFingerprint("\(draft.kind.identityTag)\u{1F}\(identityRaw)")
        let occurrence = fingerprintOccurrences[fingerprint, default: 0]
        fingerprintOccurrences[fingerprint] = occurrence + 1
        return AiChatMarkdownDocument.Block(
            id: .init(rawValue: "\(draft.kind.identityTag)-\(fingerprint)-\(occurrence)"),
            kind: draft.kind,
            sourceRange: .init(utf8Offsets: range),
            rawSlice: raw,
            projections: draft.projections,
            inlineIntents: draft.inlineIntents,
            code: draft.code,
            table: draft.table,
        )
    }

    private func sourceRange(for lineRange: Range<Int>) -> Range<Int> {
        guard let first = lineRange.first else {
            let offset = lineRange.lowerBound < lines.count ? lines[lineRange.lowerBound].startUTF8 : source.utf8.count
            return offset ..< offset
        }
        return lines[first].startUTF8 ..< lines[lineRange.upperBound - 1].endUTF8
    }

    private func sourceSlice(_ range: Range<Int>) -> String {
        AiChatMarkdownDocument.SourceRange(utf8Offsets: range).rawSlice(in: source) ?? ""
    }
}

private struct BlockDraft {
    let kind: AiChatMarkdownDocument.BlockKind
    let lineRange: Range<Int>
    let identityLineRange: Range<Int>
    let projections: AiChatMarkdownDocument.Projections
    var inlineIntents: [AiChatMarkdownDocument.InlineIntent] = []
    var code: AiChatMarkdownDocument.CodePayload?
    var table: AiChatMarkdownDocument.TableMetadata?
}

private struct SourceLine {
    let content: String
    let startUTF8: Int
    let endUTF8: Int

    static func split(_ source: String) -> [SourceLine] {
        guard !source.isEmpty else { return [] }
        let utf8 = source.utf8
        var result: [SourceLine] = []
        var lineStart = utf8.startIndex
        var index = utf8.startIndex
        while index < utf8.endIndex {
            if utf8[index] == 0x0A {
                let afterNewline = utf8.index(after: index)
                var contentEnd = index
                if contentEnd > lineStart {
                    let previous = utf8.index(before: contentEnd)
                    if utf8[previous] == 0x0D { contentEnd = previous }
                }
                result.append(makeLine(utf8, start: lineStart, contentEnd: contentEnd, end: afterNewline))
                lineStart = afterNewline
            }
            index = utf8.index(after: index)
        }
        if lineStart < utf8.endIndex {
            result.append(makeLine(utf8, start: lineStart, contentEnd: utf8.endIndex, end: utf8.endIndex))
        }
        return result
    }

    private static func makeLine(
        _ utf8: String.UTF8View,
        start: String.UTF8View.Index,
        contentEnd: String.UTF8View.Index,
        end: String.UTF8View.Index,
    ) -> SourceLine {
        SourceLine(
            content: String(bytes: utf8[start ..< contentEnd], encoding: .utf8) ?? "",
            startUTF8: utf8.distance(from: utf8.startIndex, to: start),
            endUTF8: utf8.distance(from: utf8.startIndex, to: end),
        )
    }
}

private struct FenceOpening {
    let indentation: String
    let delimiter: String
    let infoString: String?
    let language: String?
    let trailingMetadata: String?

    init?(_ line: String) {
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        let remainder = line.dropFirst(indentation.count)
        let ticks = remainder.prefix { $0 == "`" }
        guard ticks.count >= 3 else { return nil }
        let info = String(remainder.dropFirst(ticks.count)).trimmingCharacters(in: .whitespaces)
        let components = info.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        self.indentation = indentation
        delimiter = String(ticks)
        infoString = info.isEmpty ? nil : info
        language = components.first.map(String.init)
        trailingMetadata = components.count == 2 ? String(components[1]) : nil
    }

    func matchesClosing(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        let ticks = trimmed.prefix { $0 == "`" }
        return ticks.count >= delimiter.count
            && trimmed.dropFirst(ticks.count).allSatisfy(\.isWhitespace)
    }
}

private struct InlineProjection {
    let text: String
    let intents: [AiChatMarkdownDocument.InlineIntent]

    init(text source: String) {
        var output = ""
        var intents: [AiChatMarkdownDocument.InlineIntent] = []
        var index = source.startIndex
        while index < source.endIndex {
            if let match = inlineCode(in: source, at: index) {
                let range = output.count ..< output.count + match.value.count
                output += match.value
                intents.append(.code(.init(characterOffsets: range)))
                index = match.end
            } else if let match = imageOrLink(in: source, at: index) {
                let offset = output.count
                if match.isImage {
                    output += match.label
                } else {
                    let label = InlineProjection(text: match.label)
                    let range = offset ..< offset + label.text.count
                    output += label.text
                    intents.append(.link(
                        range: .init(characterOffsets: range),
                        destination: match.destination,
                    ))
                    intents += label.intents.map { $0.shifted(by: offset) }
                }
                index = match.end
            } else if let match = emphasis(in: source, at: index) {
                let offset = output.count
                let content = InlineProjection(text: match.content)
                let range = AiChatMarkdownDocument.SearchRange(
                    characterOffsets: offset ..< offset + content.text.count,
                )
                output += content.text
                intents.append(match.isStrong ? .strong(range) : .emphasis(range))
                intents += content.intents.map { $0.shifted(by: offset) }
                index = match.end
            } else if source[index] == "*" || source[index] == "_" {
                output += source[index...]
                index = source.endIndex
            } else {
                output.append(source[index])
                index = source.index(after: index)
            }
        }
        text = output
        self.intents = intents
    }
}

private struct InlineMatch {
    let value: String
    let end: String.Index
}

private struct LinkMatch {
    let label: String
    let destination: String
    let isImage: Bool
    let end: String.Index
}

private struct EmphasisMatch {
    let content: String
    let isStrong: Bool
    let end: String.Index
}

private func inlineCode(in source: String, at index: String.Index) -> InlineMatch? {
    guard source[index] == "`" else { return nil }
    let contentStart = source.index(after: index)
    guard let closing = source[contentStart...].firstIndex(of: "`") else { return nil }
    return InlineMatch(value: String(source[contentStart ..< closing]), end: source.index(after: closing))
}

private func imageOrLink(in source: String, at index: String.Index) -> LinkMatch? {
    let isImage = source[index] == "!"
    let labelStart: String.Index
    if isImage {
        let bracket = source.index(after: index)
        guard bracket < source.endIndex, source[bracket] == "[" else { return nil }
        labelStart = source.index(after: bracket)
    } else {
        guard source[index] == "[" else { return nil }
        labelStart = source.index(after: index)
    }
    guard let labelEnd = source[labelStart...].firstIndex(of: "]") else { return nil }
    let parenthesis = source.index(after: labelEnd)
    guard parenthesis < source.endIndex, source[parenthesis] == "(" else { return nil }
    let destinationStart = source.index(after: parenthesis)
    guard let destinationEnd = source[destinationStart...].firstIndex(of: ")") else { return nil }
    return LinkMatch(
        label: String(source[labelStart ..< labelEnd]),
        destination: String(source[destinationStart ..< destinationEnd]),
        isImage: isImage,
        end: source.index(after: destinationEnd),
    )
}

private func emphasis(in source: String, at index: String.Index) -> EmphasisMatch? {
    guard source[index] == "*" || source[index] == "_" else { return nil }
    let marker = source[index]
    let next = source.index(after: index)
    let markerLength = next < source.endIndex && source[next] == marker ? 2 : 1
    let contentStart = source.index(index, offsetBy: markerLength)
    guard contentStart < source.endIndex,
          let closing = emphasisClosingDelimiter(
              in: source,
              after: contentStart,
              marker: marker,
              markerLength: markerLength,
          ),
          closing.lowerBound > contentStart
    else {
        return nil
    }
    return EmphasisMatch(
        content: String(source[contentStart ..< closing.lowerBound]),
        isStrong: markerLength == 2,
        end: closing.upperBound,
    )
}

private func emphasisClosingDelimiter(
    in source: String,
    after contentStart: String.Index,
    marker: Character,
    markerLength: Int,
) -> Range<String.Index>? {
    var cursor = contentStart
    while cursor < source.endIndex {
        guard source[cursor] == marker else {
            cursor = source.index(after: cursor)
            continue
        }
        let runStart = cursor
        while cursor < source.endIndex, source[cursor] == marker {
            cursor = source.index(after: cursor)
        }
        let runLength = source.distance(from: runStart, to: cursor)
        if markerLength == 1, runLength == 1 {
            return runStart ..< cursor
        }
        if markerLength == 2, runLength >= 2 {
            return runStart ..< source.index(runStart, offsetBy: 2)
        }
    }
    return nil
}

private extension AiChatMarkdownDocument.InlineIntent {
    func shifted(by offset: Int) -> Self {
        switch self {
        case let .emphasis(range): .emphasis(range.shifted(by: offset))
        case let .strong(range): .strong(range.shifted(by: offset))
        case let .link(range, destination): .link(range: range.shifted(by: offset), destination: destination)
        case let .code(range): .code(range.shifted(by: offset))
        }
    }
}

private extension AiChatMarkdownDocument.SearchRange {
    func shifted(by offset: Int) -> Self {
        .init(characterOffsets: characterOffsets.lowerBound + offset ..< characterOffsets.upperBound + offset)
    }
}

private func parseHeading(_ line: String) -> (level: Int, text: String)? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    let count = trimmed.prefix { $0 == "#" }.count
    guard (1 ... 6).contains(count), trimmed.dropFirst(count).first == " " else { return nil }
    let text = trimmed.dropFirst(count + 1).trimmingCharacters(in: .whitespaces)
    return text.isEmpty ? nil : (count, text)
}

private func parseBullet(_ line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.hasPrefix("- [ ] "), !trimmed.hasPrefix("- [x] "), !trimmed.hasPrefix("- [X] "),
          trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
    else {
        return nil
    }
    let text = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
    return text.isEmpty ? nil : text
}

private func parseNumbered(_ line: String) -> (number: Int, text: String)? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let dot = trimmed.firstIndex(of: ".") else { return nil }
    let digits = trimmed[..<dot]
    let afterDot = trimmed.index(after: dot)
    guard !digits.isEmpty, digits.allSatisfy(\.isNumber), afterDot < trimmed.endIndex, trimmed[afterDot] == " " else {
        return nil
    }
    let text = trimmed[trimmed.index(after: afterDot)...].trimmingCharacters(in: .whitespaces)
    guard let number = Int(digits), !text.isEmpty else { return nil }
    return (number, text)
}

private func isBlockquote(_ line: String) -> Bool {
    blockquoteContent(line) != nil
}

private func blockquoteContent(_ line: String) -> String? {
    let trimmed = line.drop { $0 == " " || $0 == "\t" }
    guard trimmed.first == ">" else { return nil }
    var content = trimmed.dropFirst()
    if content.first == " " { content = content.dropFirst() }
    return String(content)
}

private func tableCells(_ line: String) -> [String]? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.contains("|") else { return nil }
    var cells = trimmed.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    if trimmed.hasPrefix("|") { cells.removeFirst() }
    if trimmed.hasSuffix("|") { cells.removeLast() }
    let result = cells.map { $0.trimmingCharacters(in: .whitespaces) }
    return result.isEmpty ? nil : result
}

private func tableDelimiter(_ line: String) -> [AiChatMarkdownDocument.TableAlignment]? {
    guard let cells = tableCells(line) else { return nil }
    var alignments: [AiChatMarkdownDocument.TableAlignment] = []
    for cell in cells {
        let startsColon = cell.hasPrefix(":")
        let endsColon = cell.hasSuffix(":")
        let dashes = cell.drop(while: { $0 == ":" }).drop(while: { $0 == "-" })
        let dashCount = cell.count(where: { $0 == "-" })
        guard dashes.allSatisfy({ $0 == ":" }), dashCount >= 3 else { return nil }
        switch (startsColon, endsColon) {
        case (true, true): alignments.append(.center)
        case (true, false): alignments.append(.left)
        case (false, true): alignments.append(.right)
        case (false, false): alignments.append(.none)
        }
    }
    return alignments
}

private func normalizeLanguage(_ language: String?) -> String? {
    guard let language, !language.isEmpty else { return nil }
    return switch language.lowercased() {
    case "js", "javascript": "javascript"
    case "ts", "typescript": "typescript"
    case "sh", "shell", "bash": "bash"
    case "py", "python": "python"
    default: language.lowercased()
    }
}

private func stableFingerprint(_ value: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in value.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(hash, radix: 16)
}

private extension AiChatMarkdownDocument.BlockKind {
    var identityTag: String {
        switch self {
        case let .heading(level): "heading-\(level)"
        case .paragraph: "paragraph"
        case .bullet: "bullet"
        case let .numbered(number): "numbered-\(number)"
        case .blockquote: "blockquote"
        case .table: "table"
        case .code: "code"
        }
    }
}
