import CryptoKit
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
        /// 스냅숏 완료 시점의 내용 지문. 같은 inode 재기록을 placement open 시점에
        /// 대조한다(코멘트 #3837956594).
        let contentSize: Int
        let mtimeSeconds: Int
        let mtimeNanoseconds: Int
        /// 스냅숏 바이트의 SHA-256. size/mtime은 provider가 복원할 수 있으므로 내용
        /// 자체를 고정한다(코멘트 #3838035179). 디렉터리는 빈 값으로 건너뛴다.
        let contentDigest: Data

        func matchesContent(_ status: stat) -> Bool {
            Int(status.st_size) == contentSize
                && Int(status.st_mtimespec.tv_sec) == mtimeSeconds
                && Int(status.st_mtimespec.tv_nsec) == mtimeNanoseconds
        }
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
    /// - Parameters:
    ///   - shouldAbort: 세션 종단(취소) 폴링 클로저. 복사·digest 경계마다 확인해
    ///     이미 무의해진 대형 I/O가 staging 제거 뒤에도 지속되지 않게 한다(#3842246328).
    func snapshotFile(
        from sourceDescriptor: Int32,
        label: String,
        shouldAbort: (() -> Bool)? = nil,
    ) throws -> ClaimedFileIdentity {
        var before = stat()
        guard Darwin.fstat(sourceDescriptor, &before) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        for _ in 0 ..< 2 {
            if let shouldAbort, shouldAbort() {
                throw POSIXError(.ECANCELED)
            }
            let snapshot = try createSnapshotFile(from: sourceDescriptor, mode: before.st_mode & 0o777)
            // 내용 digest는 descriptor를 닫기 전에 계산한다(코멘트 #3838035179).
            let digest = Self.sha256(ofDescriptor: snapshot.descriptor, shouldAbort: shouldAbort)
            Darwin.close(snapshot.descriptor)
            var after = stat()
            guard Darwin.fstat(sourceDescriptor, &after) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard let digest else {
                try? fileManager.removeItem(
                    URL(fileURLWithPath: directoryPath).appendingPathComponent(snapshot.name),
                )
                throw CocoaError(.fileReadUnknown)
            }
            if Self.isStable(before, after) {
                let entry = Entry(
                    name: snapshot.name,
                    identity: snapshot.identity,
                    isDirectory: false,
                    mode: before.st_mode & 0o777,
                    contentSize: Int(before.st_size),
                    mtimeSeconds: Int(before.st_mtimespec.tv_sec),
                    mtimeNanoseconds: Int(before.st_mtimespec.tv_nsec),
                    contentDigest: digest,
                )
                lock.lock()
                entries[label] = entry
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
        let entry = Entry(
            name: name,
            identity: identity,
            isDirectory: true,
            mode: mode,
            contentSize: Int(status.st_size),
            mtimeSeconds: Int(status.st_mtimespec.tv_sec),
            mtimeNanoseconds: Int(status.st_mtimespec.tv_nsec),
            contentDigest: Data(),
        )
        lock.lock()
        entries[label] = entry
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
        // inode 일치만으로는 같은 inode 안의 재기록을 잡지 못한다. 스냅숏 완료 시점의
        // size+mtime과 대조해 mutable inode의 현재 내용 변조를 fail-closed한다(#3837956594).
        guard Darwin.fstat(descriptor, &status) == 0,
              entry.identity.matches(status),
              entry.matchesContent(status),
              // 스냅샷 시점에 기록한 mode도 대조해 chmod변조를
              // 탐지한다(#3840637312).
              status.st_mode & 0o777 == entry.mode
        else {
            Darwin.close(descriptor)
            throw CocoaError(.fileReadUnknown)
        }
        // 동일 길이·동일 mtime 재작성까지 차단한다: 스냅숏 바이트의 digest를 다시 계산해
        // 대조한 뒤 caller가 읽을 수 있게 되감는다(코멘트 #3838035179).
        if !entry.isDirectory {
            guard let digest = Self.sha256(ofDescriptor: descriptor), digest == entry.contentDigest else {
                Darwin.close(descriptor)
                throw CocoaError(.fileReadUnknown)
            }
            Darwin.lseek(descriptor, 0, SEEK_SET)
        }
        return (descriptor, entry.isDirectory)
    }

    /// entries 레지스트리만 O(1)로 비운다. 개별 스냅숏 파일 삭제는 보관 디렉터리 통째
    /// tombstone-rename 이후 백그라운드 재귀 삭제가 단일 소유한다(코멘트 #3840293889).
    func clearRegistry() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
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

    /// descriptor 콘텐츠의 canonical SHA-256이다. data fork 스트림 뒤 정렬된 xattr
    /// 이름·값 쌍을 포함해 resource fork·확장 속성 재작성까지 탐지한다 — COPYFILE_ALL
    /// 복사 범위와 검증 범위를 일치시킨다(코멘트 #3840534608). 오프셋은 0으로 되감고
    /// caller가 검증 후 되감기를 담당한다.
    static func sha256(ofDescriptor descriptor: Int32, shouldAbort: (() -> Bool)? = nil) -> Data? {
        var hasher = SHA256()
        var headerStatus = stat()
        guard Darwin.fstat(descriptor, &headerStatus) == 0 else { return nil }
        // \ub3c4\uba54\uc778 \ud0dc\uadf8\u00b7data fork \uae38\uc774·xattr \uac1c\uc218\ub97c \uba3c\uc800
        // \ud504\ub808\uc784\ud574
        // \uacbd\uacc4 \ubaa8\ud638\ub97c \ucc28\ub2e8\ud55c\ub2e4(#3841565531).
        hasher.update(data: Data("VOY-CAT-DIGEST-v2".utf8))
        appendFramedLength(Int64(headerStatus.st_size), into: &hasher)
        let names = sortedXattrNames(ofDescriptor: descriptor) ?? []
        appendFramedLength(Int64(names.count), into: &hasher)
        guard hashDataFork(
            ofDescriptor: descriptor,
            expectedBytes: Int(headerStatus.st_size),
            into: &hasher,
            shouldAbort: shouldAbort,
        ) else { return nil }
        if let shouldAbort, shouldAbort() { return nil }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: xattrStreamChunkBytes,
            alignment: MemoryLayout<UInt8>.alignment,
        )
        defer { buffer.deallocate() }
        for name in sortedXattrNames(ofDescriptor: descriptor) ?? [] {
            // 이름과 값은 성격이 다르므로 각각 길이 접두 프레이밍한다. NUL 연결은
            // 값 내부 NUL로 경계를 위조할 수 있었다(#3840824707).
            let nameBytes = Data(name.utf8)
            appendFramedLength(Int64(nameBytes.count), into: &hasher)
            hasher.update(data: nameBytes)
            let valueSize32 = fgetxattr(descriptor, name, nil, 0, 0, 0)
            guard valueSize32 >= 0 else { return nil }
            let valueSize = Int(valueSize32)
            appendFramedLength(Int64(valueSize), into: &hasher)
            // resource fork는 position 기반 청크 스트리밍으로 메모리 상한을 고정하고,
            // 일반 xattr은 128KiB(AppKit xattr 상한) 초과 시 실패 폐쇄한다.
            if name == Self.resourceForkXattrName {
                var offset = 0
                while offset < valueSize {
                    if let shouldAbort, shouldAbort() { return nil }
                    let chunk = min(xattrStreamChunkBytes, valueSize - offset)
                    let got = fgetxattr(
                        descriptor,
                        name,
                        buffer,
                        chunk,
                        UInt32(offset),
                        0,
                    )
                    guard got == chunk else { return nil }
                    hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: got))
                    offset += chunk
                }
            } else {
                guard valueSize <= regularXattrMaxBytes else { return nil }
                let got = fgetxattr(descriptor, name, buffer, valueSize, 0, 0)
                guard got == valueSize else { return nil }
                hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: got))
            }
        }
        return Data(hasher.finalize())
    }

    private static func isStable(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
    }

    /// provider가 전달하는 resource fork 크기 직결 메모리 할당을 막기 위한 청크 크기다
    /// (#3840824707).
    static let resourceForkXattrName = "com.apple.ResourceFork"
    static let xattrStreamChunkBytes = 1 << 20
    /// 일반 xattr의 명시적 상한. 초과 시 실패 폐쇄한다(#3840824707).
    static let regularXattrMaxBytes = 128 * 1024

    /// 길이 접두 프레이밍: 8바이트 big-endian 길이를 해시에 넣는다(#3840824707).
    private static func appendFramedLength(_ length: Int64, into hasher: inout SHA256) {
        withUnsafeBytes(of: UInt64(bitPattern: length).bigEndian) { hasher.update(bufferPointer: $0) }
    }

    /// data fork 스트림을 해시에 포함한다. 오프셋은 0으로 되감는다.
    private static func hashDataFork(
        ofDescriptor descriptor: Int32,
        expectedBytes: Int,
        into hasher: inout SHA256,
        shouldAbort: (() -> Bool)? = nil,
    ) -> Bool {
        guard Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else { return false }
        let bufferSize = 1 << 20
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize,
            alignment: MemoryLayout<UInt8>.alignment,
        )
        defer { buffer.deallocate() }
        // 프레이밍한 선언 길이만큼만 읽는다. 조기 EOF나 초과 바이트는 data fork와
        // xattr 프레임의 경계가 선언과 어긋난 것이므로 실패 폐쇄한다(#3849011298).
        var remaining = expectedBytes
        while remaining > 0 {
            if let shouldAbort, shouldAbort() { return false }
            let readCount = Darwin.read(descriptor, buffer, min(bufferSize, remaining))
            if readCount < 0 {
                if errno == EINTR { continue }
                return false
            }
            if readCount == 0 { return false }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: readCount))
            remaining -= readCount
        }
        if Darwin.read(descriptor, buffer, 1) != 0 { return false }
        return true
    }

    /// xattr 이름을 정렬해 반환한다. xattr이 없으면 빈 배열을 반환한다.
    static func sortedXattrNames(ofDescriptor descriptor: Int32) -> [String]? {
        let listLength32 = flistxattr(descriptor, nil, 0, 0)
        guard listLength32 >= 0 else { return nil }
        guard listLength32 > 0 else { return [] }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: listLength32,
            alignment: MemoryLayout<CChar>.alignment,
        )
        defer { buffer.deallocate() }
        let listed = flistxattr(
            descriptor,
            buffer.assumingMemoryBound(to: CChar.self),
            listLength32,
            0,
        )
        guard listed == listLength32 else { return nil }
        var names: [String] = []
        var cursor = buffer.assumingMemoryBound(to: CChar.self)
        let end = cursor + Int(listLength32)
        while cursor < end, cursor.pointee != 0 {
            names.append(String(cString: cursor))
            cursor = cursor + strlen(cursor) + 1
        }
        return names.sorted()
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
