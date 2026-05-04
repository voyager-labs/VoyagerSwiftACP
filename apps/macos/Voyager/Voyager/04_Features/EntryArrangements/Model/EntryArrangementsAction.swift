import Foundation

import ComposableArchitecture
import VoyagerEntitiesEntry

@CasePathable
enum EntryArrangementsAction: CasePathable, Equatable, Sendable {
    case setSortKey(SortKey)
    case setSortOrder(SortOrder)
    case setGroupKey(GroupKey)
    case toggleCollapsedGroup(String)
    case reapply
    case apply(items: [EntryModel], isCollectionMode: Bool)

    case delegate(Delegate)

    @CasePathable
    enum Delegate: CasePathable, Equatable, Sendable {
        case requestApply
        case applied(sortedItems: [EntryModel], isCollectionMode: Bool)
    }
}
