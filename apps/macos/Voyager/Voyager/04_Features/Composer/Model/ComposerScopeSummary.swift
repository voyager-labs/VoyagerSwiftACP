import Foundation

enum ComposerScopeSummaryPrimary: Equatable, Hashable, Sendable {
    case rootOnly
    case singleExplicit(path: String)
    case multiExplicit(count: Int)
}

enum ComposerScopeSummarySecondary: Equatable, Hashable, Sendable {
    case exceptionCount(Int)
}

struct ComposerScopeSummary: Equatable, Hashable, Sendable {
    let primary: ComposerScopeSummaryPrimary
    let secondary: [ComposerScopeSummarySecondary]

    var primaryText: String {
        switch primary {
        case .rootOnly:
            "This Mac"
        case let .singleExplicit(path):
            path
        case let .multiExplicit(count):
            count == 1 ? "1 Scope" : "\(count) Scopes"
        }
    }

    var secondaryText: String? {
        guard exceptionCount > 0 else { return nil }
        return exceptionCount == 1 ? "1 exception" : "\(exceptionCount) exceptions"
    }

    var exceptionCount: Int {
        secondary.reduce(into: 0) { partialResult, item in
            guard case let .exceptionCount(count) = item else { return }
            partialResult += count
        }
    }
}
