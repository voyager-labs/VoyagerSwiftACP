import AppKit
import Foundation
@testable import VoyagerFeaturesAiChat
import XCTest

final class AiChatInputTextViewDropTests: XCTestCase {
    func testFileURLPasteboardResolvesAttachmentURLs() {
        let firstURL = URL(fileURLWithPath: "/tmp/Notes.txt")
        let duplicateURL = URL(fileURLWithPath: "/tmp/Folder/../Notes.txt")
        let folderURL = URL(filePath: "/tmp/Projects", directoryHint: .isDirectory)
        let pasteboard = NSPasteboard(name: .init("AiChatInputTextViewDropTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([firstURL as NSURL, duplicateURL as NSURL, folderURL as NSURL])

        let urls = AiChatInputTextView.Coordinator.fileURLs(from: pasteboard)

        XCTAssertEqual(urls, [firstURL.standardizedFileURL, folderURL.standardizedFileURL])
    }

    func testFileURLStringPasteboardResolvesAttachmentURL() {
        let collectionURL = URL(fileURLWithPath: "/tmp/Workspace.voycoll")
        let pasteboard = NSPasteboard(name: .init("AiChatInputTextViewDropTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString(collectionURL.absoluteString, forType: .fileURL)

        let urls = AiChatInputTextView.Coordinator.fileURLs(from: pasteboard)

        XCTAssertEqual(urls, [collectionURL.standardizedFileURL])
    }
    @MainActor
    func testAttachmentDroppingTextViewConsumesFileURLDrops() {
        let fileURL = URL(fileURLWithPath: "/tmp/Dropped.txt")
        let pasteboard = NSPasteboard(name: .init("AiChatInputTextViewDropTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        let textView = AiChatInputTextView.AttachmentDroppingTextView()
        var droppedURLs: [URL] = []
        textView.onAttachmentsDropped = { droppedURLs = $0 }

        let consumed = textView.consumeFileURLs(from: pasteboard)

        XCTAssertTrue(consumed)
        XCTAssertEqual(droppedURLs, [fileURL.standardizedFileURL])
        XCTAssertEqual(textView.string, "")
    }

}
