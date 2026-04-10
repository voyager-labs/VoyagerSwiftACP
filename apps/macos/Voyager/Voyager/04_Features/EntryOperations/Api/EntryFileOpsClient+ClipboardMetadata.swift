import AppKit
import ComposableArchitecture

extension EntryFileOpsLive {
    nonisolated static var clipboardChangeCount: @Sendable () -> Int {
        {
            @Dependency(\.pasteboardClient)
            var pasteboardClient
            return pasteboardClient.changeCount()
        }
    }

    nonisolated static var loadClipboardCutSessionId: @Sendable () -> String? {
        {
            @Dependency(\.pasteboardClient)
            var pasteboardClient
            let type = NSPasteboard.PasteboardType("fm.voyager.clipboard.cutSessionId")
            let sessionId = pasteboardClient.string(type)
            guard let sessionId, !sessionId.isEmpty else {
                return nil
            }
            return sessionId
        }
    }

    nonisolated static var saveClipboardCutSessionId: @Sendable (String?) -> Void {
        { sessionId in
            @Dependency(\.pasteboardClient)
            var pasteboardClient
            let type = NSPasteboard.PasteboardType("fm.voyager.clipboard.cutSessionId")
            _ = pasteboardClient.setString(sessionId ?? "", type)
        }
    }
}
