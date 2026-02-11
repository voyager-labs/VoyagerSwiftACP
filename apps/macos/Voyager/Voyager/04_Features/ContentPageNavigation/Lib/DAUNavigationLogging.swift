// TODO(ContentPageNavigation): 2차 네이밍 정리
// - 파일명 변경: DAUNavigationLogging.swift -> ContentPageNavigationLogging.swift
// - 관련 심볼 변경:
//   - logDAUNavigationIfNeeded(...) -> logContentPageNavigationDAUIfNeeded(...) (또는 유지)
// - 주의:
//   - 이 단계에서는 동작 변경 금지(로직 수정 금지). 네이밍만 정리한다.

import Foundation

func logDAUNavigationIfNeeded(
    previous: FileManagerNavigationUtils.NavigationState,
    next: FileManagerNavigationUtils.NavigationState,
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
