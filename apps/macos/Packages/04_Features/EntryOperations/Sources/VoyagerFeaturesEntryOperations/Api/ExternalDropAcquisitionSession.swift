@preconcurrency import AppKit
import Foundation
import os
import VoyagerShared

/// 세션별 획득 상태. AppKit receiver는 저장하지 않고 callback closure만 캡처한다.
///
/// 수명주기와 staging 제거는 별도 소유자로 분리해, 고칠 때마다 새 edge-case 구멍이
/// 생기던 암묵적 불린 4중주(isCancelled/isFinished/emittedTerminal/removedStaging)를
/// 명시적 `Phase` + `StagingDirectory`로 대체한다.
final class ExternalDropAcquisitionSession: @unchecked Sendable {
    /// 세션의 명시적 수명주기 상태. terminal은 정확히 한 번, staging 제거는 정확히 한 번
    /// 수행되도록 상태 전이로 강제한다. 불린 조합이 아닌 단일 열거형이라 상태 불변식이
    /// 암묵적이지 않다.
    enum Phase: Equatable {
        /// 수신 중. staging 존재, terminal 미발행.
        case acquiring
        /// `.succeeded` 발행. placement 복사가 끝날 때까지 staging을 보존한다.
        case succeededAwaitingPlacement
        /// 종료됨. staging이 이미 제거됨(실패/취소 종단, 성공+finish, 성공+cancel).
        case finished
    }

    let sessionID: ExternalDropSessionID
    private let staging: StagingDirectory
    private let fileManager: FileManagerClient
    private let queue: OperationQueue
    private let observationQueue: DispatchQueue

    private let lock = NSLock()
    private var phase: Phase = .acquiring
    /// 발행된 terminal 이벤트. 정확히 한 번 발행을 보장하기 위해 저장한다.
    private var terminalEvent: ExternalDropAcquisitionEvent?
    private var expectedCardinality: Int = 0
    /// cardinality가 확정됐는지 여부. 확정 전에 도착한 콜백이 성공을 내지 못하게 하는
    /// 최소 수명주기 가드다(receive 시작 후 콜백이 확정보다 먼저 도착할 수 있다).
    private var cardinalityFinalized = false
    private var receivedCount: Int = 0
    /// 결정적(파일명 있는 수신기 + data flavor) 기여 중 실제 수신된 수. 종단 판정에 쓴다.
    private var receivedDeterminateCount: Int = 0
    /// fileNames가 빈(기대 콜백 수 미정) 수신기의 index 집합. 미정 수신기는 카운트 기반
    /// 성공이 아니라 취소-재조정(provider가 userCancelled로 완료를 알림) 경로로만 종단한다.
    private var indeterminateReceivers: Set<Int> = []
    /// 명시적 취소-재조정(userCancelled + staged file)으로 완료된 미정 수신기의 index 집합.
    private var completedIndeterminateReceivers: Set<Int> = []
    private var receivedStagedPaths: Set<String> = []
    /// data flavor 파일명 충돌을 회피하기 위한 세션 내 사용 파일명 집합(canonical key).
    private var usedStagedFilenames: Set<String> = []
    private var nextItemOrdinal: Int = 0
    private var callbackCounts: [Int: Int] = [:]
    private var callbacksAwaitingCardinality: [(receiverIndex: Int, url: URL?, error: Error?)] = []
    private var pendingCancelledCallbacks: [Int: Int] = [:]
    private var callbackErrorTimeouts: [Int: DispatchWorkItem] = [:]
    private var stagingScanWorkItem: DispatchWorkItem?
    private var bufferedEvents: [ExternalDropAcquisitionEvent] = []
    private var continuation: AsyncStream<ExternalDropAcquisitionEvent>.Continuation?

    init(
        sessionID: ExternalDropSessionID,
        stagingDirectory: String,
        fileManager: FileManagerClient,
        queue: OperationQueue,
    ) {
        self.sessionID = sessionID
        staging = StagingDirectory(path: stagingDirectory, fileManager: fileManager)
        self.fileManager = fileManager
        self.queue = queue
        observationQueue = DispatchQueue(label: "fm.voyager.external-drop.\(sessionID.rawValue)")
    }

