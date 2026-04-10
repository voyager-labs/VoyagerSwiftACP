import AppKit

enum EntryViewLayoutAutoscrollAcceleration {
    static let tickInterval: CGFloat = 1.0 / 60.0
    static let maxOutside: CGFloat = 64
    static let vMin: CGFloat = 1
    static let vMax: CGFloat = 24
    static let maxDelta: CGFloat = 32

    static func delta(
        distanceOutsideBounds: CGFloat,
        axisSize _: CGFloat,
    ) -> CGFloat {
        guard distanceOutsideBounds.isFinite else { return 0 }

        let distance = abs(distanceOutsideBounds)
        guard distance > 0 else { return 0 }

        let sign: CGFloat = distanceOutsideBounds < 0 ? -1 : 1
        let normalizedDistance = min(1, distance / maxOutside)
        let velocity = vMin + (vMax - vMin) * normalizedDistance * normalizedDistance
        let unclamped = sign * velocity
        return max(-maxDelta, min(maxDelta, unclamped))
    }

    static func distanceOutsideBounds(pointerY: CGFloat, visibleRect: CGRect) -> CGFloat {
        if pointerY < visibleRect.minY {
            return pointerY - visibleRect.minY
        }
        if pointerY > visibleRect.maxY {
            return pointerY - visibleRect.maxY
        }
        return 0
    }

    static func nextVerticalOrigin(
        pointerY: CGFloat,
        visibleRect: CGRect,
        currentOriginY: CGFloat,
        documentHeight: CGFloat,
    ) -> CGFloat? {
        let distanceOutside = distanceOutsideBounds(pointerY: pointerY, visibleRect: visibleRect)
        guard distanceOutside != 0 else { return nil }

        let delta = delta(distanceOutsideBounds: distanceOutside, axisSize: visibleRect.height)
        guard delta != 0 else { return nil }

        let maxOriginY = max(0, documentHeight - visibleRect.height)
        let nextOriginY = min(max(0, currentOriginY + delta), maxOriginY)
        guard nextOriginY != currentOriginY else { return nil }
        return nextOriginY
    }
}

struct EntryGridLassoAutoscrollGeometry: Equatable {
    let visibleRect: CGRect
    let currentOrigin: CGPoint
    let documentSize: CGSize
}

final class EntryGridLassoAutoscrollController {
    typealias PointerProvider = () -> NSPoint?
    typealias GeometryProvider = () -> EntryGridLassoAutoscrollGeometry?
    typealias ScrollApplier = (CGPoint) -> Void
    typealias SelectionUpdater = (NSPoint) -> Void

    private let pointerProvider: PointerProvider
    private let geometryProvider: GeometryProvider
    private let scrollApplier: ScrollApplier
    private let selectionUpdater: SelectionUpdater

    private var timer: Timer?

    init(
        pointerProvider: @escaping PointerProvider,
        geometryProvider: @escaping GeometryProvider,
        scrollApplier: @escaping ScrollApplier,
        selectionUpdater: @escaping SelectionUpdater,
    ) {
        self.pointerProvider = pointerProvider
        self.geometryProvider = geometryProvider
        self.scrollApplier = scrollApplier
        self.selectionUpdater = selectionUpdater
    }

    func start() {
        guard timer == nil else { return }

        let timer = Timer(
            timeInterval: TimeInterval(EntryViewLayoutAutoscrollAcceleration.tickInterval),
            repeats: true,
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func tick() {
        guard let pointer = pointerProvider(),
              let geometry = geometryProvider()
        else {
            return
        }

        selectionUpdater(pointer)

        guard let nextOriginY = EntryViewLayoutAutoscrollAcceleration.nextVerticalOrigin(
            pointerY: pointer.y,
            visibleRect: geometry.visibleRect,
            currentOriginY: geometry.currentOrigin.y,
            documentHeight: geometry.documentSize.height,
        ) else {
            return
        }

        var nextOrigin = geometry.currentOrigin
        guard nextOriginY != nextOrigin.y else { return }
        nextOrigin.y = nextOriginY
        scrollApplier(nextOrigin)
    }
}

enum EntryViewLayoutDragStateClearRuleSet {
    nonisolated static func shouldClearAfterSessionEnd(operation: NSDragOperation) -> Bool {
        // Defer clearing for successful copy operations so the highlight persists
        // until the file operation completes. Cancel/invalid (empty) and move
        // operations clear immediately.
        operation != .copy
    }

    nonisolated static func clearedDragPaths(
        afterSessionEndWith operation: NSDragOperation,
        currentPaths: [String],
    ) -> [String] {
        guard shouldClearAfterSessionEnd(operation: operation) else { return currentPaths }
        return []
    }

    nonisolated static func isInternalDrag(paths: [String]) -> Bool {
        !paths.isEmpty
    }
}
