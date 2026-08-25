import Foundation
import os
import VoyagerShared

/// claim 시점의 inode 신원. 성공 배리어에서 현재 경로를 다시 lstat해
/// 같은-UID provider의 unlink/rename/symlink 치환을 탐지한다(코멘트 #3835329095).
/// `lstat` 기반이라 FIFO O_RDONLY open처럼 세션 lock을 잡고 블로킹하지 않는다(P1-C).
/// regular/directory 외 타입(symlink·FIFO·소켓 등)은 신원으로 고정하지 않고 fail-closed한다.
struct ClaimedFileIdentity {
    let deviceID: UInt64
    let inode: UInt64
    let fileType: mode_t

    init?(path: String) {
        var status = stat()
        guard Darwin.lstat(path, &status) == 0 else { return nil }
        self.init(status: status)
    }

    /// 이미 열린(또는 생성 직후 fstat한) descriptor의 신원을 기록한다. 파일 생성과 동시에
    /// 신원을 고정해, 보관 사본이 관찰 가능해진 뒤 별도 lstat까지의 틈에서 치환이 기록되는
    /// 경쟁을 없앤다(코멘트 #3835329095).
    init?(descriptor: Int32) {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else { return nil }
        self.init(status: status)
    }

    /// 걷기 시점에 확보한 stat에서 신원을 만든다. 경로 재판독 없이 스냅숏 순간의 inode를
    /// 고정하므로, 이후 가시 경로 치환이 신원 기록에 기여할 수 없다.
    init?(status: stat) {
        let type = status.st_mode & S_IFMT
        guard type == S_IFREG || type == S_IFDIR else { return nil }
        deviceID = UInt64(status.st_dev)
        inode = UInt64(status.st_ino)
        fileType = type
    }

    func matchesCurrentPath(_ path: String) -> Bool {
        var status = stat()
        guard Darwin.lstat(path, &status) == 0 else { return false }
        return matches(status)
    }

    func matches(_ status: stat) -> Bool {
        UInt64(status.st_dev) == deviceID
            && UInt64(status.st_ino) == inode
            && status.st_mode & S_IFMT == fileType
    }
}

/// 세션 staging 디렉터리의 수명주기 소유자. 생성 경로와 제거 상태를 단일 소유해
/// "정확히 한 번 제거"가 상태 전이로 보장된다.
final class StagingDirectory {
    let path: String
    private let fileManager: FileManagerClient
    /// callback 시점에 확정한 파일의 보관 디렉터리. staging root는 receive destination으로
    /// provider에 전달되므로, provider가 root를 계속 쓸 수 있는 동안 claimed 파일을
    /// symlink로 교체하지 못하게 root 밖에 둔다(코멘트 #3830970683).
    private let ownedPath: URL
    private let identityLock = NSLock()
    /// \uc774\uc804 \ub514\ub809\ud1a0\ub9ac\uc758 mtime/atime\uc744 \ub77c\ubca8\ubcc4\ub85c \ubcf4\uad00\ud574
    /// placement \uc2dc \ubcf5\uc6d0\ud55c\ub2e4(#3841341519).
    private var preservedDirectoryTimes: [String: [timeval]] = [:]
    /// 성공 배리어용 가시 표면 신원(staged/legacy 등 provider가 경로를 아는 노드).
    private var claimedIdentities: [String: ClaimedFileIdentity] = [:]
    /// 격리 콘텐츠 레지스트리. placement는 여기 기록된 무작위 이름 노드를 신원 검증해 열고,
    /// fd를 저장하지 않으므로 동시 fd는 순회 깊이 수준이다(코멘트 #3835329095).
    private let pinnedContent: PinnedContentStore
    /// accept 시점에 동기 고정한 root descriptor(O(1) per URL). 트리 격리와 하위 열거는
    /// 세션 큐 첫 작업에서 이 fd 기준으로 수행한다(코멘트 #3835329097).
    private var pinnedImmediateRootDescriptors: [String: Int32] = [:]
    /// 보관 candidate 경로(canonical) → 격리 레지스트리 루트 label 매핑. 격리는 원본
    /// canonical 레이블로 수행되고 placement 조회는 candidate 경로로 들어온다.
    private var placementAliases: [String: String] = [:]
    private(set) var isRemoved = false
    /// 파일시스템 관찰 소스. 외부에서 attach/teardown을 관리한다.
    var observer: DispatchSourceFileSystemObject?

