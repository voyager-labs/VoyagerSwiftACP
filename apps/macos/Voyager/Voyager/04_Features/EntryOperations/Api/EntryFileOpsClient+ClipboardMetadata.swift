import AppKit

extension EntryFileOpsLive {
    nonisolated static var clipboardChangeCount: @Sendable () -> Int {
        {
            NSPasteboard.general.changeCount
        }
    }

    nonisolated static var loadClipboardCutSessionId: @Sendable () -> String? {
        {
            let pasteboard = NSPasteboard.general
            let type = NSPasteboard.PasteboardType("fm.voyager.clipboard.cutSessionId")
            let sessionId = pasteboard.string(forType: type)
            guard let sessionId, !sessionId.isEmpty else {
                return nil
            }
            return sessionId
        }
    }

    nonisolated static var saveClipboardCutSessionId: @Sendable (String?) -> Void {
        { sessionId in
            let pasteboard = NSPasteboard.general
            let type = NSPasteboard.PasteboardType("fm.voyager.clipboard.cutSessionId")
            pasteboard.setString(sessionId ?? "", forType: type)
        }
    }
}