    func startStagingObservation() {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .acquiring, staging.observer == nil else { return }

        let fileDescriptor = Darwin.open(staging.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        let observer = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .link, .rename],
            queue: observationQueue,
        )
        observer.setEventHandler { [weak self] in
            self?.scheduleStagingScan()
        }
        observer.setCancelHandler {
            Darwin.close(fileDescriptor)
        }
        staging.attachObserver(observer)
        observer.activate()
    }

    /// receive 시작 후 receiver.fileNames를 기준으로 예상 cardinality를 확정한다.
    /// data flavor는 begin에서 이미 물리화되므로 `dataCount`를 결정적 cardinality에 더한다.
    /// fileNames가 빈 수신기는 기대 콜백 수가 미정이므로 결정적 수에 넣지 않고 취소-재조정
    /// 경로로만 종단한다. 그 외 결정적/미정 기여가 모두 비면 즉시 타입화 실패로 처리한다.
    func finalizeCardinality(fileNamesByReceiver: [[String]], dataCount: Int) {
        lock.lock()
        guard phase == .acquiring else {
            lock.unlock()
            return
        }

        var determinate = dataCount
        for (index, fileNames) in fileNamesByReceiver.enumerated() {
            if fileNames.isEmpty {
                indeterminateReceivers.insert(index)
                continue
            }
            switch ExternalDropAcquisitionSession.cardinalityState(for: fileNames) {
            case let .rejected(reason):
                emitTerminalLocked(.failed(sessionID, reason))
                lock.unlock()
                return
            case let .count(count):
                determinate += count
            }
        }
        expectedCardinality = determinate
        cardinalityFinalized = true
        let pendingCallbacks = callbacksAwaitingCardinality
        callbacksAwaitingCardinality.removeAll()
        if determinate == 0, indeterminateReceivers.isEmpty {
            emitTerminalLocked(.failed(sessionID, .emptyCardinality))
        } else if phase == .acquiring, sessionIsCompleteLocked() {
            // receive 중 동기적으로 도착한 콜백이 이미 받은 수를 채웠을 수 있다. cardinality
            // 확정 후에야 성공 판정이 가능하므로 lock을 보유한 채 재평가한다.
            emitTerminalLocked(.succeeded(sessionID))
        }
        lock.unlock()

        for callback in pendingCallbacks {
            handleCallback(
                receiverIndex: callback.receiverIndex,
                url: callback.url,
                error: callback.error,
            )
        }
    }

    /// 레거시 폴백: staging에 이미 존재하는 파일 수를 예상 cardinality로 확정한다.
    /// 빈 cardinality는 즉시 타입화 실패로 처리한다.
    func finalizeLegacyCardinality(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .acquiring else { return }
        expectedCardinality = count
        cardinalityFinalized = true
        if count == 0 {
            emitTerminalLocked(.failed(sessionID, .emptyCardinality))
        } else if phase == .acquiring, sessionIsCompleteLocked() {
            emitTerminalLocked(.succeeded(sessionID))
        }
    }

    /// data flavor 한 건을 staging에 verbatim으로 써서 `.received`를 emit한다.
    /// 쓰기 실패는 타입화 실패(`.dataMaterializationFailed`)로 귀결된다.
    func materialize(dataFlavor: ExternalDropDataFlavor) {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .acquiring else { return }
        // 같은 text 첫 줄 + UTI를 가진 data flavor가 같은 파일명을 만들면 두 번째 write가
        // 첫 번째 파일을 덮어쓴다. 세션 내에서 고유한 이름을 예약해 충돌을 회피한다.
        let filename = uniqueStagedFilename(for: dataFlavor.filename)
        let url = URL(fileURLWithPath: staging.path).appendingPathComponent(filename)
        do {
            try dataFlavor.bytes.write(to: url)
        } catch {
            emitTerminalLocked(.failed(sessionID, .dataMaterializationFailed))
            return
        }
        receivedStagedPaths.insert(url.standardizedFileURL.path)
        nextItemOrdinal += 1
        let itemOrdinal = nextItemOrdinal
        receivedCount += 1
        receivedDeterminateCount += 1
        emitLocked(.received(ExternalDropReceivedFile(
            sessionID: sessionID,
            itemOrdinal: itemOrdinal,
            callbackOrdinal: 0,
            stagedPath: url.path,
        )))
        if sessionIsCompleteLocked() {
            emitTerminalLocked(.succeeded(sessionID))
        }
    }

    /// 레거시 폴백: staging에 이미 물리화된 파일 한 건을 received-item으로 등록한다.
    /// 파일 존재·containment를 재검증하고 실패는 타입화 실패로 승격하지 않는다.
    func registerLegacyStagedFile(stagedPath: String) {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .acquiring else { return }
        let url = URL(fileURLWithPath: stagedPath)
        guard fileManager.fileExists(url.path), isInsideStaging(url) else {
            emitTerminalLocked(.failed(sessionID, .outsideStaging))
            return
        }
        receivedStagedPaths.insert(url.standardizedFileURL.path)
        nextItemOrdinal += 1
        let itemOrdinal = nextItemOrdinal
        receivedCount += 1
        receivedDeterminateCount += 1
        emitLocked(.received(ExternalDropReceivedFile(
            sessionID: sessionID,
            itemOrdinal: itemOrdinal,
            callbackOrdinal: 0,
            stagedPath: url.path,
        )))
        if sessionIsCompleteLocked() {
            emitTerminalLocked(.succeeded(sessionID))
        }
    }

    /// data flavor가 이미 확정된 promise 파일명과 충돌해 provider 쓰기를 실패시키지
    /// 않도록 파일명을 미리 예약한다. 물리화 시점에 data flavor가 다른 이름을 고른다.
    func reserveStagedFilenames(_ filenames: [String]) {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .acquiring else { return }
        for filename in filenames {
            usedStagedFilenames.insert(stagedFilenameKey(filename))
        }
    }

    /// data flavor 파일명이 세션 내에서 고유하도록 ` <n>` 접미로 충돌을 회피한다.
    /// caller는 lock을 보유해야 한다.
    private func uniqueStagedFilename(for original: String) -> String {
        var candidate = original
        var counter = 1
        while !usedStagedFilenames.insert(stagedFilenameKey(candidate)).inserted {
            counter += 1
            let ext = (original as NSString).pathExtension
            let base = (original as NSString).deletingPathExtension
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
        }
        return candidate
    }

    /// staging 볼륨에서 파일명이 filesystem상 동일하게 취급되는지 판정하는 canonical key.
    /// 기본 APFS처럼 case-insensitive + Unicode 정규화 볼륨에서는 조합형 `é`와 분해형
    /// `e◌́`가 같은 파일로 취급되므로, 예약/충돌 판정도 같은 동등성으로 수행해 두 번째
    /// payload가 첫 파일을 조용히 덮어쓰지 않게 한다. `EntryClipboardOperationsSupport`의
    /// destinationNameKey와 동일한 정규화(case folding + canonical mapping)를 적용한다.
    private func stagedFilenameKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive], locale: nil)
            .precomposedStringWithCanonicalMapping
    }

    /// 지연 data-flavor 로드를 세션 전용 큐에서 실행한다. 로드 실패는 타입화 실패로 종단 처리한다.
    func enqueueDeferredLoad(_ flavor: ExternalDropDeferredFlavor) {
        queue.addOperation { [weak self] in
            guard let self else { return }
            guard let bytes = flavor.load() else {
                fail(reason: .dataMaterializationFailed)
                return
            }
            materialize(dataFlavor: ExternalDropDataFlavor(
                uti: flavor.uti,
                bytes: bytes,
                filename: flavor.filename,
            ))
        }
    }

    /// promise receiver를 세션 전용 큐에서 수신을 시작한다. AppKit는 completion handler를
    /// non-main OperationQueue에서 호출하므로, lock-guarded `handleCallback`이 off-main에서
    /// 안전하게 실행된다.
    @MainActor
    func startReceiving(receiver: NSFilePromiseReceiver, atDestination destination: URL, index: Int) {
        receiver.receivePromisedFiles(
            atDestination: destination,
            options: [:],
            operationQueue: queue,
        ) { @Sendable [weak self] url, error in
            self?.handleCallback(receiverIndex: index, url: url, error: error)
        }
    }

    func events() -> AsyncStream<ExternalDropAcquisitionEvent> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            // buffered 이벤트를 lock을 보유한 채 순서대로 drain한다. 그렇지 않으면 snapshot 후
            // lock을 풀고 replay하는 사이 다른 스레드의 종단 emit이 continuation을 finish시켜
            // buffered `.received`가 yield 실패로 유실될 수 있다.
            let buffered = bufferedEvents
            let terminal = terminalEvent
            for event in buffered {
                continuation.yield(event)
            }
            if terminal != nil {
                continuation.finish()
                self.continuation = nil
            }
            lock.unlock()
        }
    }

    /// reader 콜백. non-main OperationQueue에서 실행된다.
    func handleCallback(receiverIndex: Int, url: URL?, error: Error?) {
        lock.lock()
        if handleTerminalCallback(reportedURL: url) {
            return
        }
        guard cardinalityFinalized else {
            callbacksAwaitingCardinality.append((receiverIndex, url, error))
            lock.unlock()
            return
        }

        let callbackOrdinal = (callbackCounts[receiverIndex] ?? 0) + 1
        callbackCounts[receiverIndex] = callbackOrdinal

        // 일부 provider는 취소 callback 뒤에 source-owned 파일을 쓰므로 staging 관찰을 먼저 기다린다.
        let resolvedURL: URL?
        if let error {
            logCallbackError(error)
            resolvedURL = reconciledCallbackURL(reportedURL: url)
            guard resolvedURL != nil else {
                if shouldAwaitStagedFile(error: error, receiverIndex: receiverIndex) {
                    pendingCancelledCallbacks[receiverIndex] = callbackOrdinal
                    scheduleCallbackErrorTimeoutLocked(receiverIndex: receiverIndex)
                    lock.unlock()
                    return
                }
                emitTerminalLocked(.failed(sessionID, .callbackError))
                lock.unlock()
                return
            }
        } else {
            resolvedURL = url
        }
        guard let resolvedURL else {
            emitTerminalLocked(.failed(sessionID, .missingURL))
            lock.unlock()
            return
        }
        guard fileManager.fileExists(resolvedURL.path) else {
            emitTerminalLocked(.failed(sessionID, .fileAbsent))
            lock.unlock()
            return
        }
        guard isInsideStaging(resolvedURL) else {
            emitTerminalLocked(.failed(sessionID, .outsideStaging))
            lock.unlock()
            return
        }
        guard receivedStagedPaths.insert(resolvedURL.standardizedFileURL.path).inserted else {
            emitTerminalLocked(.failed(sessionID, .callbackError))
            lock.unlock()
            return
        }
        if error != nil { Self.logger.info("callback error reconciled by staged file") }

        // 결정적 수신기에서 마지막 콜백이 URL과 error를 함께 전달하면, registerReceivedFile이
        // cardinality 충족으로 먼저 `.succeeded`를 내고(phase가 .acquiring을 벗어남) 뒤의 error
        // 검사가 항상 거짓이 되어 오류가 무시될 수 있다. hasError를 넘겨 결정적 성공을 억제해
        // `.callbackError` 종단을 보장한다(코멘트 #3826514658). 미정 수신기 것은 기존 계약
        // (취소 error + staged file = 성공)대로 재조정 종단 판정에 맡긴다.
        registerReceivedFile(
            receiverIndex: receiverIndex,
            url: resolvedURL,
            callbackOrdinal: callbackOrdinal,
            hasError: error != nil,
            cancelReconciled: error != nil && isUserCancelled(error),
        )
        if let error, phase == .acquiring, !shouldAwaitStagedFile(error: error, receiverIndex: receiverIndex) {
            emitTerminalLocked(.failed(sessionID, .callbackError))
        }
        lock.unlock()
    }

    private func isUserCancelled(_ error: Error?) -> Bool {
        guard let nsError = error as NSError? else { return false }
        return nsError.domain == NSCocoaErrorDomain
            && nsError.code == CocoaError.Code.userCancelled.rawValue
    }

    private func logCallbackError(_ error: Error) {
        let nsError = error as NSError
        Self.logger.error(
            "callback error domain=\(nsError.domain, privacy: .public) code=\(nsError.code)",
        )
    }

    private func reconciledCallbackURL(reportedURL: URL?) -> URL? {
        if let reportedURL,
           fileManager.fileExists(reportedURL.path),
           isInsideStaging(reportedURL),
           !receivedStagedPaths.contains(reportedURL.standardizedFileURL.path)
        {
            return reportedURL
        }
        let candidates = unregisteredStagingURLs()
        guard candidates.count == 1 else { return nil }
        return candidates[0]
    }

    private func shouldAwaitStagedFile(error: Error, receiverIndex: Int) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain
            && nsError.code == CocoaError.Code.userCancelled.rawValue
            && indeterminateReceivers.contains(receiverIndex)
    }

    private func scheduleCallbackErrorTimeoutLocked(receiverIndex: Int) {
        callbackErrorTimeouts[receiverIndex]?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            self?.failPendingCallback(receiverIndex: receiverIndex)
        }
        callbackErrorTimeouts[receiverIndex] = timeout
        observationQueue.asyncAfter(deadline: .now() + 1, execute: timeout)
    }

    private func scheduleStagingScan() {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .acquiring else { return }

        stagingScanWorkItem?.cancel()
        let scan = DispatchWorkItem { [weak self] in
            self?.handleStagingWrite()
        }
        stagingScanWorkItem = scan
        observationQueue.asyncAfter(deadline: .now() + 0.25, execute: scan)
    }

    private func handleStagingWrite() {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .acquiring else { return }
        stagingScanWorkItem = nil

        let pending = pendingCancelledCallbacks.sorted { $0.key < $1.key }
        let candidates = unregisteredStagingURLs()
        guard !pending.isEmpty, pending.count == candidates.count else { return }

        for ((receiverIndex, callbackOrdinal), url) in zip(pending, candidates) {
            pendingCancelledCallbacks.removeValue(forKey: receiverIndex)
            callbackErrorTimeouts.removeValue(forKey: receiverIndex)?.cancel()
            guard receivedStagedPaths.insert(url.standardizedFileURL.path).inserted else { continue }
            registerReceivedFile(
                receiverIndex: receiverIndex,
                url: url,
                callbackOrdinal: callbackOrdinal,
                cancelReconciled: true,
            )
            if phase != .acquiring { return }
        }
    }

    private func failPendingCallback(receiverIndex: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .acquiring,
              pendingCancelledCallbacks.removeValue(forKey: receiverIndex) != nil
        else {
            return
        }
        callbackErrorTimeouts.removeValue(forKey: receiverIndex)
        emitTerminalLocked(.failed(sessionID, .callbackError))
    }

    private func unregisteredStagingURLs() -> [URL] {
        let stagingURL = URL(fileURLWithPath: staging.path)
        guard let entries = try? fileManager.contentsOfDirectory(stagingURL, nil, []) else { return [] }
        return entries
            .filter {
                fileManager.fileExists($0.path)
                    && isInsideStaging($0)
                    && !receivedStagedPaths.contains($0.standardizedFileURL.path)
            }
            .sorted { $0.path < $1.path }
    }

    private func registerReceivedFile(
        receiverIndex: Int,
        url: URL,
        callbackOrdinal: Int,
        hasError: Bool = false,
        cancelReconciled: Bool = false,
    ) {
        nextItemOrdinal += 1
        let itemOrdinal = nextItemOrdinal
        receivedCount += 1
        let isIndeterminate = indeterminateReceivers.contains(receiverIndex)
        if !isIndeterminate {
            receivedDeterminateCount += 1
        }

        let receivedFile = ExternalDropReceivedFile(
            sessionID: sessionID,
            itemOrdinal: itemOrdinal,
            callbackOrdinal: callbackOrdinal,
            stagedPath: url.path,
        )
        emitLocked(.received(receivedFile))

        if isIndeterminate {
            // 미정(빈 fileNames) 수신기는 카운트 기반 성공이 불가능하다. provider가
            // userCancelled로 완료를 알려 파일을 재조정한 경우에만 "명시적 완료"로 기록하고,
            // 정상 성공 콜백은 예상 cardinality를 알 수 없으므로 `.emptyCardinality`로 실패한다.
            // 그 외 오류 콜백은 호출자(`handleCallback`)가 `.callbackError`로 종단한다.
            if cancelReconciled {
                completedIndeterminateReceivers.insert(receiverIndex)
                if sessionIsCompleteLocked() {
                    emitTerminalLocked(.succeeded(sessionID))
                }
            } else if !hasError {
                emitTerminalLocked(.failed(sessionID, .emptyCardinality))
            }
        } else if !hasError, sessionIsCompleteLocked() {
            emitTerminalLocked(.succeeded(sessionID))
        }
    }

    /// 취소/종료 이후 도착한 지연 콜백의 reported output과 staging을 재삭제한다. 이벤트는 내지 않는다.
    /// staging 밖 URL(예: source 앱이 늦게 보고한 원본 파일)은 containment 검증 없이
    /// 삭제하면 사용자 파일이 제거될 수 있으므로 staging 내부 경로에만 재삭제를 적용한다.
    private func removeLateCallbackArtifacts(reportedURL: URL?) {
        if let reportedURL, isInsideStaging(reportedURL) {
            try? fileManager.removeItem(reportedURL)
        }
        staging.removeIfPresent()
    }

    /// 취소/종료 이후 지연 콜백을 처리하고 staging을 정리한다. staging이 이미 제거된 상태에서
    /// 늦은 콜백이 경로를 재생성하면 잔류하므로 재정리한다. placement 복사가 끝나기 전
    /// (`.succeededAwaitingPlacement`, staging 보존 중)에는 staging을 건드리지 않는다.
    /// caller는 lock을 보유해야 하며, true를 반환하면 호출자가 unlock 후 반환해야 한다.
    /// false를 반환하면 정상 수신 콜백으로 계속 처리한다.
    private func handleTerminalCallback(reportedURL: URL?) -> Bool {
        // acquiring: 아직 수신 중이면 정상 처리 경로로 진행한다.
        if phase == .acquiring {
            return false
        }
        // 그 외(terminal 이미 발행): staging이 아직 보존 중(succeededAwaitingPlacement)이면
        // 정리하지 않고, staging이 이미 제거됐으면 늦은 콜백이 재생성한 경로를 재정리한다.
        if staging.isRemoved {
            lock.unlock()
            removeLateCallbackArtifacts(reportedURL: reportedURL)
            return true
        }
        lock.unlock()
        return true
    }

    /// 취소: 세션 무효화, 로컬 큐 취소, staging 즉시 제거, `.cancelled` 이벤트.
    /// provider-side cancellation은 주장하지 않는다.
    /// `.succeeded` emit 후(성공 종단 직후, reducer가 아직 placement를 시작하기 전) 취소가
    /// 와도 staging은 제거한다. 그렇지 않으면 finish 호출자가 사라져 staging이 영구 잔류한다.
    /// 이때 `.cancelled`는 이미 종단이 나갔으므로 emit하지 않는다.
    func cancel(fileManager _: FileManagerClient) {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .acquiring || phase == .succeededAwaitingPlacement else { return }
        queue.cancelAllOperations()
        switch phase {
        case .acquiring:
            emitTerminalLocked(.cancelled(sessionID))
        case .succeededAwaitingPlacement:
            // 이미 성공 종단 발행, staging만 제거한다. `.cancelled`는 재발행하지 않는다.
            staging.remove()
            phase = .finished
        case .finished:
            break
        }
    }

    /// 정상 종료: 멱등. staging을 정확히 한 번 제거한다. `.succeeded` 종단 후 호출돼도
    /// (이미 성공 종단으로 표시됐어도) staging을 정리한다.
    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .acquiring || phase == .succeededAwaitingPlacement else { return }
        staging.remove()
        queue.cancelAllOperations()
        phase = .finished
    }

    // MARK: - Event emission (caller must hold lock)

    private static let logger = Logger(subsystem: "fm.voyager.external-drop", category: "acquisition")

    private func emitLocked(_ event: ExternalDropAcquisitionEvent) {
        bufferedEvents.append(event)
        continuation?.yield(event)
    }

    /// terminal 이벤트를 정확히 한 번 발행한다. `.succeeded`는 placement 복사가 끝날 때까지
    /// staging을 보존하고(`.succeededAwaitingPlacement`), 실패/취소는 즉시 staging을 제거한다.
    /// caller는 lock을 보유해야 한다.
    private func emitTerminalLocked(_ event: ExternalDropAcquisitionEvent) {
        guard terminalEvent == nil else { return }
        terminalEvent = event
        switch event {
        case .succeeded:
            phase = .succeededAwaitingPlacement
        case .failed, .cancelled:
            staging.remove()
            phase = .finished
        case .received:
            break
        }
        teardownLocked()
        bufferedEvents.append(event)
        continuation?.yield(event)
        continuation?.finish()
        continuation = nil
        let loggedSessionID = sessionID.rawValue
        let loggedReceivedCount = receivedCount
        switch event {
        case .succeeded:
            Self.logger
                .info(
                    "session \(loggedSessionID, privacy: .public) succeeded received=\(loggedReceivedCount)",
                )
        case let .failed(_, reason):
            let loggedReason = String(describing: reason)
            Self.logger
                .info(
                    "session \(loggedSessionID, privacy: .public) failed reason=\(loggedReason, privacy: .public)",
                )
        case .cancelled:
            Self.logger.info("session \(loggedSessionID, privacy: .public) cancelled")
        case .received:
            break
        }
    }

    /// terminal 발행 후 진행 중인 타이머·큐·관찰을 정리한다. caller는 lock을 보유해야 한다.
    private func teardownLocked() {
        staging.observer?.cancel()
        staging.detachObserver()
        stagingScanWorkItem?.cancel()
        stagingScanWorkItem = nil
        callbackErrorTimeouts.values.forEach { $0.cancel() }
        callbackErrorTimeouts.removeAll()
        pendingCancelledCallbacks.removeAll()
        queue.cancelAllOperations()
    }

    private func isInsideStaging(_ url: URL) -> Bool {
        let stagingComponents = URL(
            fileURLWithPath: FileChangeScopePolicy.canonicalPath(staging.path),
        ).pathComponents
        let fileComponents = URL(
            fileURLWithPath: FileChangeScopePolicy.canonicalPath(url.path),
        ).pathComponents
        return fileComponents.starts(with: stagingComponents) && fileComponents.count > stagingComponents.count
    }

    // MARK: - Cardinality

    enum Cardinality {
        case count(Int)
        case rejected(ExternalDropRejectReason)
    }

    static func cardinalityState(for fileNames: [String]) -> Cardinality {
        guard !fileNames.isEmpty else { return .rejected(.emptyCardinality) }
        if fileNames.allSatisfy({ $0 == indeterminateNameMarker }) {
            return .rejected(.indeterminateCardinality)
        }
        return .count(fileNames.count)
    }

    /// 종단(성공) 판정. cardinality가 확정됐고, 결정적 기여(파일명 있는 수신기 + data flavor)
    /// 가 모두 수신됐으며, 모든 미정 수신기가 명시적 취소-재조정으로 완료됐을 때 성공이다.
    /// caller는 lock을 보유해야 한다.
    private func sessionIsCompleteLocked() -> Bool {
        guard cardinalityFinalized else { return false }
        return receivedDeterminateCount >= expectedCardinality
            && completedIndeterminateReceivers.isSuperset(of: indeterminateReceivers)
    }
}

