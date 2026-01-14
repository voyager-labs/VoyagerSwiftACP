import Foundation

struct ListColumnWidths: Equatable, Sendable {
    enum Column: Sendable {
        case name
        case date
        case size
        case kind
    }

    var name: CGFloat
    var date: CGFloat
    var size: CGFloat
    var kind: CGFloat

    static let `default` = ListColumnWidths(
        name: 0.4,
        date: 0.35,
        size: 0.1,
        kind: 0.15,
    )

    func makeAbsoluteWidths(totalWidth: CGFloat, padding _: CGFloat, spacing _: CGFloat) -> ListColumnLayout {
        ListColumnLayout(availableWidth: totalWidth, columnWidths: self)
    }

    func updated(
        column: Column,
        delta: CGFloat,
        totalWidth: CGFloat,
        padding: CGFloat,
        spacing: CGFloat,
    ) -> ListColumnWidths {
        let usableWidth = max(totalWidth - padding * 2, 0)
        let widthForColumns = max(usableWidth - spacing * 3, 0)
        let deltaRatio = widthForColumns > 0 ? delta / widthForColumns : 0

        var newWidths = self

        let minNamePixels: CGFloat = 200
        let minDatePixels: CGFloat = 120
        let minSizePixels: CGFloat = 70
        let minKindPixels: CGFloat = 80

        let absoluteMinRatio: CGFloat = 0.05

        switch column {
        case .name:
            let minNameRatio = max(minNamePixels / widthForColumns, absoluteMinRatio)
            let maxNameRatio = min(0.7, name + date - absoluteMinRatio)
            newWidths.name = max(minNameRatio, min(maxNameRatio, name + deltaRatio))
            newWidths.date = max(absoluteMinRatio, date - (newWidths.name - name))
        case .date:
            let minDateRatio = max(minDatePixels / widthForColumns, absoluteMinRatio)
            let maxDateRatio = min(0.6, date + size - absoluteMinRatio)
            newWidths.date = max(minDateRatio, min(maxDateRatio, date + deltaRatio))
            newWidths.size = max(absoluteMinRatio, size - (newWidths.date - date))
        case .size:
            let minSizeRatio = max(minSizePixels / widthForColumns, absoluteMinRatio)
            let maxSizeRatio = min(0.3, size + kind - absoluteMinRatio)
            newWidths.size = max(minSizeRatio, min(maxSizeRatio, size + deltaRatio))
            newWidths.kind = max(absoluteMinRatio, kind - (newWidths.size - size))
        case .kind:
            let minKindRatio = max(minKindPixels / widthForColumns, absoluteMinRatio)
            let maxKindRatio = min(0.4, kind + size - absoluteMinRatio)
            newWidths.kind = max(minKindRatio, min(maxKindRatio, kind + deltaRatio))
            newWidths.size = max(absoluteMinRatio, size - (newWidths.kind - kind))
        }

        let totalRatio = newWidths.name + newWidths.date + newWidths.size + newWidths.kind
        if abs(totalRatio - 1.0) > 0.001 {
            let normalizationFactor = 1.0 / totalRatio
            newWidths.name *= normalizationFactor
            newWidths.date *= normalizationFactor
            newWidths.size *= normalizationFactor
            newWidths.kind *= normalizationFactor
        }

        return newWidths
    }
}
