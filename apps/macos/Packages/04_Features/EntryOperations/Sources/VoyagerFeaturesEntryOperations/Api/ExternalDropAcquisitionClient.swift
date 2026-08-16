@preconcurrency import AppKit
import ComposableArchitecture
import Darwin
import Foundation
import os
import VoyagerShared

/// 외부 Finder drop의 AppKit 기반 파일 획득을 담당하는 의존성 클라이언트.
///
/// `acceptDrop` 시점에 동기적으로 세션을 시작하고(`begin`), `NSFilePromiseReceiver`를
/// private registry에 보관한 뒤 `receivePromisedFiles`를 즉시 호출한다. reducer로는
/// Sendable 이벤트(`events`)와 세션 ID만 전달되며, AppKit receiver는 절대 경계를 넘지 않는다.
public struct ExternalDropAcquisitionClient: Sendable {
    /// 외부 drop 획득을 동기적으로 시작한다. main actor에서 호출되며 Todo 4/5의
    /// Grid/List `acceptDrop`이 이 진입점을 사용한다. promise receiver와 data flavor를 함께
    /// 받아 물리화하고, Sendable 요청 메타데이터만 반환한다.
    public var begin: @MainActor @Sendable ([NSFilePromiseReceiver], [ExternalDropDataFlavor], String, Bool)
        -> ExternalDropAcceptedRequest

    /// 주어진 세션의 종단 획득 이벤트 스트림. reducer가 구독해 소비한다.
    public var events: @MainActor @Sendable (ExternalDropSessionID) -> AsyncStream<ExternalDropAcquisitionEvent>

    /// 세션을 취소한다. 세션을 무효화하고 staging을 즉시 제거하며, 지연 콜백은 재삭제만 하고
    /// 이벤트는 내지 않는다. 멱등(idempotent)하다.
    public var cancel: @MainActor @Sendable (ExternalDropSessionID) -> Void

    /// 세션을 정상 종료한다. 멱등(idempotent)하다.
    public var finish: @MainActor @Sendable (ExternalDropSessionID) -> Void

    /// 레거시 promised-file 수신 폴백 세션을 시작한다. `NSFilePromiseReceiver`가 없는
    /// (`com.apple.pasteboard.promised-file-url`/`NSPromiseContentsPboardType` 기반) 드래그에서
    /// `acceptDrop` 내부에서 source가 staging에 써 둔 파일 경로들을 받아 이미 물리화된
    /// received-item으로 등록한다. `stagedPaths`는 이미 staging 안에 존재·검증된 경로여야 한다.
    public var beginLegacy: @MainActor @Sendable (
        [String], String, String, Bool,
    ) -> ExternalDropAcceptedRequest

    /// 지연 data-flavor 획득 세션을 시작한다. request는 load 실행 전에 즉시 반환되고,
    /// 각 flavor의 `load` 클로저는 세션이 소유한 OperationQueue에서 실행된 뒤 결과가
    /// 기존 `.received`/종단 이벤트 스트림으로 흐른다. acceptDrop 동기 경로에서
    /// 다중 MB 원문 로딩(Mail `source` export 등)을 분리할 때 사용한다.
    public var beginDeferred: @MainActor @Sendable (
        [ExternalDropDeferredFlavor], String, Bool,
    ) -> ExternalDropAcceptedRequest

    /// Mail 메시지 드래그의 원문(`source`)을 조회 키로 로드한다. 라이브 구현은
    /// Mail automation(AppleScript)으로 export하고, 테스트는 클로저를 교체해 대체한다.
    public var loadMailSource: @Sendable (MailMessageSourceLookup) -> Data?

