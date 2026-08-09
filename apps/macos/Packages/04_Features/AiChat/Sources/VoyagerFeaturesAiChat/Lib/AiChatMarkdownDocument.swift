import Foundation

struct AiChatMarkdownDocument: Equatable {
    let rawSource: String
    let blocks: [Block]

    var rawUTF8: [UInt8] {
        Array(rawSource.utf8)
    }

    var reconstructedRawSource: String {
        blocks.map(\.rawSlice).joined()
    }

    var renderedBlocks: [String] {
        blocks.map(\.projections.rendered)
    }

    var searchBlocks: [String] {
        blocks.map(\.projections.search)
    }

    var plainText: String {
        blocks.map(\.projections.plain).joined(separator: "\n")
    }

    var codePayloads: [CodePayload] {
        blocks.compactMap(\.code)
    }

    struct Block: Equatable {
        let id: BlockID
        let kind: BlockKind
        let sourceRange: SourceRange
        let rawSlice: String
        let projections: Projections
        let inlineIntents: [InlineIntent]
        let code: CodePayload?
        let table: TableMetadata?

        init?(
            id: BlockID,
            kind: BlockKind,
            sourceRange: SourceRange,
            rawSlice: String,
            projections: Projections,
            inlineIntents: [InlineIntent] = [],
            code: CodePayload? = nil,
            table: TableMetadata? = nil,
        ) {
            guard sourceRange.utf8Offsets.count == rawSlice.utf8.count else {
                return nil
            }
            self.id = id
            self.kind = kind
            self.sourceRange = sourceRange
            self.rawSlice = rawSlice
            self.projections = projections
            self.inlineIntents = inlineIntents
            self.code = code
            self.table = table
        }
    }

    struct BlockID: Equatable, Hashable {
        let rawValue: String
    }

    enum BlockKind: Equatable {
        case heading(level: Int)
        case paragraph
        case bullet
        case numbered(number: Int)
        case blockquote
        case table
        case code
    }

    enum InlineIntent: Equatable {
        case emphasis(SearchRange)
        case strong(SearchRange)
        case link(range: SearchRange, destination: String)
        case code(SearchRange)
    }

    struct Projections: Equatable {
        let rendered: String
        let search: String
        let plain: String
    }

    struct CodePayload: Equatable {
        let payload: String
        let openingIndentation: String
        let fenceDelimiter: String
        let originalInfoString: String?
        let originalLanguage: String?
        let trailingMetadata: String?
        let normalizedLanguage: String?

        init(
            payload: String,
            originalLanguage: String?,
            normalizedLanguage: String?,
            openingIndentation: String = "",
            fenceDelimiter: String = "```",
            originalInfoString: String? = nil,
            trailingMetadata: String? = nil,
        ) {
            self.payload = payload
            self.openingIndentation = openingIndentation
            self.fenceDelimiter = fenceDelimiter
            self.originalInfoString = originalInfoString
            self.originalLanguage = originalLanguage
            self.trailingMetadata = trailingMetadata
            self.normalizedLanguage = normalizedLanguage
        }
    }

    struct TableCell: Equatable {
        let text: String
        let inlineIntents: [InlineIntent]
    }

    struct TableMetadata: Equatable {
        let cells: [[TableCell]]
        let alignments: [TableAlignment]

        var rows: [[String]] {
            cells.map { $0.map(\.text) }
        }

        init(cells: [[TableCell]], alignments: [TableAlignment]) {
            self.cells = cells
            self.alignments = alignments
        }

        init(rows: [[String]], alignments: [TableAlignment]) {
            cells = rows.map { row in
                row.map { TableCell(text: $0, inlineIntents: []) }
            }
            self.alignments = alignments
        }
    }

    enum TableAlignment: Equatable {
        case none
        case left
        case center
        case right
    }

    struct SourceRange: Equatable, Hashable {
        let utf8Offsets: Range<Int>

        func rawSlice(in source: String) -> String? {
            guard utf8Offsets.lowerBound >= 0,
                  utf8Offsets.upperBound >= utf8Offsets.lowerBound,
                  utf8Offsets.upperBound <= source.utf8.count,
                  let lowerUTF8 = source.utf8.index(
                      source.utf8.startIndex,
                      offsetBy: utf8Offsets.lowerBound,
                      limitedBy: source.utf8.endIndex,
                  ),
                  let upperUTF8 = source.utf8.index(
                      source.utf8.startIndex,
                      offsetBy: utf8Offsets.upperBound,
                      limitedBy: source.utf8.endIndex,
                  ),
                  let lowerBound = String.Index(lowerUTF8, within: source),
                  let upperBound = String.Index(upperUTF8, within: source)
            else {
                return nil
            }
            return String(source[lowerBound ..< upperBound])
        }
    }

    struct SearchRange: Equatable, Hashable {
        let characterOffsets: Range<Int>

