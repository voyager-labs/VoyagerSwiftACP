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
    public var begin: @MainActor @Sendable (
        [NSFilePromiseReceiver], [ExternalDropDeferredFlavor], String, Bool, [String], [Int], [Int],
    ) -> ExternalDropAcceptedRequest

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
    /// `promisedOrdinals`는 negotiation이 확정한 logical promise item의 pasteboard 순번이다.
    /// 이름 수 == 항목 수면 1:1, 항목이 하나면 전체가 그 항목에 속한다. 그 외엔 경계를
    /// 복구할 수 없으므로 출력 수로 pasteboard ordinal을 날조하지 않고 fail-closed한다(P1-C).
    public var beginLegacy: @MainActor @Sendable (
        [String], String, String, Bool, [String], [Int], [Int],
    ) -> ExternalDropAcceptedRequest

    /// 레거시 promised-file 폴백의 staging 디렉터리를 destination 하위에 준비한다.
    /// 주입된 `FileManagerClient`로 생성하며, 실패 시 nil을 반환한다.
    public var prepareLegacyStaging: @MainActor @Sendable (String) -> String?

    /// 준비된 레거시 staging 안에서 source가 써 둔 이름/경로를 정규화·검증한다. `names`가
    /// 비어 있지 않고 각 이름이 staging 안의 실제 존재 파일이어야 한다. 하나라도 불일치하면
    /// staging을 제거하고 nil(전체 거절)을 반환한다. 한 legacy item이 여러 이름을 반환할 수
    /// 있으므로 item 수 제약은 두지 않는다. 파일시스템 경계와 실패 정리를 client가 단일 소유한다.
    public var finalizeLegacyStaging: @MainActor @Sendable ([String], String) -> [String]?

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

    /// placement가 path를 다시 열지 않도록 claim-time inode descriptor를 준비한다
    /// (코멘트 #3835329095). 하나라도 고정할 수 없으면 false로 실패 폐쇄한다.
    public var preparePlacementSources: @Sendable (ExternalDropSessionID, [String]) async -> Bool

    /// live session descriptor에서 destination으로 직접 복사한다. true면 복사를 처리했고,
    /// false면 테스트/default client가 기존 EntryFileOps copy로 fallback한다.
    public var copyPlacementSource: @Sendable (ExternalDropSessionID, String, String) async throws -> Bool

    nonisolated public init(
        begin: @escaping @MainActor @Sendable (
            [NSFilePromiseReceiver], [ExternalDropDeferredFlavor], String, Bool, [String], [Int], [Int],
        ) -> ExternalDropAcceptedRequest,
        events: @escaping @MainActor @Sendable (ExternalDropSessionID) -> AsyncStream<ExternalDropAcquisitionEvent>,
        cancel: @escaping @MainActor @Sendable (ExternalDropSessionID) -> Void,
        finish: @escaping @MainActor @Sendable (ExternalDropSessionID) -> Void,
        beginLegacy: @escaping @MainActor @Sendable (
            [String], String, String, Bool, [String], [Int], [Int],
        ) -> ExternalDropAcceptedRequest,
        prepareLegacyStaging: @escaping @MainActor @Sendable (String) -> String?,
        finalizeLegacyStaging: @escaping @MainActor @Sendable ([String], String) -> [String]?,
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
                immediateURLPaths: [],
            )
        },
        loadMailSource: @escaping @Sendable (MailMessageSourceLookup) -> Data? = { _ in nil },
        preparePlacementSources: @escaping @Sendable (ExternalDropSessionID, [String]) async -> Bool = { _, _ in true },
        copyPlacementSource: @escaping @Sendable (ExternalDropSessionID, String, String) async throws
            -> Bool = { _, _, _ in false },
    ) {
        self.begin = begin
        self.events = events
        self.cancel = cancel
        self.finish = finish
        self.beginLegacy = beginLegacy
        self.prepareLegacyStaging = prepareLegacyStaging
        self.finalizeLegacyStaging = finalizeLegacyStaging
        self.beginDeferred = beginDeferred
        self.loadMailSource = loadMailSource
        self.preparePlacementSources = preparePlacementSources
        self.copyPlacementSource = copyPlacementSource
    }
}

