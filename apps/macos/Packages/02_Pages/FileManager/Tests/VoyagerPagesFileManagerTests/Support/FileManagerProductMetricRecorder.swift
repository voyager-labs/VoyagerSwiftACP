import Foundation
@testable import VoyagerPagesFileManager

/// CTM 제품 메트릭 단언을 위한 경량 record 레코더.
/// makeOperationID 주입으로 수용 시점 발급 ID도 결정적으로 검증한다.
final class FileManagerProductMetricRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [FileManagerProductMetric] = []
    private let operationIDProvider: () -> UUID

    init(makeOperationID: @escaping () -> UUID = UUID.init) {
        operationIDProvider = makeOperationID
    }

    var client: FileManagerProductMetricsClient {
        FileManagerProductMetricsClient(
            record: { [self] metric in
                lock.lock()
                defer { lock.unlock() }
                recorded.append(metric)
            },
            makeOperationID: { [self] in operationIDProvider() },
        )
    }

    func metrics() -> [FileManagerProductMetric] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}
