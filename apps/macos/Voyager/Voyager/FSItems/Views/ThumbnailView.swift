import AppKit
import SwiftUI

struct ThumbnailView: View {
    let item: FSItem
    let displaySize: CGFloat

    var body: some View {
        Image(nsImage: displayIcon)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var displayIcon: NSImage {
        if let cached = FSItemsIconUtils.getThumbnail(for: item.fullPath) {
            return cached
        }
        return FSItemsIconUtils.icon(for: item)
    }

    private var thumbnailSize: CGSize {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return CGSize(width: displaySize * scale, height: displaySize * scale)
    }
}
