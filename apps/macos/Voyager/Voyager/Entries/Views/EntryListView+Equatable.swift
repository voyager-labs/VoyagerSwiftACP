import SwiftUI

extension EntryListView {
    static func == (lhs: EntryListView, rhs: EntryListView) -> Bool {
        lhs.item == rhs.item &&
            lhs.isSelected == rhs.isSelected &&
            lhs.isCut == rhs.isCut &&
            lhs.isRenaming == rhs.isRenaming &&
            lhs.isThumbnailReady == rhs.isThumbnailReady &&
            lhs.iconSize == rhs.iconSize &&
            lhs.textSize == rhs.textSize
    }
}