extension ExternalDropAcquisitionClient: DependencyKey {
    /// coordinator(begin)와 reducer(events)가 같은 session registry를 공유하도록
    /// 단일 인스턴스로 고정한다. computed var면 접근마다 새 store가 만들어져
    /// reducer가 다른 registry에서 빈 stream을 받아 import가 영구 pending이 된다.
    ///
    /// 단일 registry가 필연적인 이유:
    /// 1. coordinator의 `begin`이 세션을 등록하고, reducer의 `events`/`cancel`/`finish`가
    ///    같은 session ID로 이를 조회·소비한다. registry가 갈라지면 begin에서 만든 세션을
    ///    reducer가 찾지 못해 이벤트 유실·취소/종료 불일치가 발생한다.
    /// 2. 완전한 reducer-effect 이전은 불가능하다. `acceptDrop`은 AppKit의
    ///    `NSDraggingInfo`(비-Sendable)를 동기 경로에서 처리해야 하고, Sendable reducer
    ///    effect로는 non-Sendable 수신기와 staging을 경계를 넘어 전달할 수 없기 때문이다.
    /// S5 결론: `isDropTargeted`는 shared state로 유지하고, todo 1의
    /// `.setDropTargeted`는 상태 변화가 있을 때만 change-only로 send한다.
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
            begin: { _, _, destination, forcedCopy, immediateURLPaths, immediateURLOrdinals, _ in
                ExternalDropAcceptedRequest(
                    sessionID: ExternalDropSessionID(),
                    destination: destination,
                    orderedPromisedNames: [],
                    promisedOrdinals: [],
                    forcedCopy: forcedCopy,
                    stagingDirectory: "",
                    immediateURLPaths: immediateURLPaths,
                    immediateOrdinals: immediateURLOrdinals,
                )
            },
            events: { _ in AsyncStream { _ in } },
            cancel: { _ in },
            finish: { _ in },
            beginLegacy: { _, stagingDirectory, destination, forcedCopy, immediateURLPaths, immediateURLOrdinals, _ in
                ExternalDropAcceptedRequest(
                    sessionID: ExternalDropSessionID(),
                    destination: destination,
                    orderedPromisedNames: [],
                    promisedOrdinals: [],
                    forcedCopy: forcedCopy,
                    stagingDirectory: stagingDirectory,
                    immediateURLPaths: immediateURLPaths,
                    immediateOrdinals: immediateURLOrdinals,
                )
            },
            prepareLegacyStaging: { _ in nil },
            finalizeLegacyStaging: { _, _ in nil },
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
        return makeClient(store: store)
    }

    /// live 클라이언트 조립. store 클로저 바인딩만 담당해 `live` 본문을 짧게 유지한다.
    @MainActor
    private static func makeClient(store: ExternalDropAcquisitionStore) -> ExternalDropAcquisitionClient {
        ExternalDropAcquisitionClient(
            begin: { receivers, flavors, destination, forcedCopy, immediateURLs, immediateOrdinals, receiverOrds in
                store.begin(.init(
                    receivers: receivers,
                    dataFlavors: flavors,
                    destination: destination,
                    forcedCopy: forcedCopy,
                    immediateURLPaths: immediateURLs,
                    immediateURLOrdinals: immediateOrdinals,
                    receiverOrdinals: receiverOrds,
                ))
            },
            events: { store.events(for: $0) },
            cancel: { store.cancel($0) },
            finish: { store.finish($0) },
            beginLegacy: { paths, stagingDir, destination, forcedCopy, immediates, immOrds, promisedOrds in
                store.beginLegacy(
                    stagedPaths: paths,
                    stagingDirectory: stagingDir,
                    destination: destination,
                    forcedCopy: forcedCopy,
                    immediateURLPaths: immediates,
                    immediateURLOrdinals: immOrds,
                    promisedOrdinals: promisedOrds,
                )
            },
            prepareLegacyStaging: { store.prepareLegacyStaging(destinationPath: $0) },
            finalizeLegacyStaging: { names, stagingDirectory in
                store.finalizeLegacyStaging(names, stagingDirectory: stagingDirectory)
            },
            beginDeferred: { items, destination, forcedCopy in
                store.beginDeferred(
                    items: items,
                    destination: destination,
                    forcedCopy: forcedCopy,
                )
            },
            loadMailSource: { MailMessageSourceExport.load($0) },
            preparePlacementSources: { sessionID, paths in
                await store.preparePlacementSources(sessionID, paths: paths)
            },
            copyPlacementSource: { sessionID, sourcePath, destinationPath in
                try await store.copyPlacementSource(
                    sessionID,
                    sourcePath: sourcePath,
                    destinationPath: destinationPath,
                )
                return true
            },
        )
    }
}

