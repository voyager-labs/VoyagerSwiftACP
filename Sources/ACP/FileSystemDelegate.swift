import ACPModel
import Foundation
import os.log

/// Actor responsible for handling file system operations for agent sessions
public actor FileSystemDelegate {
    private let logger = Logger.forCategory("FileSystemDelegate")

    // MARK: - Initialization

    public init() {}

    // MARK: - File Operations

    /// Read ceiling for one request: reading is chunked and stops here, so a
    /// peer-supplied path (even an endless character device) cannot make this
    /// actor read forever or exhaust memory.
    private static let maxFileReadBytes = 8_000_000
    /// Response ceiling for a windowed read; content beyond it is dropped.
    private static let maxResponseBytes = 4_000_000

    /// Handle file read request from agent
    ///
    /// `line` and `limit` are peer-supplied integers, so nothing is trusted:
    /// reading is chunked under a byte cap and only the requested line window
    /// is materialized, which keeps hostile values (Int.min, a negative limit,
    /// a line past EOF, `/dev/zero`) from trapping or exhausting memory.
    public func handleFileReadRequest(
        _ path: String,
        sessionId _: String,
        line: Int?,
        limit: Int?,
    ) async throws -> ReadTextFileResponse {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }

        // Overflow-free, clamped window: lines are 1-based on the wire.
        let startIdx = line.map { max(1, $0) - 1 } ?? 0
        let windowLength = limit.map { max(0, min($0, Self.maxResponseBytes)) } ?? Int.max
        let windowed = line != nil

        var totalLines = 0
        var windowLines: [String] = []
        var windowBytes = 0
        var pending = Data()
        var wholeFileData = Data()
        var readBytes = 0

        func consume(_ lineData: Data) {
            totalLines += 1
            guard windowed, lineIndexIsInsideWindow(afterLine: totalLines - 1) else { return }
            guard windowBytes < Self.maxResponseBytes else { return }
            var textData = lineData
            if textData.last == 0x0D {
                // Keep CRLF files behaving like the previous line split.
                textData = textData.dropLast()
            }
            let remaining = Self.maxResponseBytes - windowBytes
            if textData.count > remaining {
                textData = textData.prefix(remaining)
            }
            let text = String(decoding: textData, as: UTF8.self)
            windowLines.append(text)
            windowBytes += text.utf8.count + 1
        }

        func lineIndexIsInsideWindow(afterLine: Int) -> Bool {
            afterLine >= startIdx && windowLines.count < windowLength
        }

        while readBytes < Self.maxFileReadBytes {
            let chunk = (try? handle.read(upToCount: 65536)) ?? Data()
            if chunk.isEmpty { break }
            readBytes += chunk.count
            pending.append(chunk)
            if !windowed {
                wholeFileData.append(chunk)
            }

            while let newlineIndex = pending.firstIndex(of: 0x0A) {
                let lineData = pending.subdata(in: pending.startIndex ..< newlineIndex)
                pending.removeSubrange(pending.startIndex ... newlineIndex)
                consume(lineData)
            }
        }
        if !pending.isEmpty {
            consume(pending)
        }

        let filteredContent = if windowed {
            windowLines.joined(separator: "\n")
        } else {
            // Whole-file reads preserve the exact bytes that were read.
            String(decoding: wholeFileData, as: UTF8.self)
        }

        return ReadTextFileResponse(content: filteredContent, totalLines: max(totalLines, 1), _meta: nil)
    }

    /// Handle file write request from agent
    /// Per ACP spec: Client MUST create the file if it doesn't exist
    public func handleFileWriteRequest(
        _ path: String,
        content: String,
        sessionId _: String,
    ) async throws -> WriteTextFileResponse {
        logger.info("Write request for: \(path) (\(content.count) chars)")
        let url = URL(fileURLWithPath: path)
        let fileManager = FileManager.default

        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            logger.info("Write succeeded: \(path)")
            return WriteTextFileResponse(_meta: nil)
        } catch {
            logger.error("Write failed for \(path): \(error.localizedDescription)")
            throw error
        }
    }
}

// MARK: - Typealiases for backward compatibility

@available(*, deprecated, renamed: "FileSystemDelegate")
public typealias ACPFileSystemDelegate = FileSystemDelegate
