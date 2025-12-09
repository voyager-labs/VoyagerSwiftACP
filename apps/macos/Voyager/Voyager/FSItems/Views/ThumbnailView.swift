import AppKit
import SwiftUI

struct ThumbnailView: View {
    let item: FSItem
    let displaySize: CGFloat
    let isReady: Bool

    var body: some View {
        Image(nsImage: displayIcon)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .id("\(item.fullPath)-\(isReady)")
    }

    private var displayIcon: NSImage {
        if let cached = FSItemIconUtils.getThumbnail(for: item.fullPath) {
            return cached
        }
        return FSItemIconUtils.icon(for: item)
    }
}
