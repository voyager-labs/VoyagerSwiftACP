import Foundation

func normalizedSections(_ sections: [String]) -> String {
    let content = sections
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    return content + "\n"
}

func replacingSection(
    in existing: String,
    startMarker: String,
    endMarker: String,
    with block: String,
) -> String {
    guard let startRange = existing.range(of: startMarker),
          let endRange = existing.range(of: endMarker),
          startRange.lowerBound < endRange.upperBound
    else {
        return normalizedSections([existing, block])
    }
    let prefix = String(existing[..<startRange.lowerBound])
    let suffix = String(existing[endRange.upperBound...])
    return normalizedSections([prefix, block, suffix])
}
