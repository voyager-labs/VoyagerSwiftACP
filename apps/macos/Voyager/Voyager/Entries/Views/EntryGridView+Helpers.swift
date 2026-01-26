import SwiftUI

extension EntryGridView {
    static func == (lhs: EntryGridView, rhs: EntryGridView) -> Bool {
        lhs.item == rhs.item &&
            lhs.isSelected == rhs.isSelected &&
            lhs.isCut == rhs.isCut &&
            lhs.isRenaming == rhs.isRenaming &&
            lhs.isThumbnailReady == rhs.isThumbnailReady &&
            lhs.iconSize == rhs.iconSize &&
            lhs.textSize == rhs.textSize
    }

    struct RenameTextWidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 120
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
}
