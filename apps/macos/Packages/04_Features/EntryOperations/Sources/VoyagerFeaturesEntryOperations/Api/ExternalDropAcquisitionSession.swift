@preconcurrency import AppKit
import Foundation
import os
import VoyagerShared

/// 세션별 획득 상태. AppKit receiver는 저장하지 않고 callback closure만 캡처한다.
final class ExternalDropAcquisitionSession: @unchecked Sendable {
    let sessionID: ExternalDropSessionID
    let stagingDirectory: String
    private let fileManager: FileManagerClient
    private let queue: OperationQueue
    private let observationQueue: DispatchQueue

    private let lock = NSLock()
    private var expectedCardinality: Int = 0
    private var receivedCount: Int = 0
    /// 결정적(파일명 있는 수신기 + data flavor) 기여 중 실제 수신된 수. 종단 판정에 쓴다.
    private var receivedDeterminateCount: Int = 0
    /// fileNames가 빈(기대 콜백 수 미정) 수신기의 index 집합.
    private var indeterminateReceivers: Set<Int> = []
    /// 미정 수신기 중 첫 성공 콜백이 도착해 완료된 index 집합.
    private var completedIndeterminateReceivers: Set<Int> = []
    private var receivedStagedPaths: Set<String> = []
    /// data flavor 파일명 충돌을 회피하기 위한 세션 내 사용 파일명 집합(소문자 키).
    private var usedStagedFilenames: Set<String> = []
    private var nextItemOrdinal: Int = 0
    private var callbackCounts: [Int: Int] = [:]
    private var pendingCancelledCallbacks: [Int: Int] = [:]
    private var callbackErrorTimeouts: [Int: DispatchWorkItem] = [:]
    private var stagingScanWorkItem: DispatchWorkItem?
    /// 미정(fileNames 빈) 수신기의 다중 파일 콜백을 수용하기 위한 quiescence 타이머.
    private var indeterminateQuiescenceWorkItem: DispatchWorkItem?
    private var stagingObserver: DispatchSourceFileSystemObject?
    private var isCancelled = false
    private var isFinished = false
    private var emittedTerminal = false
    private var removedStaging = false
    private var bufferedEvents: [ExternalDropAcquisitionEvent] = []
    private var continuation: AsyncStream<ExternalDropAcquisitionEvent>.Continuation?

    init(
        sessionID: ExternalDropSessionID,
        stagingDirectory: String,
        fileManager: FileManagerClient,
        queue: OperationQueue,
    ) {
        self.sessionID = sessionID
        self.stagingDirectory = stagingDirectory
        self.fileManager = fileManager
        self.queue = queue
        observationQueue = DispatchQueue(label: "fm.voyager.external-drop.\(sessionID.rawValue)")
    }

    func startStagingObservation() {
        lock.lock()
        defer { lock.unlock() }
        guard stagingObserver == nil else { return }

        let fileDescriptor = Darwin.open(stagingDirectory, O_EVTONLY)
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
        stagingObserver = observer
        observer.activate()
    }

    /// receive 시작 후 receiver.fileNames를 기준으로 예상 cardinality를 확정한다.
    /// data flavor는 begin에서 이미 물리화되므로 `dataCount`를 결정적 cardinality에 더한다.
    /// fileNames가 빈 수신기는 기대 콜백 수가 미정이므로 결정적 수에 넣지 않고, 첫 성공
    /// 콜백으로 완료 판정한다(VOY-736: Mail receiver의 fileNames 공백). 그 외 결정적/미정
    /// 기여가 모두 비면 즉시 타입화 실패로 처리한다.
    func finalizeCardinality(fileNamesByReceiver: [[String]], dataCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard !emittedTerminal else { return }

        var determinate = dataCount
        for (index, fileNames) in fileNamesByReceiver.enumerated() {
            if fileNames.isEmpty {
                indeterminateReceivers.insert(index)
                continue
            }
            switch ExternalDropAcquisitionSession.cardinalityState(for: fileNames) {
            case let .rejected(reason):
                emitTerminalLocked(.failed(sessionID, reason))
                return
            case let .count(count):
                determinate += count
            }
        }
        expectedCardinality = determinate
        if determinate == 0, indeterminateReceivers.isEmpty {
            emitTerminalLocked(.failed(sessionID, .emptyCardinality))
        }
    }