extension ExternalDropAcquisitionSession {
    /// 큐에서 실행되는 지연 load가 실패했을 때 세션을 타입화 실패로 종단 처리한다.
    func fail(reason: ExternalDropRejectReason) {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .acquiring else { return }
        emitTerminalLocked(.failed(sessionID, reason))
    }

    private static let indeterminateNameMarker = "NSFilePromiseUnknown"
}

/// 세션 staging 디렉터리의 수명주기 소유자. 생성 경로와 제거 상태를 단일 소유해
/// "정확히 한 번 제거"가 상태 전이로 보장된다.
private final class StagingDirectory {
    let path: String
    private let fileManager: FileManagerClient
    private(set) var isRemoved = false
    /// 파일시스템 관찰 소스. 외부에서 attach/teardown을 관리한다.
    var observer: DispatchSourceFileSystemObject?

    init(path: String, fileManager: FileManagerClient) {
        self.path = path
        self.fileManager = fileManager
    }

    func attachObserver(_ observer: DispatchSourceFileSystemObject) {
        self.observer = observer
    }

    func detachObserver() {
        observer = nil
    }

    /// staging을 정확히 한 번 제거한다(멱등).
    func remove() {
        guard !isRemoved else { return }
        isRemoved = true
        try? fileManager.removeItem(URL(fileURLWithPath: path))
    }

    /// 이미 제거됐어도 물리 staging 경로 제거를 항상 시도한다(늦은 콜백 재생성 대비).
    /// `remove()`와 달리 isRemoved 가드로 조기 반환하지 않으므로, finish 후 provider가
    /// staging 루트를 재생성해도 늦은 콜백 시 다시 제거된다.
    func removeIfPresent() {
        isRemoved = true
        try? fileManager.removeItem(URL(fileURLWithPath: path))
    }
}