/// modern begin의 입력 묶음. 클로저 시그니처 호환을 유지하면서 store 진입 파라미터 수를
/// function_parameter_count 한도 안으로 유지한다.
private struct ModernBeginInput {
    let receivers: [NSFilePromiseReceiver]
    let dataFlavors: [ExternalDropDeferredFlavor]
    let destination: String
    let forcedCopy: Bool
    let immediateURLPaths: [String]
    let immediateURLOrdinals: [Int]
    let receiverOrdinals: [Int]
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
    func begin(_ input: ModernBeginInput) -> ExternalDropAcceptedRequest {
        let receivers = input.receivers
        let dataFlavors = input.dataFlavors
        let destination = input.destination
        let forcedCopy = input.forcedCopy
        let immediateURLPaths = input.immediateURLPaths
        let immediateURLOrdinals = input.immediateURLOrdinals
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
            receiverOrdinals: input.receiverOrdinals,
        )

        sessions[sessionID] = session
        if !receivers.isEmpty {
            session.startStagingObservation()
        }

        // 재귀 즉시 URL 스냅숏은 세션 큐에서 수행하고 completion을 cardinality에 포함한다
        // (코멘트 #3835329097). request에는 미완료 경로를 넣지 않고 `.received` 이벤트로 전달한다.
        session.enqueueImmediateSnapshot(
            immediateURLPaths: immediateURLPaths,
            immediateURLOrdinals: immediateURLOrdinals,
        )

        startDeterminateAcquisition(
            receivers: receivers,
            dataFlavors: dataFlavors,
            session: session,
            sessionID: sessionID,
            stagingURL: stagingURL,
        )

        let promised = promisedNamesAndOrdinals(of: receivers)

