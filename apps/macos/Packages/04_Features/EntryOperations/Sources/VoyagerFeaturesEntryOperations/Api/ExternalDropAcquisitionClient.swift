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
    /// 받아 물리화하고, 즉시 file URL 경로는 복사 배치에 포함시킨다. Sendable 요청 메타데이터만 반환한다.
    public var begin: @MainActor @Sendable ([NSFilePromiseReceiver], [ExternalDropDataFlavor], String, Bool, [String])
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

    nonisolated public init(
        begin: @escaping @MainActor @Sendable (
            [NSFilePromiseReceiver], [ExternalDropDataFlavor], String, Bool, [String],
        ) -> ExternalDropAcceptedRequest,
        events: @escaping @MainActor @Sendable (ExternalDropSessionID) -> AsyncStream<ExternalDropAcquisitionEvent>,
        cancel: @escaping @MainActor @Sendable (ExternalDropSessionID) -> Void,
        finish: @escaping @MainActor @Sendable (ExternalDropSessionID) -> Void,
        beginLegacy: @escaping @MainActor @Sendable ([String], String, String, Bool) -> ExternalDropAcceptedRequest,
    ) {
        self.begin = begin
        self.events = events
        self.cancel = cancel
        self.finish = finish
        self.beginLegacy = beginLegacy
    }
}

extension ExternalDropAcquisitionClient: DependencyKey {
    /// coordinator(begin)와 reducer(events)가 같은 session registry를 공유하도록
    /// 단일 인스턴스로 고정한다. computed var면 접근마다 새 store가 만들어져
    /// reducer가 다른 registry에서 빈 stream을 받아 import가 영구 pending이 된다.
    public static let liveValue: ExternalDropAcquisitionClient = live(fileManager: .liveValue)

    public static func live(
        fileManager: FileManagerClient,
        sessionTombstoneSeconds: TimeInterval = 60,
    ) -> ExternalDropAcquisitionClient {
        MainActor.assumeIsolated {
            ExternalDropAcquisitionLive.live(
                fileManager: fileManager,
                sessionTombstoneSeconds: sessionTombstoneSeconds,
            )
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
            begin: { _, _, destination, forcedCopy, immediateURLPaths in
                ExternalDropAcceptedRequest(
                    sessionID: ExternalDropSessionID(),
                    destination: destination,
                    orderedPromisedNames: [],
                    promisedOrdinals: [],
                    forcedCopy: forcedCopy,
                    stagingDirectory: "",
                    immediateURLPaths: immediateURLPaths,
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
    static func live(
        fileManager: FileManagerClient,
        sessionTombstoneSeconds: TimeInterval = 60,
    ) -> ExternalDropAcquisitionClient {
        let store = ExternalDropAcquisitionStore(
            fileManager: fileManager,
            sessionTombstoneSeconds: sessionTombstoneSeconds,
        )
        return ExternalDropAcquisitionClient(
            begin: { receivers, dataFlavors, destination, forcedCopy, immediateURLPaths in
                store.begin(
                    receivers: receivers,
                    dataFlavors: dataFlavors,
                    destination: destination,
                    forcedCopy: forcedCopy,
                    immediateURLPaths: immediateURLPaths,
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
        )
    }
}

/// AppKit receiver registry는 main actor에 격리하고, 콜백 세션에는 Sendable 상태만 둔다.
@MainActor
private final class ExternalDropAcquisitionStore {
    private var sessions: [ExternalDropSessionID: ExternalDropAcquisitionSession] = [:]
    private var receiverRegistry: [ExternalDropSessionID: [NSFilePromiseReceiver]] = [:]
    private let fileManager: FileManagerClient
    /// 종단 후 늦은 콜백의 staging 재삭제를 보장하는 tombstone 기간(초). 이후 registry에서 회수한다.
    private let sessionTombstoneSeconds: TimeInterval

    init(fileManager: FileManagerClient, sessionTombstoneSeconds: TimeInterval = 60) {
        self.fileManager = fileManager
        self.sessionTombstoneSeconds = sessionTombstoneSeconds
    }

    /// 세션 전용 OperationQueue를 생성한다. 한 세션의 `cancelAllOperations()`가 다른 세션의
    /// 대기 작업을 취소하지 않도록 각 세션이 고유 큐를 소유한다.
    @MainActor
    private func makeSessionQueue() -> OperationQueue {
        let queue = OperationQueue()
        queue.name = "com.voyager.external-drop-acquisition-\(ExternalDropSessionID().rawValue)"
        queue.maxConcurrentOperationCount = 1
        return queue
    }

    /// 외부 drop 획득을 동기적으로 시작한다. main actor에서 호출된다.
    @MainActor
    func begin(
        receivers: [NSFilePromiseReceiver],
        dataFlavors: [ExternalDropDataFlavor],
        destination: String,
        forcedCopy: Bool,
        immediateURLPaths: [String],
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
            queue: makeSessionQueue(),
        )

        sessions[sessionID] = session
        if !receivers.isEmpty {
            session.startStagingObservation()
        }

        // cardinality 검증: empty/indeterminate는 추측 성공이 아닌 타입화 실패다.
        // data flavor는 begin에서 동기적으로 물리화되므로 promise fileNames 수에 더한다.
        session.finalizeCardinality(fileNamesByReceiver: receivers.map(\.fileNames), dataCount: dataFlavors.count)

        // 확정된 promise 파일명을 먼저 예약해 data flavor가 같은 이름으로 staging에 쓰는
        // 것을 방지한다(data-promise 충돌 시 provider 쓰기 실패로 전체 drop이 실패한다).
        session.reserveStagedFilenames(receivers.flatMap(\.fileNames))

        // data flavor 즉시 물리화: 바이트를 verbatim으로 staging에 쓰고 `.received`를 emit한다.
        for flavor in dataFlavors {
            session.materialize(dataFlavor: flavor)
        }

        // receive 시작 후 receiver.fileNames를 예상 cardinality로 사용한다.
        for (index, receiver) in receivers.enumerated() {
            receiverRegistry[sessionID, default: []].append(receiver)
            session.startReceiving(receiver: receiver, atDestination: stagingURL, index: index)
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
            immediateURLPaths: immediateURLPaths,
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
            queue: makeSessionQueue(),
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
        scheduleSessionReclaim(sessionID)
    }

    @MainActor
    func finish(_ sessionID: ExternalDropSessionID) {
        guard let session = sessions[sessionID] else {
            return
        }
        receiverRegistry.removeValue(forKey: sessionID)
        session.finish()
        scheduleSessionReclaim(sessionID)
    }

    /// 종단 후 짧은 tombstone 기간 동안 늦은 콜백의 재삭제를 허용한 뒤 세션을 회수해
    /// 장시간 실행에서 sessions/queue/bufferedEvents가 무한 증가하지 않게 한다.
    @MainActor
    private func scheduleSessionReclaim(_ sessionID: ExternalDropSessionID) {
        let tombstone = sessionTombstoneSeconds
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(tombstone * 1_000_000_000))
            self?.sessions.removeValue(forKey: sessionID)
        }
    }
}