    init(path: String, fileManager: FileManagerClient) {
        self.path = path
        self.fileManager = fileManager
        let rootName = URL(fileURLWithPath: path).lastPathComponent
        ownedPath = URL(fileURLWithPath: path, isDirectory: true)
            .deletingLastPathComponent()
            .appendingPathComponent(".voyager-claimed-\(rootName)", isDirectory: true)
        try? fileManager.createDirectory(ownedPath, true, nil)
        pinnedContent = PinnedContentStore(directoryPath: ownedPath.path, fileManager: fileManager)
    }

    var claimedPath: String {
        ownedPath.path
    }

    /// promise callback 파일을 보관 디렉터리로 옮기고 스트리밍 격리한다. provider descriptor를
    /// move 전에 열어 고정하므로 예측 가능한 candidate 경로명을 다시 열지 않는다
    /// (코멘트 #3835329095).
    func claim(_ sourceURL: URL) -> URL? {
        // 보관 디렉터리 부모를 fd로 고정한다. 이후 모든 candidate 조작은 이 fd 기준
        // openat/unlinkat/renameat으로 수행해 경로 재해석 창을 남기지 않는다(#3845390794).
        let parentDescriptor = Darwin.open(
            ownedPath.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC,
        )
        guard parentDescriptor >= 0 else { return nil }
        defer { Darwin.close(parentDescriptor) }

        let sourceName = sourceURL.lastPathComponent
        let baseName = (sourceName as NSString).deletingPathExtension
        let pathExtension = (sourceName as NSString).pathExtension

        // 이름을 O_CREAT|O_EXCL로 배타 선점한다. 공격자가 예측한 candidate 이름을
        // symlink로 대차할 수 없고, renameat이 그 이름 위로 원자적으로 덮어쓴다.
        var candidateName: String?
        var suffix = 0
        while candidateName == nil, suffix < 64 {
            let trial = suffix == 0 ? sourceName : (
                pathExtension.isEmpty
                    ? "\(baseName) \(suffix + 1)"
                    : "\(baseName) \(suffix + 1).\(pathExtension)"
            )
            let probe = Darwin.openat(
                parentDescriptor,
                trial,
                O_CREAT | O_EXCL | O_RDONLY | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600),
            )
            if probe >= 0 {
                Darwin.close(probe)
                candidateName = trial
            } else if errno != EEXIST {
                return nil
            }
            suffix += 1
        }
        guard let reservedName = candidateName else { return nil }
        let candidate = ownedPath.appendingPathComponent(reservedName)

        func abandonReservation() {
            Darwin.unlinkat(parentDescriptor, reservedName, 0)
        }

        let sourceDescriptor = Darwin.open(
            sourceURL.path,
            O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC,
        )
        guard sourceDescriptor >= 0 else {
            abandonReservation()
            return nil
        }
        defer { Darwin.close(sourceDescriptor) }

        let sourceParentDescriptor = Darwin.open(
            sourceURL.deletingLastPathComponent().path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC,
        )
        guard sourceParentDescriptor >= 0 else {
            abandonReservation()
            return nil
        }
        defer { Darwin.close(sourceParentDescriptor) }