    nonisolated public init(
        begin: @escaping @MainActor @Sendable ([NSFilePromiseReceiver], [ExternalDropDataFlavor], String, Bool)
            -> ExternalDropAcceptedRequest,
        events: @escaping @MainActor @Sendable (ExternalDropSessionID) -> AsyncStream<ExternalDropAcquisitionEvent>,
        cancel: @escaping @MainActor @Sendable (ExternalDropSessionID) -> Void,
        finish: @escaping @MainActor @Sendable (ExternalDropSessionID) -> Void,
        beginLegacy: @escaping @MainActor @Sendable ([String], String, String, Bool) -> ExternalDropAcceptedRequest,
        beginDeferred: @escaping @MainActor @Sendable (
            [ExternalDropDeferredFlavor], String, Bool,
        ) -> ExternalDropAcceptedRequest = { _, destination, forcedCopy in
            ExternalDropAcceptedRequest(
                sessionID: ExternalDropSessionID(),
                destination: destination,
                orderedPromisedNames: [],
                promisedOrdinals: [],
                forcedCopy: forcedCopy,
                stagingDirectory: "",
            )
        },
        loadMailSource: @escaping @Sendable (MailMessageSourceLookup) -> Data? = { _ in nil },
    ) {
        self.begin = begin
        self.events = events
        self.cancel = cancel
        self.finish = finish
        self.beginLegacy = beginLegacy
        self.beginDeferred = beginDeferred
        self.loadMailSource = loadMailSource
    }
}

extension ExternalDropAcquisitionClient: DependencyKey {
    public static var liveValue: ExternalDropAcquisitionClient {
        live(fileManager: .liveValue)
    }

    public static func live(fileManager: FileManagerClient) -> ExternalDropAcquisitionClient {
        MainActor.assumeIsolated {
            ExternalDropAcquisitionLive.live(fileManager: fileManager)
        }
    }

    /// 테스트/프리뷰 기본값은 같은 결정적(deterministic) no-op 클라이언트를 공유한다.
    /// 외부 drop은 AppKit 수신기와 실제 staging 없이 동작하므로, 클라이언트를 주입하지 않는
    /// 무관한 feature-composition 테스트에서도 크래시 없이 안전하게 기본 동작을 제공한다.
    /// EOP002 등 drop 동작을 검증하는 테스트는 명시적 recorder를 주입해 실제 흐름을 주장한다.
    public static var testValue: ExternalDropAcquisitionClient {
        ExternalDropAcquisitionLive.noop
    }

    public static var previewValue: ExternalDropAcquisitionClient {
        ExternalDropAcquisitionLive.noop
    }
}

public extension DependencyValues {
    nonisolated var externalDropAcquisitionClient: ExternalDropAcquisitionClient {
        get { self[ExternalDropAcquisitionClient.self] }
        set { self[ExternalDropAcquisitionClient.self] = newValue }
    }
}

// MARK: - Live implementation

enum ExternalDropAcquisitionLive {
    /// 결정적 no-op 클라이언트. 실제 획득 없이 안전하게 빈 요청/이벤트만 반환한다.
    static var noop: ExternalDropAcquisitionClient {
        ExternalDropAcquisitionClient(
            begin: { _, _, destination, forcedCopy in
                ExternalDropAcceptedRequest(
                    sessionID: ExternalDropSessionID(),
                    destination: destination,
                    orderedPromisedNames: [],
                    promisedOrdinals: [],
                    forcedCopy: forcedCopy,
                    stagingDirectory: "",
                )
            },
            events: { _ in AsyncStream { _ in } },
            cancel: { _ in },
            finish: { _ in },
            beginLegacy: { _, stagingDirectory, destination, forcedCopy in
                ExternalDropAcceptedRequest(
                    sessionID: ExternalDropSessionID(),
                    destination: destination,
                    orderedPromisedNames: [],
                    promisedOrdinals: [],
                    forcedCopy: forcedCopy,
                    stagingDirectory: stagingDirectory,
                )
            },
        )
    }

