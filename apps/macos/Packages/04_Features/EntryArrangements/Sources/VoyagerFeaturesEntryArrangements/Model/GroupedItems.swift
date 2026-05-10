import Foundation

import VoyagerEntitiesEntry
import VoyagerEntitiesTag

public struct GroupedItems: Equatable, Sendable {
    public let groupName: String
    public let colorCode: Int?
    public let items: [EntryModel]

    public init(groupName: String, items: [EntryModel], colorCode: Int? = nil) {
        self.groupName = groupName
        self.colorCode = colorCode
        self.items = items
    }

    public var count: Int {
        items.count
    }
}