        do {
            // 배타 선점된 이름 위로 원자 교체한다. moveItem의 경로 추적과 달리 중간에
            // 설치된 symlink를 따라가 staging 밖으로 나갈 수 없다.
            guard Darwin.renameat(
                sourceParentDescriptor,
                sourceName,
                parentDescriptor,
                reservedName,
            ) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let claimedCanonical = canonicalClaimPath(candidate.path)
            // 배리어는 candidate 가시 표면의 신원을 검증한다(격리 snapshot inode가 아님).
            // NOFOLLOW 재개방이므로 치환된 symlink를 따라가지 않는다.
            let surfaceDescriptor = Darwin.openat(
                parentDescriptor,
                reservedName,
                O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC,
            )
            guard surfaceDescriptor >= 0 else {
                throw POSIXError(.EIO)
            }
            defer { Darwin.close(surfaceDescriptor) }
            guard let visibleIdentity = ClaimedFileIdentity(descriptor: surfaceDescriptor) else {
                throw CocoaError(.fileReadUnknown)
            }
            guard try isolateTree(
                from: sourceDescriptor,
                rootLabel: claimedCanonical,
            ) != nil else { throw CocoaError(.fileReadUnknown) }
            identityLock.lock()
            claimedIdentities[claimedCanonical] = visibleIdentity
            identityLock.unlock()
            return candidate
        } catch {
            abandonReservation()
            return nil
        }
    }

    /// accept 경계(MainActor)에서는 각 즉시 URL의 root descriptor 고정과 타입 검증만 수행한다
    /// (O(1) per URL, bounded — 코멘트 #3835329097). 트리 격리와 하위 열거는 모두 세션 큐의
    /// completeImmediateTreePinning()에서 수행된다. 하나라도 실패하면 all-or-nothing으로
    /// false를 반환하고 이번 배치에서 연 모든 fd를 닫는다.
    func pinImmediateRoots(urls: [String]) -> Bool {
        identityLock.lock()
        defer { identityLock.unlock() }
        var builtRoots: [String: Int32] = [:]
        for path in urls {
            let canonical = canonicalClaimPath(path)
            if builtRoots[canonical] != nil || pinnedImmediateRootDescriptors[canonical] != nil { continue }
            let rootDescriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard rootDescriptor >= 0 else {
                closeDescriptors(builtRoots.values)
                return false
            }
            // pin 시점 타입 검증: FIFO/symlink 등 regular·directory 외 노드는 여기서 fail-closed.
            guard ClaimedFileIdentity(descriptor: rootDescriptor) != nil else {
                Darwin.close(rootDescriptor)
                closeDescriptors(builtRoots.values)
                return false
            }
            builtRoots[canonical] = rootDescriptor
        }
        for (canonicalPath, descriptor) in builtRoots {
            pinnedImmediateRootDescriptors[canonicalPath] = descriptor
        }
        return true
    }

    /// 세션 큐에서 보류된 root descriptor를 스트리밍 격리해 사유 콘텐츠 레지스트리를 완성한다.
    /// 신뢰 경계는 이 함수의 완료 시점이다(코멘트 #3835329095, #3835329097). 순회는 부모 체인만
    /// fd로 보유하고(openat), 각 노드는 즉시 무작위 이름 snapshot으로 relink 후 닫히므로 동시
    /// fd는 깊이 수준이다. 하나라도 실패하면 all-or-nothing으로 false를 반환하고 이번 배치
    /// 결과를 모두 폐기한다.
    func completeImmediateTreePinning() -> Bool {
        identityLock.lock()
        let pending = pinnedImmediateRootDescriptors
        pinnedImmediateRootDescriptors.removeAll()
        // 재귀 격리 동안에는 identityLock을 점유하지 않는다(코멘트 #3837839018).
        // MainActor의 cancel/remove()가 대형 트리 복사 완료까지 블로킹되지 않게 한다.
        // 콘텐츠 레지스트리는 PinnedContentStore 내부 lock으로 보호된다.
        identityLock.unlock()
        // 처리 완료한 root descriptor는 catch에서 다시 닫지 않는다(코멘트 #3837839021).
        // close 후 fd 번호가 재사용되면 무관한 descriptor를 닫을 수 있다.
        var remaining = pending
        do {
            for (canonical, rootDescriptor) in pending {
                guard let rootIdentity = try isolateTree(
                    from: rootDescriptor,
                    rootLabel: canonical,
                ) else { throw CocoaError(.fileReadUnknown) }
                _ = rootIdentity
                Darwin.close(rootDescriptor)
                remaining.removeValue(forKey: canonical)
            }
            return true
        } catch {
            pinnedContent.removeAll()
            closeDescriptors(remaining.values)
            return false
        }
    }

    /// source fd 루트 트리를 레지스트리로 스트리밍 격리한다. 재귀 중 보유 fd는 조상 체인과
    /// 현재 노드뿐이다. 반환값은 루트 신원(호출자 참조용), 실패 시 nil.
    private func isolateTree(from sourceDescriptor: Int32, rootLabel: String) throws -> ClaimedFileIdentity? {
        try isolateNode(sourceDescriptor: sourceDescriptor, label: rootLabel)
    }

    private func isolateNode(sourceDescriptor: Int32, label: String) throws -> ClaimedFileIdentity {
        var status = stat()
        guard Darwin.fstat(sourceDescriptor, &status) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let type = status.st_mode & S_IFMT
        switch type {
        case S_IFREG:
            return try pinnedContent.snapshotFile(from: sourceDescriptor, label: label)
        case S_IFDIR:
            _ = try pinnedContent.makeDirectory(label: label, mode: status.st_mode & 0o777)
            // 원본 디렉토리의 mtime/atime을 보존해 placement 시 복원한다(#3841341519).
            identityLock.lock()
            preservedDirectoryTimes[label] = [
                timeval(tv_sec: status.st_atimespec.tv_sec, tv_usec: Int32(status.st_atimespec.tv_nsec / 1000)),
                timeval(tv_sec: status.st_mtimespec.tv_sec, tv_usec: Int32(status.st_mtimespec.tv_nsec / 1000)),
            ]
            identityLock.unlock()
            // 열거 실패(fd 한도 등)를 빈 디렉터리로 치환하면 자식이 누락된 채 스냅숏이
            // 성공한다. all-or-nothing 계약에 따라 fail-closed로 예외화한다(코멘트 #3837839019).
            guard let names = Self.directoryEntryNames(fd: sourceDescriptor) else {
                throw CocoaError(.fileReadUnknown)
            }
            // 열거·하위 격리 전후로 디렉터리 상태(size+mtime)를 대조해 스냅숏 도중
            // 추가·삭제로 인한 부분 트리 성공을 막는다(코멘트 #3840460034). 자체 격리는
            // source 디렉터리를 건드리지 않으므로 변화는 외부 변경뿐이다.
            let beforeSize = status.st_size
            let beforeSec = status.st_mtimespec.tv_sec
            let beforeNsec = status.st_mtimespec.tv_nsec
            for name in names {
                let childDescriptor = Darwin.openat(
                    sourceDescriptor,
                    name,
                    O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC,
                )
                guard childDescriptor >= 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                defer { Darwin.close(childDescriptor) }
                _ = try isolateNode(sourceDescriptor: childDescriptor, label: label + "/" + name)
            }
            var afterDirectory = stat()
            guard Darwin.fstat(sourceDescriptor, &afterDirectory) == 0,
                  afterDirectory.st_size == beforeSize,
                  afterDirectory.st_mtimespec.tv_sec == beforeSec,
                  afterDirectory.st_mtimespec.tv_nsec == beforeNsec
            else {
                throw CocoaError(.fileReadUnknown)
            }
            guard let identity = ClaimedFileIdentity(status: status) else {
                throw CocoaError(.fileReadUnknown)
            }
            return identity
        default:
            throw CocoaError(.fileReadUnsupportedScheme)
        }
    }

    /// 스냅숏 복사가 끝난 뒤 남은 보류 root descriptor를 닫는다. 레지스트리는 placement까지
    /// 유지된다.
    func releasePinnedImmediateRoots() {
        identityLock.lock()
        closeDescriptors(pinnedImmediateRootDescriptors.values)
        pinnedImmediateRootDescriptors.removeAll()
        identityLock.unlock()
    }

    /// enqueue 시점에 고정한 트리에서 보관 사본을 만든다. 실행 시점에는 어떤 소스 경로도
    /// 다시 열지 않고, 레지스트리의 검증된 descriptor만 사용한다(코멘트 #3835329095).
    func copyPinnedImmediate(_ sourceURL: URL) -> URL? {
        let canonical = canonicalClaimPath(sourceURL.path)
        identityLock.lock()
        let isolated = pinnedContent.contains(canonical)
        identityLock.unlock()
        guard isolated else { return nil }
        let candidate = uniqueOwnedCandidate(for: sourceURL)
        do {
            try Self.copyFromStore(
                pinnedContent,
                rootLabel: canonical,
                destination: candidate,
            )
            identityLock.lock()
            placementAliases[canonicalClaimPath(candidate.path)] = canonical
            identityLock.unlock()
            return candidate
        } catch {
            try? fileManager.removeItem(candidate)
            return nil
        }
    }

    /// claim 시점에 캡처한 inode 신원과 현재 경로를 비교한다. 성공 배리어가 false를 받으면
    /// 세션은 `.fileAbsent` 실패로 강등돼 provider 치환 경로를 넘기지 않는다(코멘트 #3835329095).
    func verifyClaimedIdentities() -> Bool {
        identityLock.lock()
        let identities = claimedIdentities
        identityLock.unlock()
        return identities.allSatisfy { path, identity in
            identity.matchesCurrentPath(path)
        }
    }

    /// provider가 경로를 아는 staging 산출물(data flavor 물리화·legacy staged)을 등록한다.
    /// admission 시점에 포획한 기대 신원과 실제 open 결과를 대조해 lstat→open TOCTOU를
    /// fail-closed로 닫고, detached snapshot을 레지스트리에 relink한다(코멘트 #3835329095).
    func stageReceivedFile(
        _ url: URL,
        expected: ClaimedFileIdentity?,
        shouldAbort: (() -> Bool)? = nil,
    ) -> Bool {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else { return false }
        if let expected, !expected.matches(status) {
            return false
        }
        guard let openedIdentity = ClaimedFileIdentity(status: status) else { return false }
        do {
            let label = canonicalClaimPath(url.path)
            if status.st_mode & S_IFMT == S_IFDIR {
                // 레거시 provider가 반환한 폴더·package도 modern claim과 같은 재귀 격리로
                // 스냅숏한다. regular-file 전용 snapshotFile은 fcopyfile 실패로 유효한
                // drop을 .fileAbsent로 누락했다(#3842246322).
                _ = try isolateTree(from: descriptor, rootLabel: label)
            } else {
                _ = try pinnedContent.snapshotFile(
                    from: descriptor,
                    label: label,
                    shouldAbort: shouldAbort,
                )
            }
        } catch {
            return false
        }
        identityLock.lock()
        claimedIdentities[canonicalClaimPath(url.path)] = openedIdentity
        identityLock.unlock()
        return true
    }

    /// admission 시점(lstat) 신원 포횅. 세션 큐 격리 전 교체를 판정하는 기준이 된다.
    func capturedIdentity(_ url: URL) -> ClaimedFileIdentity? {
        ClaimedFileIdentity(path: url.path)
    }

    /// placement 요청 경로가 모두 격리 레지스트리에 있는지 확인한다. 누락 시 fail-closed.
    func preparePlacementSources(paths: [String]) -> Bool {
        identityLock.lock()
        defer { identityLock.unlock() }
        return paths.allSatisfy { resolvedLabel(for: $0) != nil }
    }

    /// candidate 경로면 격리 루트 label로 치환하고, 아니면 canonical을 label로 쓴다.
    private func resolvedLabel(for path: String) -> String? {
        let canonical = canonicalClaimPath(path)
        if let alias = placementAliases[canonical] {
            return pinnedContent.contains(alias) ? alias : nil
        }
        return pinnedContent.contains(canonical) ? canonical : nil
    }

    /// 복사에 사용한 격리 루트 label을 반환한다. immediate URL은 candidate 경로라
    /// 시각 기록 조회가 원본 label을 필요로 한다(#3842246337).
    @discardableResult
    func copyPlacementSource(sourcePath: String, destinationPath: String) throws -> String {
        identityLock.lock()
        let rootLabel = resolvedLabel(for: sourcePath)
        identityLock.unlock()
        guard let rootLabel else { throw CocoaError(.fileNoSuchFile) }
        try Self.copyFromStore(
            pinnedContent,
            rootLabel: rootLabel,
            destination: URL(fileURLWithPath: destinationPath),
        )
        return rootLabel
    }

    private static func copyFromStore(
        _ store: PinnedContentStore,
        rootLabel: String,
        destination: URL,
    ) throws {
        try StablePlacementCopier.copySubtree(
            rootPath: rootLabel,
            destination: destination,
            openVerifiedNode: { label in
                let opened = try store.openVerified(label)
                return (opened.fd, opened.isDirectory)
            },
            closeVerifiedNode: { Darwin.close($0) },
            childLabels: { store.childLabels(of: $0) },
            // placement가 읽은 바이트와 스냅숏 digest를 대조해 검증-복사 사이
            // 재기록 TOCTOU를 fail-closed한다(코멘트 #3840108372).
            verifyCopiedFile: { label, copiedDestination in
                guard let entry = store.entry(at: label), !entry.isDirectory else { return }
                let descriptor = Darwin.open(
                    copiedDestination.path,
                    O_RDONLY | O_NOFOLLOW | O_CLOEXEC,
                )
                guard descriptor >= 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                defer { Darwin.close(descriptor) }
                guard let actual = PinnedContentStore.sha256(ofDescriptor: descriptor),
                      actual == entry.contentDigest
                else {
                    throw CocoaError(.fileReadUnknown)
                }
            },
        )
    }

    private func closeDescriptors(_ descriptors: some Sequence<Int32>) {
        descriptors.forEach { Darwin.close($0) }
    }

    /// placement 완료 후 원본 디렉터리 시각을 복원한다(#3841341519). 기록이 없으면
    /// 아무 것도 하지 않는다. 격리 때 기록된 중첩 디렉터리 레이블도 목적지 하위
    /// 경로에 복원해 폴더 트리의 mtime/atime 손상을 막는다(#3841991804).
    func restoreOriginalDirectoryTimes(claimedPath: String, destinationPath: String) {
        identityLock.lock()
        let timesByLabel = preservedDirectoryTimes
        identityLock.unlock()
        guard !timesByLabel.isEmpty else { return }
        let rootKey = canonicalClaimPath(claimedPath)
        if let times = timesByLabel[rootKey] {
            utimes(destinationPath, times)
        }
        // 레이블은 캐노니컬 소스 경로이므로 루트 접두를 벗긴 상대 경로가 목적지 트리의
        // 동일 위치에 대응한다. 복사가 실패해 하위 경로가 없으면 utimes가 조용히
        // 실패하며 세션 종단에는 영향을 주지 않는다.
        let rootPrefix = rootKey + "/"
        for (label, times) in timesByLabel where label.hasPrefix(rootPrefix) {
            utimes(destinationPath + "/" + label.dropFirst(rootPrefix.count), times)
        }
    }

    /// claim 신원 키를 canonical real path로 통일한다. `/var`→`/private/var`처럼 symlink가
    /// 풀린 경로가 어느 경로로 기록됐든 placement 조회 키와 일치하게 한다.
    private func canonicalClaimPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// 보관 디렉터리 안에서 소스 파일명과 충돌하지 않는 고유 목적지 경로를 만든다.
    private func uniqueOwnedCandidate(for sourceURL: URL) -> URL {
        var candidate = ownedPath.appendingPathComponent(sourceURL.lastPathComponent)
        var suffix = 2
        while fileManager.fileExists(candidate.path) {
            let name = (sourceURL.lastPathComponent as NSString).deletingPathExtension
            let ext = (sourceURL.lastPathComponent as NSString).pathExtension
            let suffixedName = ext.isEmpty ? "\(name) \(suffix)" : "\(name) \(suffix).\(ext)"
            candidate = ownedPath.appendingPathComponent(suffixedName)
            suffix += 1
        }
        return candidate
    }

    /// 부모 fd 기준 readdir로 직계 자식 이름을 읽는다. 경로 재해석이 없다.
    /// DIR 스트림은 호출마다 dup(fd)에 가져지므로 잠금 없이 호출해도 안전하다(코멘트 #3837839018).
    private static func directoryEntryNames(fd: Int32) -> [String]? {
        guard let stream = fdopendir(dup(fd)) else { return nil }
        defer { closedir(stream) }
        var names: [String] = []
        while true {
            // readdir는 EOF와 오류 모두 nil을 반환한다. 호출마다 errno를 초기화해
            // 루프 종료 시의 errno만 오류 신호로 해석한다(코멘트 #3837880886).
            errno = 0
            guard let entry = readdir(stream) else { break }
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw -> String in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                    return ""
                }
                return String(cString: base)
            }
            if name != ".", name != ".." {
                names.append(name)
            }
        }
        // 부분 열거(중간 I/O 오류)를 성공 배열로 반환하지 않는다(코멘트 #3837880886).
        if errno != 0 { return nil }
        return names
    }

    /// 이미 제거된 상태가 아니어도 파일시스템 상의 staging/보관 디렉터리를 정리한다.
    /// 늦은 콜백 재정리 경로에서 사용하며 상태 플래그는 건드리지 않는다.
    func removeIfPresent() {
        identityLock.lock()
        // 늦은 콜백 경로도 항목별 동기 삭제 없이 레지스트리만 비운다(#3840293889).
        pinnedContent.clearRegistry()
        closeDescriptors(pinnedImmediateRootDescriptors.values)
        pinnedImmediateRootDescriptors.removeAll()
        placementAliases.removeAll()
        claimedIdentities.removeAll()
        identityLock.unlock()
        removeTreePayloadOffMainActor()
    }

    func attachObserver(_ observer: DispatchSourceFileSystemObject) {
        self.observer = observer
        observer.resume()
    }

    func detachObserver() {
        observer?.cancel()
        observer = nil
    }

    func remove() {
        identityLock.lock()
        guard !isRemoved else {
            identityLock.unlock()
            return
        }
        isRemoved = true
        closeDescriptors(pinnedImmediateRootDescriptors.values)
        pinnedImmediateRootDescriptors.removeAll()
        // 레지스트리만 비우고 실제 파일은 통째 rename+백그라운드 삭제로 정리한다.
        pinnedContent.clearRegistry()
        claimedIdentities.removeAll()
        identityLock.unlock()
        removeTreePayloadOffMainActor()
    }

    /// staging/보관 디렉터리 정리는 두 단계로 나눈다(코멘트 #3837956596). MainActor에서는
    /// O(1) rename으로 경로를 임시 이름으로 치워 이후 같은 경로 재생성(늦은 콜백 등)과
    /// 경합하지 않게 하고, 대형 트리 재귀 삭제는 백그라운드에서 수행한다. registry
    /// 전이는 이미 identityLock으로 완료된 뒤다.
    private func removeTreePayloadOffMainActor() {
        let suffix = UUID().uuidString
        var pending: [URL] = []
        for url in [URL(fileURLWithPath: path), ownedPath] {
            let trash = url.deletingLastPathComponent()
                .appendingPathComponent(".voyager-staging-trash-\(suffix)-\(url.lastPathComponent)")
            if (try? fileManager.moveItem(url, trash)) != nil {
                pending.append(trash)
            }
        }
        guard !pending.isEmpty else { return }
        let manager = fileManager
        Task.detached {
            for trashURL in pending {
                try? manager.removeItem(trashURL)
            }
        }
    }
}
