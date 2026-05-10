import Foundation

public func logContentPageNavigationDAUIfNeeded(
    previous: ContentPageNavigationRoute,
    next: ContentPageNavigationRoute
) {
    guard previous != next else { return }
}
