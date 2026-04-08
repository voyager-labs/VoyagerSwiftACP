import Foundation

struct GroupedItems: Equatable {
    let groupName: String
    let colorCode: Int?
    let items: [EntryModel]

    init(groupName: String, items: [EntryModel], colorCode: Int? = nil) {
        self.groupName = groupName
        self.colorCode = colorCode
        self.items = items
    }

    var count: Int {
        items.count
    }
}
