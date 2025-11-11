import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FSItemGridView: View {
    let item: FSItem
    let isSelected: Bool
    let isCut: Bool
    let isRenaming: Bool
    let renamingText: String
    let isThumbnailReady: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onRenameUpdate: (String) -> Void
    let onRenameCommit: () -> Void
    let onRenameCancel: () -> Void
    let onStartDrag: () -> Void
    let onDrop: ([NSItemProvider], String) -> Void

    @State private var isDropTarget = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 1) {
            ThumbnailView(item: item, displaySize: 64, isReady: isThumbnailReady)
                .opacity(item.isHidden || isCut ? 0.5 : 1.0)
                .frame(width: 64, height: 64)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.gray.opacity(0.2) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ItemPositionKey.self,
                            value: [item.id + "_icon": geo.frame(in: .named("contentPane"))]
                        )
                    }
                )

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 4) {
                        if let tags = item.tags, !tags.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(tags.prefix(3), id: \.self) { tag in
                                    Circle()
                                        .fill(FSItemTagUtils.getTagColor(colorCode: tag.colorCode))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.top, 2)
                        }

                        if isRenaming {
                            TextField("", text: Binding(
                                get: { renamingText },
                                set: { onRenameUpdate($0) }
                            ))
                            .font(.system(size: 12))
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.plain)
                            .background(Color.black)
                            .cornerRadius(4)
                            .fixedSize()
                            .focused($isTextFieldFocused)
                            .onSubmit {
                                onRenameCommit()
                            }
                            .onExitCommand {
                                onRenameCancel()
                            }
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    isTextFieldFocused = true
                                }
                            }
                        } else {
                            Text(item.name)
                                .font(.system(size: 12))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .opacity(item.isHidden || isCut ? 0.5 : 1.0)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelected ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
                    )
                    .foregroundColor(isSelected ? .white : .primary)
                    .contentShape(RoundedRectangle(cornerRadius: 4))

                    if let additionalInfo = item.additionalInfo {
                        Text(additionalInfo)
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ItemPositionKey.self,
                            value: [item.id + "_text": geo.frame(in: .named("contentPane"))]
                        )
                    }
                )
                .frame(minHeight: 50, alignment: .top)
            }
            .frame(width: 120)
            .padding(.horizontal, 4)
        }
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
        .onDrag {
            onStartDrag()
            let url = URL(fileURLWithPath: item.fullPath)
            let provider = NSItemProvider(object: url as NSURL)
            return provider
        }
        .if(item.isDirectory) { view in
            view.onDrop(
                of: [UTType.fileURL],
                delegate: FileDropDelegate(
                    item: item,
                    onDrop: onDrop,
                    isDropTarget: $isDropTarget
                )
            )
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
