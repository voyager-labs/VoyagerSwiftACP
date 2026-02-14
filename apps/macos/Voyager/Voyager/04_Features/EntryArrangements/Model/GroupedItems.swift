import Foundation

struct GroupedItems: Equatable {
    let groupName: String
    let items: [Entry]

    var count: Int {
        items.count
    }
}