    @MainActor
    static func live(fileManager: FileManagerClient) -> ExternalDropAcquisitionClient {
        let store = ExternalDropAcquisitionStore(fileManager: fileManager)
        return ExternalDropAcquisitionClient(
            begin: { receivers, dataFlavors, destination, forcedCopy in
                store.begin(
                    receivers: receivers,
                    dataFlavors: dataFlavors,
                    destination: destination,
                    forcedCopy: forcedCopy,
                )
            },
            events: { sessionID in
                store.events(for: sessionID)
            },
            cancel: { sessionID in
                store.cancel(sessionID)
            },
            finish: { sessionID in
                store.finish(sessionID)
            },
            beginLegacy: { stagedPaths, stagingDirectory, destination, forcedCopy in
                store.beginLegacy(
                    stagedPaths: stagedPaths,
                    stagingDirectory: stagingDirectory,
                    destination: destination,
                    forcedCopy: forcedCopy,
                )
            },
            beginDeferred: { items, destination, forcedCopy in
                store.beginDeferred(
                    items: items,
                    destination: destination,
                    forcedCopy: forcedCopy,
                )
            },
            loadMailSource: { MailMessageSourceExport.load($0) },
        )
    }
}

/// AppKit receiver registry는 main actor에 격리하고, 콜백 세션에는 Sendable 상태만 둔다.
@MainActor
private final class ExternalDropAcquisitionStore {
    private var sessions: [ExternalDropSessionID: ExternalDropAcquisitionSession] = [:]
    private var receiverRegistry: [ExternalDropSessionID: [NSFilePromiseReceiver]] = [:]
    private let fileManager: FileManagerClient
    private let queue: OperationQueue

    init(fileManager: FileManagerClient) {
        self.fileManager = fileManager
        let queue = OperationQueue()
        queue.name = "com.voyager.external-drop-acquisition"
        queue.maxConcurrentOperationCount = 1
        self.queue = queue
    }

    /// 외부 drop 획득을 동기적으로 시작한다. main actor에서 호출된다.
    @MainActor
    func begin(
        receivers: [NSFilePromiseReceiver],
        dataFlavors: [ExternalDropDataFlavor],
        destination: String,
        forcedCopy: Bool,
    ) -> ExternalDropAcceptedRequest {
        let sessionID = ExternalDropSessionID()
        let stagingURL = fileManager
            .temporaryDirectory()
            .appendingPathComponent("ExternalDrop-\(sessionID.rawValue)")
        // staging 생성 실패 시 콜백 검증(fileExists/outsideStaging)이 타입화 실패로 귀결된다.
        try? fileManager.createDirectory(stagingURL, true, nil)

        let session = ExternalDropAcquisitionSession(
            sessionID: sessionID,
            stagingDirectory: stagingURL.path,
            fileManager: fileManager,
            queue: queue,
        )

        sessions[sessionID] = session
        if !receivers.isEmpty {
            session.startStagingObservation()
        }

        // cardinality 검증: empty/indeterminate는 추측 성공이 아닌 타입화 실패다.
        // data flavor는 begin에서 동기적으로 물리화되므로 promise fileNames 수에 더한다.
        session.finalizeCardinality(fileNamesByReceiver: receivers.map(\.fileNames), dataCount: dataFlavors.count)

        // data flavor 즉시 물리화: 바이트를 verbatim으로 staging에 쓰고 `.received`를 emit한다.
        for flavor in dataFlavors {
            session.materialize(dataFlavor: flavor)
        }

        // receive 시작 후 receiver.fileNames를 예상 cardinality로 사용한다.
        for (index, receiver) in receivers.enumerated() {
            receiverRegistry[sessionID, default: []].append(receiver)
            receiver.receivePromisedFiles(
                atDestination: stagingURL,
                options: [:],
                operationQueue: queue,
            ) { @Sendable [weak session] url, error in
                // AppKit는 이 클로저를 non-main OperationQueue에서 호출한다. `begin`은
                // @MainActor이므로 @Sendable이 없으면 이 클로저가 MainActor로 추론되어
                // Swift 6 런타임 executor 검사에서 SIGTRAP한다. @Sendable로 nonisolated
                // 처리해 큐 스레드에서 handleCallback(이미 lock-guarded, off-main 안전)을
                // 호출한다.
                session?.handleCallback(receiverIndex: index, url: url, error: error)
            }
        }

        let orderedPromisedNames = receivers.flatMap(\.fileNames)
        var promisedOrdinals: [Int] = []
        for (index, receiver) in receivers.enumerated() {
            promisedOrdinals.append(contentsOf: receiver.fileNames.map { _ in index })
        }

        return ExternalDropAcceptedRequest(
            sessionID: sessionID,
            destination: destination,
            orderedPromisedNames: orderedPromisedNames,
            promisedOrdinals: promisedOrdinals,
            forcedCopy: forcedCopy,
            stagingDirectory: stagingURL.path,
        )
    }

