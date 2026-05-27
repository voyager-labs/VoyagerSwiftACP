import AppKit
import Foundation
import VoyagerEntitiesEntry
import VoyagerShared

extension EntryFileOpsLive {
    nonisolated static var fileExists: @Sendable (String) -> Bool {
        { path in
            FileManagerClient.liveValue.fileExists(path)
        }
    }

    nonisolated static var saveDragPaths: @Sendable ([String]) -> Void {
        { paths in
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
            pasteboard.clearContents()
            let pathString = paths.joined(separator: "\n")
            pasteboard.setString(pathString, forType: .string)
        }
    }

    nonisolated static var loadDragPaths: @Sendable () -> [String] {
        {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
            guard let pathString = pasteboard.string(forType: .string),
                  !pathString.isEmpty
            else {
                return []
            }
            return pathString.split(separator: "\n").map(String.init)
        }
    }

    nonisolated static var saveDragWithOption: @Sendable (Bool) -> Void {
        { isOptionPressed in
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
            pasteboard.setString(
                isOptionPressed ? "true" : "false",
                forType: NSPasteboard.PasteboardType("VoyagerDragOption"),
            )
        }
    }

    nonisolated static var loadDragWithOption: @Sendable () -> Bool {
        {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("VoyagerDragDrop"))
            let optionString = pasteboard.string(forType: NSPasteboard.PasteboardType("VoyagerDragOption"))
            return optionString == "true"
        }
    }

    nonisolated static var loadClipboardPaths: @Sendable () -> ([String], ClipboardOperation) {
        {
            let pasteboardClient = PasteboardClient.liveValue

            guard let objects = pasteboardClient.readObjects([NSURL.self], nil),
                  let urls = objects as? [URL]
            else {
                return ([], .copy)
            }

            let paths = urls.map(\.path)
            let opString = pasteboardClient
                .string(NSPasteboard.PasteboardType("fm.voyager.clipboard.operation"))
            let operation: ClipboardOperation = opString == "cut" ? .cut : .copy

            return (paths, operation)
        }
    }

    nonisolated static var postFileSystemChanged: @Sendable ([String]) -> Void {
        { paths in
            NotificationCenter.default.post(
                name: EntryWatchingLive.fileSystemChangedNotificationName,
                object: nil,
                userInfo: ["paths": paths],
            )
        }
    }
}
