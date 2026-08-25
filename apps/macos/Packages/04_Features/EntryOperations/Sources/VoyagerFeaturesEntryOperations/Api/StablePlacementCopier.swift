import Foundation
import VoyagerShared

/// placement 복사 전용 copier. 소스 노드는 caller가 제공하는 검증된 opener를 통해서만 열고,
/// 경로/`openat` 재해석으로 다른 inode를 열지 않는다(코멘트 #3835329095). opener는 기록된
/// inode 신원과 대조한 descriptor를 반환하며, 각 노드는 사용 직후 닫힌다. 동시 fd는
/// 순회 깊이 수준으로 제한된다(RLIMIT_NOFILE 안전).
enum StablePlacementCopier {
    /// 트리 순회에 필요한 검증 콜백 묶음. 재귀 호출의 파라미터 수를 고정한다.
    private struct Traversal {
        let openVerifiedNode: (String) throws -> (fd: Int32, isDirectory: Bool)
        let closeVerifiedNode: (Int32) -> Void
        let childLabels: (String) -> [String]
        let verifyCopiedFile: ((String, URL) throws -> Void)?

        init(
            openVerifiedNode: @escaping (String) throws -> (fd: Int32, isDirectory: Bool),
            closeVerifiedNode: @escaping (Int32) -> Void,
            childLabels: @escaping (String) -> [String],
            verifyCopiedFile: ((String, URL) throws -> Void)?,
        ) {
            self.openVerifiedNode = openVerifiedNode
            self.closeVerifiedNode = closeVerifiedNode
            self.childLabels = childLabels
            self.verifyCopiedFile = verifyCopiedFile
        }
    }

    /// `rootPath`(포함)를 루트로 하는 하위 트리를 `destination`으로 복사한다.
    /// - `openVerifiedNode(label)`: label의 검증된 descriptor와 디렉터리 여부를 반환한다.
    /// - `closeVerifiedNode(fd)`: opener가 연 descriptor를 닫는다.
    /// - `childLabels(label)`: label의 직계 자식 label 목록을 반환한다.
    static func copySubtree(
        rootPath: String,
        destination: URL,
        openVerifiedNode: @escaping (String) throws -> (fd: Int32, isDirectory: Bool),
        closeVerifiedNode: @escaping (Int32) -> Void,
        childLabels: @escaping (String) -> [String],
        verifyCopiedFile: ((String, URL) throws -> Void)? = nil,
    ) throws {
        // 최상위 목적지 부모를 fd로 고정한다. 이후 모든 자식 생성은 이 fd(와 하위
        // 고정 fd) 기준 openat/mkdirat으로 수행되어, 검사 직후 부모가 rename·치환
        // 돼도 자식이 symlink 밖으로 빠지지 않는다(#3849087644).
        let parentDescriptor = Darwin.open(
            destination.deletingLastPathComponent().path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC,
        )
        guard parentDescriptor >= 0 else { throw posixError() }
        defer { Darwin.close(parentDescriptor) }
        let traversal = Traversal(
            openVerifiedNode: openVerifiedNode,
            closeVerifiedNode: closeVerifiedNode,
            childLabels: childLabels,
            verifyCopiedFile: verifyCopiedFile,
        )
        try copyNode(
            label: rootPath,
            parentDescriptor: parentDescriptor,
            displayURL: destination,
            traversal: traversal,
        )
    }

    /// `parentDescriptor`가 가리키는 디렉터리 안에 `displayURL` 마지막 성분으로 노드를
    /// 생성한다. `displayURL`은 검증 콜백과 오류 정리(경로 기반, best-effort)에만 쓰인다.
    private static func copyNode(
        label: String,
        parentDescriptor: Int32,
        displayURL: URL,
        traversal: Traversal,
    ) throws {
        let node = try traversal.openVerifiedNode(label)
        defer { traversal.closeVerifiedNode(node.fd) }
        var status = stat()
        guard Darwin.fstat(node.fd, &status) == 0 else { throw posixError() }
        switch status.st_mode & S_IFMT {
        case S_IFREG:
            try copyFile(
                node.fd,
                status: status,
                parentDescriptor: parentDescriptor,
                displayURL: displayURL,
            )
            // 검증과 실제 fcopyfile 사이 같은 inode 재기록 TOCTOU를 닫는다:
            // destination에 실제로 기록된 바이트의 digest를 대조한다(코멘트 #3840108372).
            if let verifyCopiedFile = traversal.verifyCopiedFile {
                do {
                    try verifyCopiedFile(label, displayURL)
                } catch {
                    try? FileManager.default.removeItem(at: displayURL)
                    throw error
                }
            }
        case S_IFDIR:
            try copyDirectory(
                label: label,
                mode: status.st_mode & 0o777,
                sourceDirectoryDescriptor: node.fd,
                parentDescriptor: parentDescriptor,
                displayURL: displayURL,
                traversal: traversal,
            )
        default:
            throw CocoaError(.fileReadUnsupportedScheme)
        }
    }

