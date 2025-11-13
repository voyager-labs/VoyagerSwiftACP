import AppKit
import ComposableArchitecture
import Foundation

enum ScrollPositionUtils {
    /// 스크롤 위치를 저장합니다.
    static func saveScrollPosition(
        scrollView: NSScrollView?,
        currentPath: String,
        store: StoreOf<FileManagerFeature>
    ) {
        guard let scrollView = scrollView else { return }
        let offset = scrollView.contentView.bounds.origin
        store.send(.saveScrollOffset(offset, forPath: currentPath))
    }

    /// 저장된 스크롤 위치를 복원합니다.
    static func restoreScrollPosition(
        scrollView: NSScrollView?,
        currentPath: String,
        scrollPositions: [String: CGPoint],
        hasRestored: inout Bool
    ) {
        guard !hasRestored,
              let scrollView = scrollView,
              let savedOffset = scrollPositions[currentPath]
        else {
            return
        }

        scrollView.contentView.scroll(to: savedOffset)
        hasRestored = true
    }
}