        init(characterOffsets: Range<Int>) {
            self.characterOffsets = characterOffsets
        }

        init(_ range: Range<String.Index>, in string: String) {
            characterOffsets = string.distance(from: string.startIndex, to: range.lowerBound)
                ..< string.distance(from: string.startIndex, to: range.upperBound)
        }

        func substring(in string: String) -> String? {
            guard let range = stringRange(in: string) else {
                return nil
            }
            return String(string[range])
        }

        func plainSelectionRange(in string: String) -> PlainSelectionRange? {
            guard let range = stringRange(in: string) else {
                return nil
            }
            let lowerBound = range.lowerBound.utf16Offset(in: string)
            let upperBound = range.upperBound.utf16Offset(in: string)
            return PlainSelectionRange(
                utf16Location: lowerBound,
                utf16Length: upperBound - lowerBound,
            )
        }

        private func stringRange(in string: String) -> Range<String.Index>? {
            guard characterOffsets.lowerBound >= 0,
                  characterOffsets.upperBound >= characterOffsets.lowerBound,
                  characterOffsets.upperBound <= string.count,
                  let lowerBound = string.index(
                      string.startIndex,
                      offsetBy: characterOffsets.lowerBound,
                      limitedBy: string.endIndex,
                  ),
                  let upperBound = string.index(
                      lowerBound,
                      offsetBy: characterOffsets.count,
                      limitedBy: string.endIndex,
                  )
            else {
                return nil
            }
            return lowerBound ..< upperBound
        }
    }

    struct PlainSelectionRange: Equatable, Hashable {
        let utf16Location: Int
        let utf16Length: Int

        var nsRange: NSRange {
            NSRange(location: utf16Location, length: utf16Length)
        }

        init(utf16Location: Int, utf16Length: Int) {
            self.utf16Location = utf16Location
            self.utf16Length = utf16Length
        }

        init?(_ nsRange: NSRange) {
            guard nsRange.location != NSNotFound else {
                return nil
            }
            self.init(utf16Location: nsRange.location, utf16Length: nsRange.length)
        }

        func searchRange(
            in string: String,
            invalidRangePolicy: InvalidRangePolicy,
        ) -> SearchRange? {
            let boundaries = Self.characterBoundaries(in: string)
            guard let requestedUpperBound else {
                return invalidRangePolicy == .discard ? nil : Self.clampedSearchRange(
                    lowerBound: utf16Location,
                    upperBound: Int.max,
                    boundaries: boundaries,
                )
            }

            switch invalidRangePolicy {
            case .discard:
                guard utf16Location >= 0,
                      utf16Length >= 0,
                      requestedUpperBound <= string.utf16.count,
                      let lowerBound = boundaries.first(where: { $0.utf16Offset == utf16Location }),
                      let upperBound = boundaries.first(where: { $0.utf16Offset == requestedUpperBound })
                else {
                    return nil
                }
                return SearchRange(characterOffsets: lowerBound.characterOffset ..< upperBound.characterOffset)
            case .clamp:
                return Self.clampedSearchRange(
                    lowerBound: utf16Location,
                    upperBound: requestedUpperBound,
                    boundaries: boundaries,
                )
            }
        }

        private var requestedUpperBound: Int? {
            guard utf16Length >= 0 else {
                return nil
            }
            let (upperBound, overflow) = utf16Location.addingReportingOverflow(utf16Length)
            return overflow ? nil : upperBound
        }

        private static func characterBoundaries(
            in string: String,
        ) -> [(characterOffset: Int, utf16Offset: Int)] {
            var boundaries = [(characterOffset: 0, utf16Offset: 0)]
            var index = string.startIndex
            var characterOffset = 0
            while index < string.endIndex {
                index = string.index(after: index)
                characterOffset += 1
                boundaries.append((
                    characterOffset: characterOffset,
                    utf16Offset: index.utf16Offset(in: string),
                ))
            }
            return boundaries
        }

        private static func clampedSearchRange(
            lowerBound: Int,
            upperBound: Int,
            boundaries: [(characterOffset: Int, utf16Offset: Int)],
        ) -> SearchRange? {
            guard let finalBoundary = boundaries.last else {
                return nil
            }
            let clampedLowerBound = min(max(lowerBound, 0), finalBoundary.utf16Offset)
            let clampedUpperBound = min(max(upperBound, clampedLowerBound), finalBoundary.utf16Offset)
            guard let lowerBoundary = boundaries.last(where: { $0.utf16Offset <= clampedLowerBound }),
                  let upperBoundary = boundaries.first(where: { $0.utf16Offset >= clampedUpperBound })
            else {
                return nil
            }
            return SearchRange(
                characterOffsets: lowerBoundary.characterOffset ..< upperBoundary.characterOffset,
            )
        }
    }

    enum InvalidRangePolicy: Equatable {
        case clamp
        case discard
    }
}