    private static func copyFile(
        _ sourceDescriptor: Int32,
        status: stat,
        parentDescriptor: Int32,
        displayURL: URL,
    ) throws {
        let mode = status.st_mode & 0o777
        // 고정된 부모 fd 상대 생성. 경로 재해석으로 치환된 대상에 쓰지 않는다(#3849087644).
        let destinationDescriptor = Darwin.openat(
            parentDescriptor,
            displayURL.lastPathComponent,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
            mode,
        )
        guard destinationDescriptor >= 0 else { throw posixError() }
        defer { Darwin.close(destinationDescriptor) }

        do {
            // destination을 논리 크기로 먼저 확보하면 전체가 0인 구간을 건너뛸 때 hole이
            // 그대로 유지돼 sparse 파일의 물리적 팽창을 막는다(#3841132162).
            guard Darwin.ftruncate(destinationDescriptor, status.st_size) == 0 else { throw posixError() }

            try copyDataFork(from: sourceDescriptor, to: destinationDescriptor)
            try duplicateXattrs(from: sourceDescriptor, to: destinationDescriptor)

            // 원본 mode 복원: open 시점 umask가 제거한 비트를 되돌린다(코멘트 #3840914586).
            guard Darwin.fchmod(destinationDescriptor, mode) == 0 else { throw posixError() }

            // placement가 새 파일을 생성하므로 원본 스냅숏의 mtime/atime을 복원해야
            // Finder 날짜 정렬·메타데이터가 유지된다(#3840962273).
            var times = [timeval](repeating: timeval(tv_sec: 0, tv_usec: 0), count: 2)
            times[0].tv_sec = status.st_atimespec.tv_sec
            times[0].tv_usec = Int32(status.st_atimespec.tv_nsec / 1000)
            times[1].tv_sec = status.st_mtimespec.tv_sec
            times[1].tv_usec = Int32(status.st_mtimespec.tv_nsec / 1000)
            // fd 기반 적용: 목적지 부모가 경로를 rename·치환해도 복사한 inode의
            // 시각만 복원한다(#3848721436). 검증 재개방은 mismatch가 실패 폐쇄로
            // 귀결되므로 탐지로 작동한다.
            futimes(destinationDescriptor, times)
            // 성공 반환 전 최종 취소 확인(#3840637309).
            try Task.checkCancellation()
        } catch {
            // 취소를 포함한 모든 실패에서 부분 destination을 제거한 뒤 전파한다
            // (코멘트 #3840914579). 경로 기반 best-effort 정리다.
            try? FileManager.default.removeItem(at: displayURL)
            throw error
        }
    }

