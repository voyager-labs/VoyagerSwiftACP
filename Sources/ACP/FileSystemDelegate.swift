import ACPModel
import Foundation
import os.log

/// Actor responsible for handling file system operations for agent sessions
public actor FileSystemDelegate {
    private let logger = Logger.forCategory("FileSystemDelegate")

    // MARK: - Initialization

    public init() {}

    // MARK: - File Operations

    /// Handle file read request from agent
    ///
    /// `line` and `limit` are peer-supplied integers: they are clamped to safe
    /// ranges with overflow-free arithmetic so a hostile value (Int.min, a
    /// negative limit, a line past EOF) yields an empty window instead of an
    /// index trap in the host process.
    public func handleFileReadRequest(
        _ path: String,
        sessionId _: String,
        line: Int?,
        limit: Int?,
    ) async throws -> ReadTextFileResponse {
        let url = URL(fileURLWithPath: path)
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        let filteredContent: String
        if let startLine = line, let lineLimit = limit {
            let startIdx = Self.clampedStartIndex(startLine, lineCount: lines.count)
            let windowLength = max(0, min(lineLimit, lines.count - startIdx))
            let endIdx = startIdx + windowLength
            filteredContent = lines[startIdx ..< endIdx].joined(separator: "\n")
        } else if let startLine = line {
            let startIdx = Self.clampedStartIndex(startLine, lineCount: lines.count)
            filteredContent = lines[startIdx...].joined(separator: "\n")
        } else {
            filteredContent = content
        }

        return ReadTextFileResponse(content: filteredContent, totalLines: lines.count, _meta: nil)
    }

    private static func clampedStartIndex(_ startLine: Int, lineCount: Int) -> Int {
        // `max(1, ...)` first so `startLine - 1` cannot overflow for Int.min.
        let normalizedLine = max(1, startLine)
        return min(normalizedLine - 1, lineCount)
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
