import ComposableArchitecture
import Foundation

/// direct pin/unpin 터미널 메트릭 기록을 담당하는 FileManagerFeature 확장.
extension FileManagerFeature {
    /// pinned-record persistence terminal의 tabID를 추출해 탭별 상관 일치에 사용한다.
    func pinnedRecordPersistenceTerminalTabID(_ action: ContentTabAction) -> ContentTabID? {
        switch action {
        case let .pinnedRecordSaveSucceeded(tabID, _):
            tabID
        case let .pinnedRecordSaveFailed(tabID, _, _):
            tabID
        case let .pinnedRecordStoreUnavailable(tabID, _, _, _):
            tabID
        case let .pinnedRecordSaveNotApplied(tabID, _, _, _):
            tabID
        default:
            nil
        }
    }

    /// 터미널 tabID와 일치하고 해당 탭의 최신 intent인 상관만 제거하며 기록한다.
    /// 구 intent의 stale/superseded 터미널과 무관·지연·중복 터미널은 이벤트를 만들지 않는다.
    func recordContentTabMetricIfNeeded(
        _ action: ContentTabAction,
        state: inout State,
    ) {
        let result: ContentTabActionResult? = switch action {
        case .pinnedRecordSaveSucceeded:
            .success
        case .pinnedRecordSaveFailed:
            .failure
        case .pinnedRecordStoreUnavailable:
            .unavailable
        case let .pinnedRecordSaveNotApplied(_, _, reason, _):
            reason == .cancelled ? .cancelled : .failure
        default:
            nil
        }
        guard let result,
              !isStalePinnedRecordPersistenceResult(action, in: state.contentTabs),
              let tabID = pinnedRecordPersistenceTerminalTabID(action),
              let correlation = state.productContentTabPinMutationMetrics.removeValue(forKey: tabID)
        else { return }
        productMetricsClient.record(FileManagerProductMetricsProducer.contentTabTerminal(
            operationID: correlation.operationID,
            action: correlation.action,
            source: .contentTabBar,
            result: result,
        ))
    }
}