    /// data fork를 chunk 단위로 복사하며 노드 사이 취소를 확인한다(#3840637309).
    /// destination은 ftruncate로 논리 크기가 확보돼 있어 전체가 0인 청크는 쓰기를
    /// 생략하고 오프셋만 전진해 hole을 유지한다.
    private static func copyDataFork(
        from sourceDescriptor: Int32,
        to destinationDescriptor: Int32,
    ) throws {
        guard Darwin.lseek(sourceDescriptor, 0, SEEK_SET) >= 0 else { throw posixError() }
        let bufferSize = 1 << 20
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize,
            alignment: MemoryLayout<UInt8>.alignment,
        )
        let zeroBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize,
            alignment: MemoryLayout<UInt8>.alignment,
        )
        // 비초기화 메모리와 비교하면 영 청크 판정이 무효하다(#3841341510).
        zeroBuffer.initializeMemory(as: UInt8.self, repeating: 0, count: bufferSize)
        defer {
            buffer.deallocate()
            zeroBuffer.deallocate()
        }
        while true {
            try Task.checkCancellation()
            let readCount = Darwin.read(sourceDescriptor, buffer, bufferSize)
            if readCount < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            if readCount == 0 { break }
            // 전체가 0인 청크는 쓰기를 생략하고 destination 오프셋만 전진해 hole을
            // 유지한다(#3841341514).
            if memcmp(buffer, zeroBuffer, readCount) == 0 {
                guard Darwin.lseek(destinationDescriptor, off_t(readCount), SEEK_CUR) >= 0 else {
                    throw posixError()
                }
                continue
            }
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
    }

    /// source의 xattr(resource fork 포함)을 destination으로 복제한다. 빈 값 속성도
    /// 생성하며 청크 사이에 취소를 확인한다(#3840962269).
    private static func duplicateXattrs(
        from sourceDescriptor: Int32,
        to destinationDescriptor: Int32,
    ) throws {
        for name in PinnedContentStore.sortedXattrNames(ofDescriptor: sourceDescriptor) ?? [] {
            try Task.checkCancellation()
            let valueSize32 = fgetxattr(sourceDescriptor, name, nil, 0, 0, 0)
            guard valueSize32 >= 0 else { throw posixError() }
            // #3840962269: 빈 값 속성도 생성한다
            var value = Data(count: Int(valueSize32))
            let got = value.withUnsafeMutableBytes { mutable -> Int in
                guard let base = mutable.baseAddress else { return -1 }
                return fgetxattr(sourceDescriptor, name, base, valueSize32, 0, 0)
            }
            guard got == valueSize32 else { throw posixError() }
            let setResult = value.withUnsafeBytes { immutable -> Int32 in
                fsetxattr(destinationDescriptor, name, immutable.baseAddress, valueSize32, 0, 0)
            }
            guard setResult == 0 else { throw posixError() }
        }
    }

    private static func copyDirectory(
        label: String,
        mode: mode_t,
        sourceDirectoryDescriptor: Int32,
        parentDescriptor: Int32,
        displayURL: URL,
        traversal: Traversal,
    ) throws {
        // 읽기 전용 모드(예: 0555) 디렉터리도 자식 쓰기를 위해 생성 시에만 소유자
        // 쓰기·실행 권한을 더하고, 전체 복사 뒤 하단 chmod가 원본 모드로 되돌린다
        // (코멘트 #3840396992).
        // 빈 디렉터리도 포함해 생성 전에 취소를 확인한다(#3841132154).
        try Task.checkCancellation()
        // 고정 부모 fd 상대 생성 직후 NOFOLLOW로 다시 열어 자식 생성·메타데이터의
        // 기준 fd로 삼는다. 부모 쓰기 권한자의 rename·symlink 치환과 무관하게 우리가
        // 만든 디렉터리 안에서만 자식이 생성된다(#3849087644, #3845390804).
        let name = displayURL.lastPathComponent
        guard Darwin.mkdirat(parentDescriptor, name, mode | 0o700) == 0 else { throw posixError() }
        let destinationDescriptor = Darwin.openat(
            parentDescriptor,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC,
        )
        guard destinationDescriptor >= 0 else {
            try? FileManager.default.removeItem(at: displayURL)
            throw posixError()
        }
        defer { Darwin.close(destinationDescriptor) }
        do {
            // 자식 쓰기와 구분하기 위해 source dir 시각을 진입 시 포착한다.
            var sourceDirStatus = stat()
            guard Darwin.fstat(sourceDirectoryDescriptor, &sourceDirStatus) == 0 else {
                throw posixError()
            }
            for childLabel in traversal.childLabels(label).sorted() {
                // 대형 트리에서 노드 사이에 취소를 확인해 즉시 중단한다(#3840396987).
                try Task.checkCancellation()
                try copyNode(
                    label: childLabel,
                    parentDescriptor: destinationDescriptor,
                    displayURL: displayURL.appendingPathComponent(
                        (childLabel as NSString).lastPathComponent,
                    ),
                    traversal: traversal,
                )
            }
            // 메타데이터는 경로 대신 고정 fd에 적용한다(#3845390804).
            guard Darwin.fchmod(destinationDescriptor, mode) == 0 else { throw posixError() }

            // placement가 새 파일을 생성하므로 원본 스냅숏의 mtime/atime을 복원해야
            // Finder 날짜 정렬·메타데이터가 유지된다(#3840962273과 동일 계약).
            var dirTimes = [timeval](repeating: timeval(tv_sec: 0, tv_usec: 0), count: 2)
            dirTimes[0].tv_sec = sourceDirStatus.st_atimespec.tv_sec
            dirTimes[0].tv_usec = Int32(sourceDirStatus.st_atimespec.tv_nsec / 1000)
            dirTimes[1].tv_sec = sourceDirStatus.st_mtimespec.tv_sec
            dirTimes[1].tv_usec = Int32(sourceDirStatus.st_mtimespec.tv_nsec / 1000)
            futimes(destinationDescriptor, dirTimes)
            // 최종 chmod 이후에도 취소를 확인한다(#3841132154).
            try Task.checkCancellation()
        } catch {
            // 오류 경로 정리만 수행하므로 DI client 대신 FileManager.default를 쓴다.
            try? FileManager.default.removeItem(at: displayURL)
            throw error
        }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
