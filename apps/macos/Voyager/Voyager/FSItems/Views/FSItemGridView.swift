import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FSItemGridView: View {
    let item: FSItem
    let isSelected: Bool
    let isCut: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onStartDrag: () -> Void
    let onDrop: (String) -> Void

    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 1) {
            ThumbnailView(item: item, displaySize: 64)
                .opacity(item.isHidden || isCut ? 0.5 : 1.0)
                .frame(width: 64, height: 64)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.gray.opacity(0.2) : Color.clear)
                )
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture()
                        .onEnded { _ in
                            onSelect()
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded { _ in
                            if item.isDirectory {
                                onOpen()
                            }
                        }
                )

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 4) {
                        if let tags = item.tags, !tags.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(tags.prefix(3), id: \.self) { tag in
                                    Circle()
                                        .fill(FSItemTagUtils.getTagColor(tag) ?? Color.gray)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.top, 2)
                        }

                        Text(item.name)
                            .font(.system(size: 12))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .opacity(item.isHidden || isCut ? 0.5 : 1.0)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelected ? Color(nsColor: .controlAccentColor) : Color.clear)
                    )
                    .foregroundColor(isSelected ? .white : .primary)

                    if let additionalInfo = item.additionalInfo {
                        Text(additionalInfo)
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: 50, alignment: .top)
            }
            .frame(width: 120)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        onSelect()
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded { _ in
                        if item.isDirectory {
                            onOpen()
                        }
                    }
            )
        }
        .onDrag {
            onStartDrag()

            let url = URL(fileURLWithPath: item.fullPath)
            let provider = NSItemProvider()

            provider
                .registerFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier,
                                            visibility: .all)
                { completion in
                    completion(url, true, nil)
                    return nil
                }

            return provider
        }
        .if(item.isDirectory) { view in
            view.onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { _, _ in
                onDrop(item.fullPath)
                return true
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: isDropTarget ? 2 : 0)
            )
        }
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
