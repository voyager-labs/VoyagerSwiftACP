import Foundation
import VoyagerShared

/// 격리된 콘텐츠 레지스트리(코멘트 #3835329095, #3835329097).
///
/// 각 노드는 보관 디렉터리 안 무작위 이름(mkstemp/mkdtemp)의 사유 파일/디렉터리로 relink되고,
/// 열림마다 기록된 inode 신원(dev/ino/type)과 대조 검증한다(O_NOFOLLOW). fd를 저장하지 않으므로
/// 노드 수와 무관하게 동시 fd는 순회 깊이 수준으로 제한된다(RLIMIT_NOFILE 안전, 넓은 트리 지원).
///
/// 콘텐츠 안정성 프로토콜: producer가 retained writable fd로 같은 inode에 임자 내부 재기록하는
/// 경우를 대비해, 복사 전후 size+mtime을 대조하고 불안정하면 1회 재시도 후 fail-closed한다.
final class PinnedContentStore {
    struct Entry {
        let name: String
        let identity: ClaimedFileIdentity
        let isDirectory: Bool
        let mode: mode_t
    }

    private(set) var entries: [String: Entry] = [:]
    private let directoryPath: String
    private let fileManager: FileManagerClient
    /// entries 접근만 직렬화하고 파일 I/O 중에는 보유하지 않는다(코멘트 #3837839018).
    private let lock = NSLock()

    init(directoryPath: String, fileManager: FileManagerClient) {
        self.directoryPath = directoryPath
        self.fileManager = fileManager
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries.isEmpty
    }

    func contains(_ label: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[label] != nil
    }

    func entry(at label: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[label]
    }

    /// label의 직계 자식 label들을 반환한다(트리 구조 복원용).
    func childLabels(of parentLabel: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let prefix = parentLabel + "/"
        return entries.keys.filter { key in
            guard key.hasPrefix(prefix), key != parentLabel else { return false }
            return !key.dropFirst(prefix.count).contains("/")
        }
    }

    /// source fd의 현재 콘텐츠를 사유 파일 snapshot으로 복사해 relink한다.
    /// 복사 전후 size+mtime 대조로 임자 내부 재기록 찢어짐을 탐지하고, 불안정 시 1회
    /// 재시도 후 fail-closed 예외를 던진다(코멘트 #3835329095).
    func snapshotFile(from sourceDescriptor: Int32, label: String) throws -> ClaimedFileIdentity {
        var before = stat()
        guard Darwin.fstat(sourceDescriptor, &before) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        for _ in 0 ..< 2 {
            let snapshot = try createSnapshotFile(from: sourceDescriptor, mode: before.st_mode & 0o777)
            Darwin.close(snapshot.descriptor)
            var after = stat()
            guard Darwin.fstat(sourceDescriptor, &after) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if Self.isStable(before, after) {
                lock.lock()
                entries[label] = Entry(
                    name: snapshot.name,
                    identity: snapshot.identity,
                    isDirectory: false,
                    mode: before.st_mode & 0o777,
                )
                lock.unlock()
                return snapshot.identity
            }
            try? fileManager.removeItem(
                URL(fileURLWithPath: directoryPath).appendingPathComponent(snapshot.name),
            )
            before = after
        }
        // 두 차례 복사에서도 size+mtime이 고정되지 않았다. 찢어진 바이트를 placement에
        // 넘기지 않고 실패로 닫는다.
        throw CocoaError(.fileReadUnknown)
    }