    /// 레거시 promised-file 폴백 세션을 시작한다. `stagedPaths`는 이미 staging에 물리화된
    /// (존재·containment 검증 완료) 파일 경로이며, 세션은 이를 received-item으로 등록한다.
    /// receiver/data flavor가 없으므로 순수 cardinality만으로 성공/실패를 판정한다.
    @MainActor
    func beginLegacy(
        stagedPaths: [String],
        stagingDirectory: String,
        destination: String,
        forcedCopy: Bool,
    ) -> ExternalDropAcceptedRequest {
        let sessionID = ExternalDropSessionID()
        let session = ExternalDropAcquisitionSession(
            sessionID: sessionID,
            stagingDirectory: stagingDirectory,
            fileManager: fileManager,
            queue: queue,
        )
        sessions[sessionID] = session

        session.finalizeLegacyCardinality(stagedPaths.count)
        for path in stagedPaths {
            session.registerLegacyStagedFile(stagedPath: path)
        }

        return ExternalDropAcceptedRequest(
            sessionID: sessionID,
            destination: destination,
            orderedPromisedNames: [],
            promisedOrdinals: [],
            forcedCopy: forcedCopy,
            stagingDirectory: stagingDirectory,
        )
    }

    /// 지연 data-flavor 획득 세션을 시작한다. request는 로드 완료 전에 반환되고,
    /// 각 flavor의 load 클로저는 세션 OperationQueue에서 실행된 뒤 materialize된다.
    @MainActor
    func beginDeferred(
        items: [ExternalDropDeferredFlavor],
        destination: String,
        forcedCopy: Bool,
    ) -> ExternalDropAcceptedRequest {
        let sessionID = ExternalDropSessionID()
        let stagingURL = fileManager
            .temporaryDirectory()
            .appendingPathComponent("ExternalDrop-\(sessionID.rawValue)")
        try? fileManager.createDirectory(stagingURL, true, nil)

        let session = ExternalDropAcquisitionSession(
            sessionID: sessionID,
            stagingDirectory: stagingURL.path,
            fileManager: fileManager,
            queue: queue,
        )
        sessions[sessionID] = session
        session.finalizeCardinality(fileNamesByReceiver: [], dataCount: items.count)

        for item in items {
            queue.addOperation { [weak session] in
                guard let session else { return }
                guard let bytes = item.load() else {
                    session.fail(reason: .dataMaterializationFailed)
                    return
                }
                session.materialize(dataFlavor: ExternalDropDataFlavor(
                    uti: item.uti,
                    bytes: bytes,
                    filename: item.filename,
                ))
            }
        }

        return ExternalDropAcceptedRequest(
            sessionID: sessionID,
            destination: destination,
            orderedPromisedNames: [],
            promisedOrdinals: [],
            forcedCopy: forcedCopy,
            stagingDirectory: stagingURL.path,
        )
    }

    func events(for sessionID: ExternalDropSessionID) -> AsyncStream<ExternalDropAcquisitionEvent> {
        guard let session = sessions[sessionID] else {
            return AsyncStream { $0.finish() }
        }
        return session.events()
    }

    @MainActor
    func cancel(_ sessionID: ExternalDropSessionID) {
        guard let session = sessions[sessionID] else {
            return
        }
        session.cancel(fileManager: fileManager)
        receiverRegistry.removeValue(forKey: sessionID)
    }

    @MainActor
    func finish(_ sessionID: ExternalDropSessionID) {
        guard let session = sessions[sessionID] else {
            return
        }
        // cancel과 동일하게 세션은 `sessions`에 유지해 finish 후 도착하는 지연 콜백이
        // session을 소유하며 reported output/staging을 재삭제할 수 있게 한다.
        receiverRegistry.removeValue(forKey: sessionID)
        session.finish()
    }
}
