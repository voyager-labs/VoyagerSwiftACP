import Foundation

import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerShared

@CasePathable
public enum EntryArrangementsAction: CasePathable, Equatable, Sendable {
    case setSortKey(SortKey)
    case setSortOrder(VoyagerShared.SortOrder)
    case setGroupKey(GroupKey)
    case toggleCollapsedGroup(String)
    case reapply
    case apply(items: [EntryModel], isCollectionMode: Bool)

    case delegate(Delegate)

    @CasePathable
    public enum Delegate: CasePathable, Equatable, Sendable {
        case requestApply
        case applied(sortedItems: [EntryModel], isCollectionMode: Bool)
    }
}
