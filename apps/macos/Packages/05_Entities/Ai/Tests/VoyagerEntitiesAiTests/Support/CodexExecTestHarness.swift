import Foundation
@testable import VoyagerEntitiesAi

enum CodexExecTestHarness {
    static func feed(
        _ lines: [String],
        chunks: [Int] = [Int.max],
    ) throws -> (
        events: [CodexExecDecodeOutcome],
        diagnostics: CodexExecDiagnostics,
    ) {
        let input = Data(lines.joined(separator: "\n").utf8) + Data("\n".utf8)
        var decoder = CodexExecJSONLDecoder()
        var events: [CodexExecDecodeOutcome] = []
        var offset = 0
        for requestedSize in chunks {
            guard offset < input.count else { break }
            let size = min(requestedSize, input.count - offset)
            events += try decoder.append(Data(input[offset ..< offset + size]))
            offset += size
        }
        if offset < input.count { events += try decoder.append(Data(input[offset...])) }
        events += try decoder.finish()
        return (events, decoder.diagnostics)
    }
}
