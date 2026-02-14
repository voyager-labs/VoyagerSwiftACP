import Foundation

struct TagChangeTarget: Equatable, Sendable {
    let file: Entry
    let beforeTags: [String]
    let afterTags: [String]
}
