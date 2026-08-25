import AppKit
import Foundation
import VoyagerFeaturesEntryOperations
import VoyagerShared

/// 실제 파일시스템 위에서 동작하는 `FileManagerClient`를 반환하되, staging 디렉터리가
/// 테스트 전용 임시 루트 아래에 생기도록 `temporaryDirectory`만 교체한다.
/// acquisition 클라이언트의 staging 생성/검증/제거를 실제 FS로 검증하기 위해 사용한다.
func makeExternalDropFileManager(temporaryRoot: URL) -> FileManagerClient {
    var client = FileManagerClient.liveValue
    client.temporaryDirectory = { temporaryRoot }
    return client
}

/// acquisition 테스트 전용 임시 루트를 생성해 반환한다. 호출자가 defer로 제거한다.
func makeAcquisitionTempRoot(_ label: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("VoyagerExtDrop-\(label)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

/// 이벤트 스트림을 timeout까지 수집한다. 스트림이 finish하지 않아도 hang 없이 반환한다.
/// (RED stub처럼 종단 없이 흐르는 스트림이나, 실패/취소 시그널이 오지 않는 시나리오를
/// 검증하기 위해 필요하다.)
func collectEvents(
    from stream: AsyncStream<ExternalDropAcquisitionEvent>,
    timeoutNanoseconds: UInt64 = 2_000_000_000,
) async -> [ExternalDropAcquisitionEvent] {
    await withTaskGroup(of: [ExternalDropAcquisitionEvent].self) { group in
        group.addTask {
            var collected: [ExternalDropAcquisitionEvent] = []
            for await event in stream {
                collected.append(event)
            }
            return collected
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            return [ExternalDropAcquisitionEvent]()
        }
        let first = await group.next() ?? [ExternalDropAcquisitionEvent]()
        group.cancelAll()
        return first
    }
}

/// `NSFilePromiseReceiver`를 테스트에서 제어하기 위한 spy.
///
/// `receivePromisedFiles`를 재정의해 실제 파일 수신 대신 reader 콜백을 저장하고,
/// 테스트가 원하는 시점에 `invokeReader(url:error:)`로 직접 호출할 수 있게 한다.
/// 이를 통해 sleep 없이 "제어된 연속(controlled continuation)"으로 콜백을 구동한다.
final class FilePromiseReceiverSpy: NSFilePromiseReceiver, @unchecked Sendable {
    private let names: [String]

    private(set) var receiveCalled = false
    private(set) var receivedDestination: URL?
    private(set) var receivedOperationQueue: OperationQueue?
    private var storedReader: ((URL?, Error?) -> Void)?
    /// `invokeReaderOnQueue`로 큐에서 reader 콜백이 실행될 때 그 스레드가 main이었는지.
    /// 실제 AppKit 콜백 경로가 main이 아님을 검증하는 크래시 재현 테스트에서 사용한다.
    private(set) var readerExecutedOnMainThread: Bool?
    /// 설정되면 receivePromisedFiles가 destination에 첫 이름 파일을 쓰고 reader를
    /// 동기적으로 호출한다. cardinality 확정보다 먼저 콜백이 도착하는 경로를 재현한다.
    var deliverSynchronously = false
    var synchronousFilename: String?

    init(names: [String]) {
        self.names = names
        super.init()
    }

    required init?(pasteboardPropertyList _: Any, ofType _: NSPasteboard.PasteboardType) {
        names = []
        super.init()
    }

    override var fileNames: [String] {
        // provider cardinality는 receive 후에만 알려진다(계약: receive 먼저 → fileNames 사용).
        receiveCalled ? names : []
    }

    override func receivePromisedFiles(
        atDestination destinationDir: URL,
        options _: [AnyHashable: Any] = [:],
        operationQueue: OperationQueue,
        reader: @escaping (URL, (any Error)?) -> Void,
    ) {
        receiveCalled = true
        receivedDestination = destinationDir
        receivedOperationQueue = operationQueue
        storedReader = { url, error in
            reader(url ?? URL(fileURLWithPath: "NSFilePromiseMissing"), error)
        }
        if deliverSynchronously, let name = synchronousFilename ?? names.first {
            let delivered = destinationDir.appendingPathComponent(name)
            try? Data("sync".utf8).write(to: delivered)
            storedReader?(delivered, nil)
        }
    }

    func invokeReader(url: URL?, error: Error? = nil) {
        storedReader?(url, error)
    }

    /// 실제 AppKit처럼 reader 콜백을 receive 시 전달된 non-main OperationQueue에서
    /// 비동기로 호출한다. main actor에서 형성된 콜백 클로저가 큐 스레드에서 실행되는
    /// 실제 크래시(SIGTRAP) 경로를 재현한다.
    func invokeReaderOnQueue(url: URL?, error: Error? = nil) {
        guard let queue = receivedOperationQueue else {
            invokeReader(url: url, error: error)
            return
        }
        queue.addOperation { [self] in
            readerExecutedOnMainThread = Thread.isMainThread
            storedReader?(url ?? URL(fileURLWithPath: "NSFilePromiseMissing"), error)
        }
    }
}
