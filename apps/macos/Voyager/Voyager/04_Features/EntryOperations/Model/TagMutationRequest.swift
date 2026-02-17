import Foundation

struct TagMutationRequest: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case toggle
        case add
        case remove
    }

    let mode: Mode
    let tagName: String
    let paths: [String]
}
