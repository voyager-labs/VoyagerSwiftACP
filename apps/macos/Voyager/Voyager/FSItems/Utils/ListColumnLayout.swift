import Foundation

struct ListColumnLayout {
    let outerPadding: CGFloat = 16
    let columnSpacing: CGFloat = 8
    let name: CGFloat
    let date: CGFloat
    let size: CGFloat
    let kind: CGFloat

    init(availableWidth: CGFloat) {
        let usableWidth = max(availableWidth - outerPadding * 2, 0)
        let widthForColumns = max(usableWidth - columnSpacing * 3, 0)

        let nameRatio: CGFloat = 0.4
        let dateRatio: CGFloat = 0.35
        let sizeRatio: CGFloat = 0.1
        let kindRatio: CGFloat = 0.15

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