    /// 사유 디렉터리 노드를 만들고 relink한다(콘텐츠 없이 구조만).
    func makeDirectory(label: String, mode: mode_t) throws -> ClaimedFileIdentity {
        var template = Array(
            URL(fileURLWithPath: directoryPath).appendingPathComponent(".snapd-XXXXXX").path.utf8CString,
        )
        let created: UnsafeMutablePointer<CChar>? = template.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return nil }
            return Darwin.mkdtemp(baseAddress)
        }
        guard created != nil else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        // mkstemp/mkdtemp는 템플릿(절대 경로)을 in-place 치환하므로 해석 결과는 전체 경로다.
        // 레지스트리에는 디렉터리 기준 상대 이름만 저장한다.
        let name = try requiredSnapshotName(Self.decodingNullTerminated(template))
            .split(separator: "/").last.map(String.init) ?? ""
        let directoryURL = URL(fileURLWithPath: directoryPath).appendingPathComponent(name)
        guard Darwin.chmod(directoryURL.path, mode) == 0 else {
            try? fileManager.removeItem(directoryURL)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let descriptor = Darwin.open(
            directoryURL.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC,
        )
        guard descriptor >= 0 else {
            try? fileManager.removeItem(directoryURL)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              let identity = ClaimedFileIdentity(status: status)
        else {
            try? fileManager.removeItem(directoryURL)
            throw CocoaError(.fileReadUnknown)
        }
        lock.lock()
        entries[label] = Entry(name: name, identity: identity, isDirectory: true, mode: mode)
        lock.unlock()
        return identity
    }

    /// 기록된 신원과 대조해 검증된 descriptor를 연다(O_NOFOLLOW). caller가 close한다.
    /// 이름 교체·symlink 치환은 신원 불일치로 fail-closed된다.
    func openVerified(_ label: String) throws -> (fd: Int32, isDirectory: Bool) {
        lock.lock()
        let entry = entries[label]
        lock.unlock()
        guard let entry else {
            throw CocoaError(.fileNoSuchFile)
        }
        let nodeURL = URL(fileURLWithPath: directoryPath).appendingPathComponent(entry.name)
        var flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        if entry.isDirectory {
            flags |= O_DIRECTORY
        }
        let descriptor = Darwin.open(nodeURL.path, flags)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
        }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              entry.identity.matches(status)
        else {
            Darwin.close(descriptor)
            throw CocoaError(.fileReadUnknown)
        }
        return (descriptor, entry.isDirectory)
    }

    func removeAll() {
        // 레지스트리를 먼저 비우고 파일 삭제는 lock 밖에서 수행한다(코멘트 #3837839018).
        lock.lock()
        let removed = Array(entries.values)
        entries.removeAll()
        lock.unlock()
        for entry in removed {
            try? fileManager.removeItem(
                URL(fileURLWithPath: directoryPath).appendingPathComponent(entry.name),
            )
        }
    }

    /// mkstemp로 만든 사유 파일 snapshot의 소유 정보.
    private struct SnapshotFile {
        let descriptor: Int32
        let name: String
        let identity: ClaimedFileIdentity
    }

    private func createSnapshotFile(
        from sourceDescriptor: Int32,
        mode: mode_t,
    ) throws -> SnapshotFile {
        var template = Array(
            URL(fileURLWithPath: directoryPath).appendingPathComponent(".snap-XXXXXX").path.utf8CString,
        )
        let descriptor: Int32 = template.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return -1 }
            return Darwin.mkstemp(baseAddress)
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        do {
            guard Darwin.fchmod(descriptor, mode) == 0,
                  Darwin.lseek(sourceDescriptor, 0, SEEK_SET) >= 0
            else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let state = copyfile_state_alloc()
            defer { copyfile_state_free(state) }
            guard fcopyfile(sourceDescriptor, descriptor, state, copyfile_flags_t(COPYFILE_ALL)) == 0,
                  Darwin.lseek(descriptor, 0, SEEK_SET) >= 0
            else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            Darwin.close(descriptor)
            let name = Self.decodingNullTerminated(template)
            if let name {
                try? fileManager.removeItem(URL(fileURLWithPath: directoryPath).appendingPathComponent(name))
            }
            throw error
        }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              let identity = ClaimedFileIdentity(status: status)
        else {
            Darwin.close(descriptor)
            throw CocoaError(.fileReadUnknown)
        }
        // 템플릿이 절대 경로이므로 해석 결과에서 마지막 구성요소(이름)만 취한다.
        let name = try requiredSnapshotName(Self.decodingNullTerminated(template))
            .split(separator: "/").last.map(String.init) ?? ""
        return SnapshotFile(descriptor: descriptor, name: name, identity: identity)
    }

    private static func isStable(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
    }

    private static func decodingNullTerminated(_ bytes: [CChar]) -> String? {
        bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return nil }
            let utf8Address = UnsafeRawPointer(baseAddress).assumingMemoryBound(to: UInt8.self)
            return String(decodingCString: utf8Address, as: UTF8.self)
        }
    }
}

/// mkstemp 템플릿에서 해석한 이름이 누락되면 fail-closed 예외로 승격한다.
private func requiredSnapshotName(_ value: String?) throws -> String {
    guard let value else { throw CocoaError(.fileReadUnknown) }
    return value
}
