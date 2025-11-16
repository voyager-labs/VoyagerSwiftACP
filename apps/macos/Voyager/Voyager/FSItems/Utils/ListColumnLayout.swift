import Foundation

struct ListColumnLayout {
    static let outerPadding: CGFloat = 16
    static let columnSpacing: CGFloat = 8

    let outerPadding: CGFloat = Self.outerPadding
    let columnSpacing: CGFloat = Self.columnSpacing
    let name: CGFloat
    let date: CGFloat
    let size: CGFloat
    let kind: CGFloat

    init(availableWidth: CGFloat, columnWidths: ListColumnWidths? = nil) {
        let usableWidth = max(availableWidth - outerPadding * 2, 0)
        let widthForColumns = max(usableWidth - columnSpacing * 3, 0)

        let nameRatio: CGFloat
        let dateRatio: CGFloat
        let sizeRatio: CGFloat
        let kindRatio: CGFloat

        if let columnWidths = columnWidths {
            nameRatio = columnWidths.name
            dateRatio = columnWidths.date
            sizeRatio = columnWidths.size
            kindRatio = columnWidths.kind
        } else {
            nameRatio = 0.4
            dateRatio = 0.35
            sizeRatio = 0.1
            kindRatio = 0.15
        }

        let baseNameWidth = widthForColumns * nameRatio
        let dateValue = widthForColumns * dateRatio
        let sizeValue = widthForColumns * sizeRatio
        let kindValue = widthForColumns * kindRatio

        let remainder = widthForColumns - (baseNameWidth + dateValue + sizeValue + kindValue)
        let adjustedNameWidth = baseNameWidth + max(remainder, 0)

        name = adjustedNameWidth
        date = dateValue
        size = sizeValue
        kind = kindValue
    }
}