        return ExternalDropAcceptedRequest(
            sessionID: sessionID,
            destination: destination,
            orderedPromisedNames: promised.names,
            promisedOrdinals: promised.ordinals,
            forcedCopy: forcedCopy,
            stagingDirectory: stagingURL.path,
        )
    }

    /// receiver 순서대로 promise 파일명과 파일별 pasteboard ordinal(receiver index)을 확장한다.
    /// 한 receiver가 여러 파일을 산출하면 그 index가 파일 수만큼 반복된다.
    private func promisedNamesAndOrdinals(
        of receivers: [NSFilePromiseReceiver],
    ) -> (names: [String], ordinals: [Int]) {
        let names = receivers.flatMap(\.fileNames)
        var ordinals: [Int] = []
        for (index, receiver) in receivers.enumerated() {
            ordinals.append(contentsOf: receiver.fileNames.map { _ in index })
        }
        return (names, ordinals)
    }

    /// receiver 수신 시작부터 cardinality 확정·data 물리화까지의 결정적 획득 단계를 순서대로
    /// 실행한다. pinning 실패 시에는 호출돼선 안 된다(P1-A).
    @MainActor
    private func startDeterminateAcquisition(
        receivers: [NSFilePromiseReceiver],
        dataFlavors: [ExternalDropDeferredFlavor],
        session: ExternalDropAcquisitionSession,
        sessionID: ExternalDropSessionID,
        stagingURL: URL,
    ) {
        // receive를 먼저 시작한다. provider cardinality(fileNames)는 receive 후에만
        // 채워지므로, 수신 시작 후의 값을 기준으로 cardinality를 확정·예약해야 한다.
        for (index, receiver) in receivers.enumerated() {
            receiverRegistry[sessionID, default: []].append(receiver)
            session.startReceiving(receiver: receiver, atDestination: stagingURL, index: index)
        }

        // cardinality 검증: empty/indeterminate는 추측 성공이 아닌 타입화 실패다.
        // data flavor는 아래에서 동기적으로 물리화되므로 promise fileNames 수에 더한다.
        session.finalizeCardinality(fileNamesByReceiver: receivers.map(\.fileNames), dataCount: dataFlavors.count)

        // 확정된 promise 파일명을 먼저 예약해 data flavor가 같은 이름으로 staging에 쓰는
        // 것을 방지한다(data-promise 충돌 시 provider 쓰기 실패로 전체 drop이 실패한다).
        session.reserveStagedFilenames(receivers.flatMap(\.fileNames))

        // data flavor 물리화: 바이트 로드와 staging 쓰기는 세션 큐에서 수행한다
        // (코멘트 #3837956591). accept 경계에서는 flavor 선언만 넘긴다.
        for flavor in dataFlavors {
            session.enqueueDeferredLoad(flavor)
        }
    }

    /// 종단 실패 후 reducer가 이벤트만 소비하도록 비어 있는 배치 요청을 만든다.
    /// accepted immediates/promises는 비운다(fail-closed).
    private func failClosedRequest(
        sessionID: ExternalDropSessionID,
        destination: String,
        forcedCopy: Bool,
        stagingDirectory: String,
    ) -> ExternalDropAcceptedRequest {
        ExternalDropAcceptedRequest(
            sessionID: sessionID,
            destination: destination,
            orderedPromisedNames: [],
            promisedOrdinals: [],
            forcedCopy: forcedCopy,
            stagingDirectory: stagingDirectory,
        )
    }

    /// 레거시 promised-file 폴백 staging 디렉터리를 destination 하위에 준비한다.
    /// 주입된 fileManager로 생성하며, 실패 시 nil을 반환해 전체 drop을 거절한다.
    @MainActor
    func prepareLegacyStaging(destinationPath: String) -> String? {
        let sessionID = ExternalDropSessionID()
        let stagingURL = URL(fileURLWithPath: destinationPath, isDirectory: true)
            .appendingPathComponent(".voyager-external-drop-\(sessionID.rawValue)")
        do {
            try fileManager.createDirectory(stagingURL, true, nil)
            return stagingURL.path
        } catch {
            return nil
        }
    }

    /// 레거시 staging 안에서 source가 써 둔 이름/경로를 정규화·검증한다. `names`가 비어
    /// 있지 않고 각 이름이 staging 안의 실제 존재 파일이어야 한다. 하나라도 불일치하면
    /// staging을 제거하고 nil(전체 거절)을 반환한다. 한 legacy item이 여러 이름을
    /// 반환할 수 있으므로 pasteboard item 수와의 일대일 제약은 두지 않는다
    /// (코멘트 #3830663095). 파일시스템 경계와 실패 정리를 client가 단일 소유한다.
    /// `names`는 `namesOfPromisedFilesDropped`가 반환한 원본(절대 경로 또는 이름)이다.
    @MainActor
    func finalizeLegacyStaging(
        _ names: [String],
        stagingDirectory: String,
    ) -> [String]? {
        let stagingURL = URL(fileURLWithPath: stagingDirectory, isDirectory: true)
        guard !names.isEmpty else {
            try? fileManager.removeItem(stagingURL)
            return nil
        }
        let stagedPaths = names.compactMap { name -> String? in
            let url = name.hasPrefix("/")
                ? URL(fileURLWithPath: name).standardizedFileURL
                : stagingURL.appendingPathComponent(name).standardizedFileURL
            guard fileManager.fileExists(url.path),
                  isInsideDirectory(url.path, of: stagingURL.path)
            else {
                return nil
            }
            return url.path
        }
        guard stagedPaths.count == names.count else {
            try? fileManager.removeItem(stagingURL)
            return nil
        }
        // 동일 파일을 다른 표기(file vs ./file)로 중복 반환하는 provider를 거절한다.
        // 중복 경로는 placement pendingPaths Set에서 한 항목으로 합쳐져 첫 복사
        // 완료만으로 세션이 종료되는 조기 종단을 유발한다(코멘트 #3840534607).
        // 항목마다 canonical 경로를 한 번만 삽입한다. raw·canonical을 같은 집합에
        // 연속 삽입하면 path == canonical인 정상 경로도 항상 거절된다(#3840576139).
        var seenCanonicalPaths = Set<String>()
        for path in stagedPaths {
            let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard seenCanonicalPaths.insert(canonical).inserted else {
                try? fileManager.removeItem(stagingURL)
                return nil
            }
        }
        return stagedPaths
    }

    /// `path`가 `directory`의 진정한 하위 경로인지 검사한다(자기 자신 제외). containment
    /// 검증은 파일시스템 경계를 소유하는 client가 단일 수행한다.
    @MainActor
    private func isInsideDirectory(_ path: String, of directory: String) -> Bool {
        let dirComponents = URL(
            fileURLWithPath: FileChangeScopePolicy.canonicalPath(directory),
        ).pathComponents
        let fileComponents = URL(
            fileURLWithPath: FileChangeScopePolicy.canonicalPath(path),
        ).pathComponents
        return fileComponents.starts(with: dirComponents) && fileComponents.count > dirComponents.count
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
        immediateURLPaths: [String] = [],
        immediateURLOrdinals: [Int] = [],
        promisedOrdinals: [Int] = [],
    ) -> ExternalDropAcceptedRequest {
        let sessionID = ExternalDropSessionID()
        let session = ExternalDropAcquisitionSession(
            sessionID: sessionID,
            stagingDirectory: stagingDirectory,
            fileManager: fileManager,
            queue: makeSessionQueue(),
        )
        sessions[sessionID] = session

        // flat 이름 목록과 logical promise item의 경계 복구(P1-C). 이름 수 == 항목 수면
        // 1:1 대응, 항목이 하나뿐이면 전체 파일이 그 항목에 속한다. 그 외엔 경계를 복구할
        // 수 없으므로 출력 수로 pasteboard ordinal을 날조하지 않고 fail-closed한다.
        guard let mappedOrdinals = mappedLegacyOrdinals(pathCount: stagedPaths.count,
                                                        promisedOrdinals: promisedOrdinals)
        else {
            // .indeterminateCardinality 종단이 staging(보관 디렉터리 포함)을 정리한다.
            session.fail(reason: .indeterminateCardinality)
            return failClosedRequest(
                sessionID: sessionID,
                destination: destination,
                forcedCopy: forcedCopy,
                stagingDirectory: stagingDirectory,
            )
        }

        // 즉시 URL 스냅숏은 세션 큐에서 수행하고 legacy staged 파일과 같은 성공 배리어에
        // 합친다. request에는 미완료 경로를 넣지 않고 `.received` 이벤트로 전달한다.
        session.enqueueImmediateSnapshot(
            immediateURLPaths: immediateURLPaths,
            immediateURLOrdinals: immediateURLOrdinals,
        )
        registerLegacyStagedFiles(stagedPaths, ordinals: mappedOrdinals, on: session)

        return ExternalDropAcceptedRequest(
            sessionID: sessionID,
            destination: destination,
            orderedPromisedNames: [],
            promisedOrdinals: [],
            forcedCopy: forcedCopy,
            stagingDirectory: stagingDirectory,
        )
    }

    /// flat 이름 수와 logical promise item 순번으로 pasteboard ordinal 대응을 복구한다(P1-C).
    /// 이름 수 == 항목 수면 1:1, 항목이 하나면 전체가 그 항목에 속한다. 그 외엔 nil(복구 불가).
    private func mappedLegacyOrdinals(pathCount: Int, promisedOrdinals: [Int]) -> [Int]? {
        if promisedOrdinals.count == pathCount {
            return promisedOrdinals
        }
        if promisedOrdinals.count == 1 {
            return Array(repeating: promisedOrdinals[0], count: pathCount)
        }
        return nil
    }

    /// 복구된 ordinal대로 legacy staged 파일을 received-item으로 등록하고 cardinality를 확정한다.
    /// 같은 logical item의 파일은 같은 pasteboard ordinal에 항목 내 순번(0-based)만 다르게 붙는다.
    private func registerLegacyStagedFiles(
        _ paths: [String],
        ordinals: [Int],
        on session: ExternalDropAcquisitionSession,
    ) {
        var withinItemCounts: [Int: Int] = [:]
        session.finalizeLegacyCardinality(paths.count)
        for (index, path) in paths.enumerated() {
            let pasteboardOrdinal = ordinals[index]
            let withinItemOrdinal = withinItemCounts[pasteboardOrdinal, default: 0]
            withinItemCounts[pasteboardOrdinal] = withinItemOrdinal + 1
            session.registerLegacyStagedFile(
                stagedPath: path,
                pasteboardOrdinal: pasteboardOrdinal,
                callbackOrdinal: withinItemOrdinal,
            )
        }
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
            queue: makeSessionQueue(),
        )
        sessions[sessionID] = session
        session.finalizeCardinality(fileNamesByReceiver: [], dataCount: items.count)

        for item in items {
            session.enqueueDeferredLoad(item)
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

    /// placement가 읽을 descriptor 경로를 준비한다(코멘트 #3835329095). registry에 없는
    /// 세션은 tombstone 정리 이후 온 요청일 수 있으므로 실패 폐쇄한다.
    @MainActor
    func preparePlacementSources(
        _ sessionID: ExternalDropSessionID,
        paths: [String],
    ) -> Bool {
        guard let session = sessions[sessionID] else {
            return false
        }
        return session.preparePlacementSources(paths: paths)
    }

    @MainActor
    func copyPlacementSource(
        _ sessionID: ExternalDropSessionID,
        sourcePath: String,
        destinationPath: String,
    ) async throws {
        guard let session = sessions[sessionID] else {
            throw CocoaError(.fileNoSuchFile)
        }
        // detached 복사는 부모 effect 취소를 상속하지 않으므로 핸들을 보관했다가
        // 호출자(effect) 취소 시 즉시 전파한다. 재귀 copier의 checkCancellation이
        // 이 신호로 중단하고 기존 실패-시-제거 계약으로 부분 목적지를 정리한다
        // (코멘트 #3840396987).
        let copyTask = Task.detached {
            try session.copyPlacementSource(sourcePath: sourcePath, destinationPath: destinationPath)
        }
        return try await withTaskCancellationHandler {
            try await copyTask.value
        } onCancel: {
            copyTask.cancel()
        }
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
