import Foundation
import VoyagerShared

/// placement 복사 전용 copier. 소스 노드는 caller가 제공하는 검증된 opener를 통해서만 열고,
/// 경로/`openat` 재해석으로 다른 inode를 열지 않는다(코멘트 #3835329095). opener는 기록된
/// inode 신원과 대조한 descriptor를 반환하며, 각 노드는 사용 직후 닫힌다. 동시 fd는
/// 순회 깊이 수준으로 제한된다(RLIMIT_NOFILE 안전).
enum StablePlacementCopier {
    /// `rootPath`(포함)를 루트로 하는 하위 트리를 `destination`으로 복사한다.
    /// - `openVerifiedNode(label)`: label의 검증된 descriptor와 디렉터리 여부를 반환한다.
    /// - `closeVerifiedNode(fd)`: opener가 연 descriptor를 닫는다.
    /// - `childLabels(label)`: label의 직계 자식 label 목록을 반환한다.
    static func copySubtree(
        rootPath: String,
        destination: URL,
        openVerifiedNode: (String) throws -> (fd: Int32, isDirectory: Bool),
        closeVerifiedNode: (Int32) -> Void,
        childLabels: (String) -> [String],
        verifyCopiedFile: ((String, URL) throws -> Void)? = nil,
    ) throws {
        try copyNode(
            label: rootPath,
            destination: destination,
            openVerifiedNode: openVerifiedNode,
            closeVerifiedNode: closeVerifiedNode,
            childLabels: childLabels,
            verifyCopiedFile: verifyCopiedFile,
        )
    }

    private static func copyNode(
        label: String,
        destination: URL,
        openVerifiedNode: (String) throws -> (fd: Int32, isDirectory: Bool),
        closeVerifiedNode: (Int32) -> Void,
        childLabels: (String) -> [String],
        verifyCopiedFile: ((String, URL) throws -> Void)? = nil,
    ) throws {
        let node = try openVerifiedNode(label)
        defer { closeVerifiedNode(node.fd) }
        var status = stat()
        guard Darwin.fstat(node.fd, &status) == 0 else { throw posixError() }
        switch status.st_mode & S_IFMT {
        case S_IFREG:
            try copyFile(node.fd, status: status, destination: destination)
            // 검증과 실제 fcopyfile 사이 같은 inode 재기록 TOCTOU를 닫는다:
            // destination에 실제로 기록된 바이트의 digest를 대조한다(코멘트 #3840108372).
            if let verifyCopiedFile {
                do {
                    try verifyCopiedFile(label, destination)
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    throw error
                }
            }
        case S_IFDIR:
            try copyDirectory(
                label: label,
                mode: status.st_mode & 0o777,
                destination: destination,
                openVerifiedNode: openVerifiedNode,
                closeVerifiedNode: closeVerifiedNode,
                childLabels: childLabels,
                verifyCopiedFile: verifyCopiedFile,
            )
        default:
            throw CocoaError(.fileReadUnsupportedScheme)
        }
    }

    private static func copyFile(
        _ sourceDescriptor: Int32,
        status: stat,
        destination: URL,
    ) throws {
        let mode = status.st_mode & 0o777
        let destinationDescriptor = Darwin.open(
            destination.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
            mode,
        )
        guard destinationDescriptor >= 0 else { throw posixError() }
        defer { Darwin.close(destinationDescriptor) }

        do {
            guard Darwin.lseek(sourceDescriptor, 0, SEEK_SET) >= 0 else { throw posixError() }
            let bufferSize = 1 << 20
            let buffer = UnsafeMutableRawPointer.allocate(
                byteCount: bufferSize,
                alignment: MemoryLayout<UInt8>.alignment,
            )
            defer { buffer.deallocate() }
            while true {
                try Task.checkCancellation()
                let readCount = Darwin.read(sourceDescriptor, buffer, bufferSize)
                if readCount < 0 {
                    if errno == EINTR { continue }
                    throw posixError()
                }
                if readCount == 0 { break }
                var written = 0
                while written < readCount {
                    let writeCount = Darwin.write(
                        destinationDescriptor,
                        buffer.advanced(by: written),
                        readCount - written,
                    )
                    if writeCount < 0 {
                        if errno == EINTR { continue }
                        throw posixError()
                    }
                    written += writeCount
                }
            }

            // xattr(resource fork 포함) 복제. 청크 사이에도 취소를 확인한다.
            for name in PinnedContentStore.sortedXattrNames(ofDescriptor: sourceDescriptor) ?? [] {
                try Task.checkCancellation()
                let valueSize = fgetxattr(sourceDescriptor, name, nil, 0, 0, 0)
                guard valueSize >= 0 else { throw posixError() }
                var offset = 0
                while offset < Int(valueSize) {
                    try Task.checkCancellation()
                    let chunk = min(1 << 20, Int(valueSize) - offset)
                    var chunkData = Data(count: chunk)
                    let got = chunkData.withUnsafeMutableBytes { mutable -> Int in
                        guard let base = mutable.baseAddress else { return -1 }
                        return fgetxattr(sourceDescriptor, name, base, chunk, UInt32(offset), 0)
                    }
                    guard got == chunk else { throw posixError() }
                    let setResult = chunkData.withUnsafeBytes { immutable -> Int32 in
                        fsetxattr(destinationDescriptor, name, immutable.baseAddress, chunk, UInt32(offset), 0)
                    }
                    guard setResult == 0 else { throw posixError() }
                    offset += chunk
                }
            }

            // 원본 mode 복원: open 시점 umask가 제거한 비트를 되돌린다(코멘트 #3840914586).
            guard Darwin.fchmod(destinationDescriptor, mode) == 0 else { throw posixError() }

            // 성공 반환 전 최종 취소 확인(#3840637309).
            try Task.checkCancellation()
        } catch {
            // 취소를 포함한 모든 실패에서 부분 destination을 제거한 뒤 전파한다
            // (코멘트 #3840914579).
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func copyDirectory(
        label: String,
        mode: mode_t,
        destination: URL,
        openVerifiedNode: (String) throws -> (fd: Int32, isDirectory: Bool),
        closeVerifiedNode: (Int32) -> Void,
        childLabels: (String) -> [String],
        verifyCopiedFile: ((String, URL) throws -> Void)? = nil,
    ) throws {
        // 읽기 전용 모드(예: 0555) 디렉터리도 자식 쓰기를 위해 생성 시에만 소유자
        // 쓰기·실행 권한을 더하고, 전체 복사 뒤 하단 chmod가 원본 모드로 되돌린다
        // (코멘트 #3840396992).
        guard Darwin.mkdir(destination.path, mode | 0o700) == 0 else { throw posixError() }
        do {
            for childLabel in childLabels(label).sorted() {
                // 대형 트리에서 노드 사이에 취소를 확인해 즉시 중단한다(#3840396987).
                try Task.checkCancellation()
                try copyNode(
                    label: childLabel,
                    destination: destination.appendingPathComponent(
                        (childLabel as NSString).lastPathComponent,
                    ),
                    openVerifiedNode: openVerifiedNode,
                    closeVerifiedNode: closeVerifiedNode,
                    childLabels: childLabels,
                    verifyCopiedFile: verifyCopiedFile,
                )
            }
            guard Darwin.chmod(destination.path, mode) == 0 else { throw posixError() }
        } catch {
            // 오류 경로 정리만 수행하므로 DI client 대신 FileManager.default를 쓴다.
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
