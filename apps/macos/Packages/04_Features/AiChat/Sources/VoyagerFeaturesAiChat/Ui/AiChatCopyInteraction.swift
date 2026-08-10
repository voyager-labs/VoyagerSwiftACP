import AppKit
import Dependencies
import SwiftUI
import VoyagerShared

enum AiChatRowCopyFormat: Equatable {
    case markdown
    case plainText
}

@MainActor
final class AiChatCopyInteractionModel: ObservableObject {
    typealias Announcement = @MainActor (String) -> Void
    typealias Sleep = @Sendable (Duration) async throws -> Void

    enum Feedback: Equatable {
        case copied
        case failed

        var visibleLabel: String {
            switch self {
            case .copied:
                "복사됨"
            case .failed:
                "복사하지 못했습니다. 다시 시도해 주세요."
            }
        }

        var accessibilityLabel: String {
            visibleLabel
        }
    }

    @Published private(set) var feedback: Feedback?
    @Published private(set) var isRowSelected = false
    @Published private(set) var rowCopyFormat = AiChatRowCopyFormat.plainText

    @Dependency(\.pasteboardClient)
    private var pasteboardClient

    private let announce: Announcement
    private let sleep: Sleep
    private var feedbackTask: Task<Void, Never>?

    init(
        announce: @escaping Announcement = AiChatCopyInteractionModel.postAccessibilityAnnouncement,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
    ) {
        self.announce = announce
        self.sleep = sleep
    }

    deinit {
        feedbackTask?.cancel()
    }

    func copyRow(format: AiChatRowCopyFormat, rawMarkdown: String, plainText: String) {
        rowCopyFormat = format
        copy(format == .markdown ? rawMarkdown : plainText)
    }

    func selectAll() {
        isRowSelected = true
    }

    func clearSelection() {
        isRowSelected = false
    }

    func copySelectedRow(rawMarkdown: String, plainText: String) {
        guard isRowSelected else { return }
        copy(rowCopyFormat == .markdown ? rawMarkdown : plainText)
    }

    func copyCode(_ payload: String) {
        copy(payload)
    }

    private func copy(_ payload: String) {
        pasteboardClient.clearContents()
        let didWriteObjects = pasteboardClient.writeObjects([payload as NSString])
        let didWrite = didWriteObjects || pasteboardClient.setString(payload, .string)
        let result: Feedback = didWrite ? .copied : .failed
        present(result)
    }

    private func present(_ result: Feedback) {
        feedbackTask?.cancel()
        feedback = result
        announce(result.accessibilityLabel)
        guard result == .copied else { return }

        let sleep = sleep
        feedbackTask = Task { [weak self] in
            do {
                try await sleep(.seconds(2))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.feedback = nil
        }
    }

    private static func postAccessibilityAnnouncement(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ],
        )
    }
}

@MainActor
struct AiChatOutputContextMenuAction {
    let title: String
    let isEnabled: Bool
    let perform: () -> Void
}

enum AiChatMarkdownBlockLayout {
    static let ownsChildVerticalScroll = false

    static func allowsHorizontalOverflow(for kind: AiChatMarkdownDocument.BlockKind) -> Bool {
        switch kind {
        case .code, .table:
            true
        case .heading, .paragraph, .bullet, .numbered, .blockquote:
            false
        }
    }
}

enum AiChatMarkdownAccessibility {
    static func codeValue(originalLanguage: String?) -> String {
        "코드 블록, \(originalLanguage ?? "언어 없음")"
    }

    static func tableValue(rowCount: Int, columnCount: Int) -> String {
        "표, \(rowCount)행 \(columnCount)열"
    }
}
