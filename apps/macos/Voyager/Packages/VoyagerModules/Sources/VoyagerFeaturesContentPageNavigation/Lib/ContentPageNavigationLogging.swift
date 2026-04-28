import Foundation
import VoyagerEntitiesEntry

public func logContentPageNavigationDAUIfNeeded(
    previous: ContentPageNavigationRoute,
    next: ContentPageNavigationRoute,
) {
    guard previous != next else { return }

    if next.isCollection {
        // 콜렉션으로 진입하는 경우만 콜렉션 DAU를 기록한다.
        VoyagerSentryMetricLogger.logDAUNavigation(kind: .collection)
        return
    }

    // 그 외(폴더/태그/컴퓨터/최근 항목 등) 이동은 폴더로 취급
    VoyagerSentryMetricLogger.logDAUNavigation(kind: .folder)
}
