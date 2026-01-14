import AppKit
import SwiftUI

struct ThumbnailView: View {
    let item: Entry
    let displaySize: CGFloat
    let isReady: Bool

    var body: some View {
        Image(nsImage: displayIcon)
            .resizable()
            .scaledToFit()
            .scaleEffect(item.fileExtension.lowercased() == "voycoll" ? 0.88 : 1.0)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .id("\(item.fullPath)-\(isReady)")
    }

    private var displayIcon: NSImage {
        if let cached = EntryIconUtils.getThumbnail(for: item.fullPath) {
            return cached
        }
        return EntryIconUtils.icon(for: item)
    }
}
