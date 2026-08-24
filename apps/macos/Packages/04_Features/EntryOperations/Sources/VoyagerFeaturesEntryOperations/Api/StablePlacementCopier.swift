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
        guard Darwin.lseek(sourceDescriptor, 0, SEEK_SET) >= 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw posixError()
        }
        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }
        guard fcopyfile(sourceDescriptor, destinationDescriptor, state, copyfile_flags_t(COPYFILE_ALL)) == 0 else {
            let error = posixError()
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
        guard Darwin.mkdir(destination.path, mode) == 0 else { throw posixError() }
        do {
            for childLabel in childLabels(label).sorted() {
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
