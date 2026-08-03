import Foundation

enum AssistantMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(number: Int, text: String)
    case code(String)

    static func parse(_ markdown: String) -> [AssistantMarkdownBlock] {
        var parser = AssistantMarkdownBlockParser(markdown: markdown)
        return parser.parse()
    }

    static func parseHeading(_ line: String) -> AssistantMarkdownBlock? {
        let markerCount = line.prefix { $0 == "#" }.count
        guard (1 ... 6).contains(markerCount), line.dropFirst(markerCount).first == " " else {
            return nil
        }
        let text = line.dropFirst(markerCount + 1).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : .heading(level: markerCount, text: text)
    }

    static func parseBullet(_ line: String) -> String? {
        guard line.count > 2 else { return nil }
        let prefix = line.prefix(2)
        guard prefix == "- " || prefix == "* " else { return nil }
        let text = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    static func parseNumbered(_ line: String) -> AssistantMarkdownBlock? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let digits = line[..<dotIndex]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        let textStart = line.index(after: dotIndex)
        guard textStart < line.endIndex, line[textStart] == " " else { return nil }
        let text = line[line.index(after: textStart)...].trimmingCharacters(in: .whitespaces)
        guard let number = Int(digits), !text.isEmpty else { return nil }
        return .numbered(number: number, text: text)
    }
}

private struct AssistantMarkdownBlockParser {
    var markdown: String
    var blocks: [AssistantMarkdownBlock] = []
    var paragraphLines: [String] = []
    var codeLines: [String] = []
    var isInCodeBlock = false

    mutating func parse() -> [AssistantMarkdownBlock] {
        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            consume(rawLine)
        }
        finish()
        return blocks.isEmpty ? [.paragraph(markdown)] : blocks
    }

    mutating func consume(_ rawLine: String) {
        let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
        if consumeFence(trimmedLine) { return }
        if isInCodeBlock {
            codeLines.append(rawLine)
            return
        }
        consumeMarkdownLine(rawLine: rawLine, trimmedLine: trimmedLine)
    }

    mutating func consumeFence(_ trimmedLine: String) -> Bool {
        guard trimmedLine.hasPrefix("```") else { return false }
        flushParagraph()
        if isInCodeBlock { flushCode() }
        isInCodeBlock.toggle()
        return true
    }

    mutating func consumeMarkdownLine(rawLine: String, trimmedLine: String) {
        guard !trimmedLine.isEmpty else {
            flushParagraph()
            return
        }
        if appendBlock(from: trimmedLine) { return }
        paragraphLines.append(rawLine)
    }

    mutating func appendBlock(from trimmedLine: String) -> Bool {
        if let heading = AssistantMarkdownBlock.parseHeading(trimmedLine) {
            flushParagraph()
            blocks.append(heading)
            return true
        }
        if let bullet = AssistantMarkdownBlock.parseBullet(trimmedLine) {
            flushParagraph()
            blocks.append(.bullet(bullet))
            return true
        }
        if let numbered = AssistantMarkdownBlock.parseNumbered(trimmedLine) {
            flushParagraph()
            blocks.append(numbered)
            return true
        }
        return false
    }

    mutating func finish() {
        if isInCodeBlock {
            paragraphLines.append("```")
            paragraphLines.append(contentsOf: codeLines)
        } else if !codeLines.isEmpty {
            flushCode()
        }
        flushParagraph()
    }

    mutating func flushParagraph() {
        let paragraph = paragraphLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !paragraph.isEmpty { blocks.append(.paragraph(paragraph)) }
        paragraphLines.removeAll()
    }

    mutating func flushCode() {
        blocks.append(.code(codeLines.joined(separator: "\n")))
        codeLines.removeAll()
    }
}

extension AssistantMarkdownBlock {
    var renderedText: String {
        switch self {
        case let .heading(_, text), let .paragraph(text), let .bullet(text), let .numbered(_, text):
            renderedInlineMarkdown(text)
        case let .code(text):
            text
        }
    }

    private func renderedInlineMarkdown(_ text: String) -> String {
        guard let attributedText = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace),
        ) else {
            return text
        }
        return String(attributedText.characters)
    }
}