    /// 레거시 폴백: staging에 이미 존재하는 파일 수를 예상 cardinality로 확정한다.
    /// 빈 cardinality는 즉시 타입화 실패로 처리한다.
    func finalizeLegacyCardinality(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard !emittedTerminal else { return }
        expectedCardinality = count
        if count == 0 {
            emitTerminalLocked(.failed(sessionID, .emptyCardinality))
        }
    }

    /// data flavor 한 건을 staging에 verbatim으로 써서 `.received`를 emit한다.
    /// 쓰기 실패는 타입화 실패(`.dataMaterializationFailed`)로 귀결된다.
    func materialize(dataFlavor: ExternalDropDataFlavor) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled, !isFinished, !emittedTerminal else { return }
        // 같은 text 첫 줄 + UTI를 가진 data flavor가 같은 파일명을 만들면 두 번째 write가
        // 첫 번째 파일을 덮어쓴다. 세션 내에서 고유한 이름을 예약해 충돌을 회피한다.
        let filename = uniqueStagedFilename(for: dataFlavor.filename)
        let url = URL(fileURLWithPath: stagingDirectory).appendingPathComponent(filename)
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
        guard !isCancelled, !isFinished, !emittedTerminal else { return }
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
        guard !isCancelled, !isFinished, !emittedTerminal else { return }
        for filename in filenames {
            usedStagedFilenames.insert(filename.lowercased())
        }
    }

    /// data flavor 파일명이 세션 내에서 고유하도록 ` <n>` 접미로 충돌을 회피한다.
    /// caller는 lock을 보유해야 한다.
    private func uniqueStagedFilename(for original: String) -> String {
        var candidate = original
        var counter = 1
        while !usedStagedFilenames.insert(candidate.lowercased()).inserted {
            counter += 1
            let ext = (original as NSString).pathExtension
            let base = (original as NSString).deletingPathExtension
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
        }
        return candidate
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
            let terminal = emittedTerminal
            for event in buffered {
                continuation.yield(event)
            }
            if terminal {
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

        registerReceivedFile(receiverIndex: receiverIndex, url: resolvedURL, callbackOrdinal: callbackOrdinal)
        // reconcile로 복구된 error 콜백 중 미정 수신기 것은 quiescence 종단 판정에 맡긴다.
        // 기존 계약(취소 error + staged file = 성공)을 유지한다.
        if error != nil, !emittedTerminal, !indeterminateReceivers.contains(receiverIndex) {
            emitTerminalLocked(.failed(sessionID, .callbackError))
        }
        lock.unlock()
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
        guard !isCancelled, !isFinished, !emittedTerminal else { return }

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
        guard !isCancelled, !isFinished, !emittedTerminal else { return }
        stagingScanWorkItem = nil

        let pending = pendingCancelledCallbacks.sorted { $0.key < $1.key }
        let candidates = unregisteredStagingURLs()
        guard !pending.isEmpty, pending.count == candidates.count else { return }

        for ((receiverIndex, callbackOrdinal), url) in zip(pending, candidates) {
            pendingCancelledCallbacks.removeValue(forKey: receiverIndex)
            callbackErrorTimeouts.removeValue(forKey: receiverIndex)?.cancel()
            guard receivedStagedPaths.insert(url.standardizedFileURL.path).inserted else { continue }
            registerReceivedFile(receiverIndex: receiverIndex, url: url, callbackOrdinal: callbackOrdinal)
            if emittedTerminal { return }
        }
    }

    private func failPendingCallback(receiverIndex: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled, !isFinished, !emittedTerminal,
              pendingCancelledCallbacks.removeValue(forKey: receiverIndex) != nil
        else {
            return
        }
        callbackErrorTimeouts.removeValue(forKey: receiverIndex)
        emitTerminalLocked(.failed(sessionID, .callbackError))
    }

    private func unregisteredStagingURLs() -> [URL] {
        let stagingURL = URL(fileURLWithPath: stagingDirectory)
        guard let entries = try? fileManager.contentsOfDirectory(stagingURL, nil, []) else { return [] }
        return entries
            .filter {
                fileManager.fileExists($0.path)
                    && isInsideStaging($0)
                    && !receivedStagedPaths.contains($0.standardizedFileURL.path)
            }
            .sorted { $0.path < $1.path }
    }

    private func registerReceivedFile(receiverIndex: Int, url: URL, callbackOrdinal: Int) {
        nextItemOrdinal += 1
        let itemOrdinal = nextItemOrdinal
        receivedCount += 1
        let isIndeterminate = indeterminateReceivers.contains(receiverIndex)
        if isIndeterminate {
            // 미정 수신기: 첫 성공 콜백으로 "기여 시작"을 표시한다. 다중 파일 전달 대비해
            // 아래에서 quiescence 후 최종 종단을 판정한다.
            completedIndeterminateReceivers.insert(receiverIndex)
        } else {
            receivedDeterminateCount += 1
        }

        let receivedFile = ExternalDropReceivedFile(
            sessionID: sessionID,
            itemOrdinal: itemOrdinal,
            callbackOrdinal: callbackOrdinal,
            stagedPath: url.path,
        )
        emitLocked(.received(receivedFile))

        if indeterminateReceivers.isEmpty {
            // 미정 수신기가 없으면 즉시 종단 판정한다(기존 동작).
            if sessionIsCompleteLocked() {
                emitTerminalLocked(.succeeded(sessionID))
            }
        } else {
            // 미정 수신기가 있으면 첫 콜백에서 곧바로 성공을 내지 않고, 같은 receiver의
            // 추가 콜백(다중 파일)을 수용하기 위해 quiescence 타이머로 최종 종단을 지연한다.
            scheduleIndeterminateQuiescenceLocked()
        }
    }

    /// 미정 수신기의 종단 판정을 quiescence(추가 콜백 대기) 후로 지연한다. 같은 receiver에서
    /// 여러 파일이 콜백으로 전달될 때 첫 callback만으로 완료 처리하지 않도록 한다.
    /// caller는 lock을 보유해야 한다.
    private func scheduleIndeterminateQuiescenceLocked() {
        guard !emittedTerminal, !isFinished, !isCancelled else { return }
        indeterminateQuiescenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.evaluateIndeterminateCompletion()
        }
        indeterminateQuiescenceWorkItem = workItem
        observationQueue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func evaluateIndeterminateCompletion() {
        lock.lock()
        defer { lock.unlock() }
        indeterminateQuiescenceWorkItem = nil
        guard !isCancelled, !isFinished, !emittedTerminal else { return }
        if sessionIsCompleteLocked() {
            emitTerminalLocked(.succeeded(sessionID))
        }
    }

    /// 취소/종료 이후 도착한 지연 콜백의 reported output과 staging을 재삭제한다. 이벤트는 내지 않는다.
    /// staging 밖 URL(예: source 앱이 늦게 보고한 원본 파일)은 containment 검증 없이
    /// 삭제하면 사용자 파일이 제거될 수 있으므로 staging 내부 경로에만 재삭제를 적용한다.
    private func removeLateCallbackArtifacts(reportedURL: URL?, staging: String, fileManager: FileManagerClient) {
        if let reportedURL, isInsideStaging(reportedURL) {
            try? fileManager.removeItem(reportedURL)
        }
        try? fileManager.removeItem(URL(fileURLWithPath: staging))
    }

    /// 취소/종료 이후 지연 콜백을 처리하고 staging을 정리한다. 성공 종단(.succeeded)은
    /// emittedTerminal과 isFinished를 함께 세우므로, 이때는 staging을 건드리지 않는다.
    /// 성공 직후 reducer가 placement(복사)를 시작하므로 staging은 `finish()`가 정리할
    /// 때까지 보존돼야 한다. caller는 lock을 보유해야 하며, true를 반환하면 호출자가
    /// unlock 후 반환해야 한다.
    private func handleTerminalCallback(reportedURL: URL?) -> Bool {
        if isCancelled || (isFinished && !emittedTerminal) {
            let staging = stagingDirectory
            let fm = fileManager
            lock.unlock()
            removeLateCallbackArtifacts(reportedURL: reportedURL, staging: staging, fileManager: fm)
            return true
        }
        if emittedTerminal {
            lock.unlock()
            return true
        }
        return false
    }

    /// 취소: 세션 무효화, 로컬 큐 취소, staging 즉시 제거, `.cancelled` 이벤트.
    /// provider-side cancellation은 주장하지 않는다.
    /// `.succeeded` emit 후(성공 종단 직후, reducer가 아직 placement를 시작하기 전) 취소가
    /// 와도 staging은 제거한다. 그렇지 않으면 finish 호출자가 사라져 staging이 영구 잔류한다.
    /// 이때 `.cancelled`는 이미 종단이 나갔으므로 emit하지 않는다.
    func cancel(fileManager _: FileManagerClient) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled, !(isFinished && !emittedTerminal) else { return }
        isCancelled = true
        queue.cancelAllOperations()
        if !emittedTerminal {
            emitTerminalLocked(.cancelled(sessionID))
        }
        removeStagingLocked()
    }

    /// 정상 종료: 멱등. staging을 정확히 한 번 제거한다. `.succeeded` 종단 후 호출돼도
    /// (이미 `isFinished`로 표시됐어도) staging을 정리한다.
    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }
        removeStagingLocked()
        if isFinished { return }
        isFinished = true
        queue.cancelAllOperations()
    }

    /// staging 디렉터리를 정확히 한 번 제거한다 (멱등). caller는 lock을 보유해야 한다.
    private func removeStagingLocked() {
        guard !removedStaging else { return }
        removedStaging = true
        try? fileManager.removeItem(URL(fileURLWithPath: stagingDirectory))
    }

    // MARK: - Event emission (caller must hold lock)

    private static let logger = Logger(subsystem: "fm.voyager.external-drop", category: "acquisition")

    private func emitLocked(_ event: ExternalDropAcquisitionEvent) {
        bufferedEvents.append(event)
        continuation?.yield(event)
    }

    private func emitTerminalLocked(_ event: ExternalDropAcquisitionEvent) {
        guard !emittedTerminal else { return }
        emittedTerminal = true
        isFinished = true
        // 실패/취소 종단에서도 staging을 반드시 정리한다. 성공(.succeeded)은 placement가
        // staged 파일을 destination으로 복사한 뒤 `finish()`가 제거하므로 여기서 지우지 않는다.
        switch event {
        case .succeeded:
            break
        case .failed, .cancelled:
            removeStagingLocked()
        case .received:
            break
        }
        stagingObserver?.cancel()
        stagingObserver = nil
        stagingScanWorkItem?.cancel()
        stagingScanWorkItem = nil
        indeterminateQuiescenceWorkItem?.cancel()
        indeterminateQuiescenceWorkItem = nil
        callbackErrorTimeouts.values.forEach { $0.cancel() }
        callbackErrorTimeouts.removeAll()
        pendingCancelledCallbacks.removeAll()
        queue.cancelAllOperations()
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

    private func isInsideStaging(_ url: URL) -> Bool {
        let stagingComponents = URL(fileURLWithPath: stagingDirectory)
            .standardizedFileURL
            .pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
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

    /// 종단(성공) 판정. 결정적 기여(파일명 있는 수신기 + data flavor)가 모두 수신됐고
    /// 모든 미정 수신기가 source-owned 파일을 실제로 기여했을 때 성공이다.
    /// caller는 lock을 보유해야 한다.
    private func sessionIsCompleteLocked() -> Bool {
        receivedDeterminateCount >= expectedCardinality
            && completedIndeterminateReceivers.isSuperset(of: indeterminateReceivers)
    }
}

extension ExternalDropAcquisitionSession {
    /// 큐에서 실행되는 지연 load가 실패했을 때 세션을 타입화 실패로 종단 처리한다.
    func fail(reason: ExternalDropRejectReason) {
        lock.lock()
        defer { lock.unlock() }
        guard !emittedTerminal else { return }
        emitTerminalLocked(.failed(sessionID, reason))
    }

    private static let indeterminateNameMarker = "NSFilePromiseUnknown"
}
