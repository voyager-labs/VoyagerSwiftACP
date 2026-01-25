import AppKit
import SwiftUI

final class ServicesMenuRequestorView: NSView, NSServicesMenuRequestor {
    var selectedURLs: [URL] = []

    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?,
    ) -> Any? {
        if sendType == .fileURL {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard types.contains(.fileURL), !selectedURLs.isEmpty else { return false }
        pboard.clearContents()
        return pboard.writeObjects(selectedURLs as [NSURL])
    }
}

struct ServicesMenuRequestorRepresentable: NSViewRepresentable {
    var selectedURLs: [URL]
    var onViewReady: (ServicesMenuRequestorView) -> Void

    func makeNSView(context _: Context) -> ServicesMenuRequestorView {
        let view = ServicesMenuRequestorView()
        view.selectedURLs = selectedURLs
        onViewReady(view)
        return view
    }

    func updateNSView(_ nsView: ServicesMenuRequestorView, context _: Context) {
        nsView.selectedURLs = selectedURLs
    }
}
