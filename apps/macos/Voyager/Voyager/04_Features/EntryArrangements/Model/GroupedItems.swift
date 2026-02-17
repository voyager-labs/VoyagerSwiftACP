import Foundation

struct GroupedItems: Equatable {
    let groupName: String
    let items: [EntryModel]

    var count: Int {
        items.count
    }
}
