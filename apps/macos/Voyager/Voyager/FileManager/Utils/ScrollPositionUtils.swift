import AppKit
import ComposableArchitecture
import Foundation

enum ScrollPositionUtils {
    static func saveScrollPosition(
        scrollView: NSScrollView?,
        currentPath: String,
        store: StoreOf<FileManagerFeature>,
    ) {
        guard let scrollView else { return }
        let offset = scrollView.contentView.bounds.origin
        store.send(.saveScrollOffset(offset, forPath: currentPath))
    }

    static func restoreScrollPosition(
        scrollView: NSScrollView?,
        currentPath: String,
        scrollPositions: [String: CGPoint],
        hasRestored: inout Bool,
    ) {
        guard !hasRestored,
              let scrollView,
              let savedOffset = scrollPositions[currentPath]
        else {
            return
        }

        scrollView.contentView.scroll(to: savedOffset)
        hasRestored = true
    }

    static func performAutoScroll(scrollView: NSScrollView?) {
        guard let scrollView,
              let currentEvent = NSApplication.shared.currentEvent
        else {
            return
        }

        scrollView.contentView.autoscroll(with: currentEvent)
    }
}
