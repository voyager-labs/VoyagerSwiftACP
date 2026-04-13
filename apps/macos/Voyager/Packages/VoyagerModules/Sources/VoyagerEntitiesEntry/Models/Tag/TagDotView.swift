import SwiftUI
import VoyagerEntitiesEntry

public struct TagDotView: View {
    public let tagColor: TagColor
    public let size: CGFloat

    public init(tagColor: TagColor, size: CGFloat = 8) {
        self.tagColor = tagColor
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(Color(nsColor: tagColor.nsColor))
            .frame(width: size, height: size)
    }
}
