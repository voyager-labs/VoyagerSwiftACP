import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FSItemListView: View {
    let item: FSItem
    let isSelected: Bool
    let isCut: Bool
    let isRenaming: Bool
    let renamingText: String
    let availableWidth: CGFloat
    let applications: [ApplicationInfo]?
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onOpenInNewTab: (Bool) -> Void
    let onQuickLook: () -> Void
    let onOpenWithApp: (String?, Bool) -> Void
    let onRenameUpdate: (String) -> Void
    let onRenameCommit: () -> Void
    let onRenameCancel: () -> Void
    let onStartDrag: () -> Void
    let onDrop: ([NSItemProvider], String) -> Void
    let onLoadApplications: () -> Void
    let onPutBack: (() -> Void)?
    let onMoveToTrash: () -> Void
    let onDeleteImmediately: () -> Void
    let onEmptyTrash: () -> Void
    let onRename: () -> Void
    let onCompress: () -> Void
    let onDuplicate: () -> Void
    let onExtract: () -> Void
    let onCopy: () -> Void
    let onCut: () -> Void
    let onToggleTag: (String) -> Void
    let selectedCount: Int
    let showCompress: Bool
    let showExtract: Bool

    @State private var isDropTarget = false
    @FocusState private var isTextFieldFocused: Bool
    @State private var isOptionPressed = false
    @State private var optionKeyTimer: Timer?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    private struct ColumnWidths {
        let name: CGFloat
        let date: CGFloat
        let size: CGFloat
        let kind: CGFloat
    }

    private var columnWidths: ColumnWidths {
        let totalPadding = 16.0
        let dividerWidth = 3.0 * 1.0
        let availableForColumns = availableWidth - totalPadding - dividerWidth

        return ColumnWidths(
            name: availableForColumns * 0.4,
            date: availableForColumns * 0.35,
            size: availableForColumns * 0.1,
            kind: availableForColumns * 0.15
        )
    }

    private func styledText(_ text: String, fontSize: CGFloat, isPrimary: Bool = true) -> some View {
        Text(text)
            .font(.system(size: fontSize))
            .foregroundColor(isSelected ? .white : (isPrimary ? .primary : .secondary))
            .opacity(item.isHidden || isCut ? 0.5 : 1.0)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ThumbnailView(item: item, displaySize: 20)
                    .opacity(item.isHidden || isCut ? 0.5 : 1.0)
                    .frame(width: 20, height: 20)

                if isRenaming {
                    TextField("", text: Binding(
                        get: { renamingText },
                        set: { onRenameUpdate($0) }
                    ))
                    .font(.system(size: 13))
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
                    styledText(item.name, fontSize: 13)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let tags = item.tags, !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags.prefix(3), id: \.self) { tag in
                            Circle()
                                .fill(FSItemTagUtils.getTagColor(colorCode: tag.colorCode))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
            .frame(width: columnWidths.name, alignment: .leading)
            .padding(.leading, 8)

            styledText(dateText(item.modifiedDate), fontSize: 12, isPrimary: false)
                .frame(width: columnWidths.date, alignment: .leading)
                .padding(.leading, 8)

            styledText(sizeText(item), fontSize: 12, isPrimary: false)
                .frame(width: columnWidths.size, alignment: .trailing)
                .padding(.leading, 8)

            styledText(kindText(item), fontSize: 12, isPrimary: false)
                .frame(width: columnWidths.kind, alignment: .leading)
                .padding(.leading, 8)
        }
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color(nsColor: .controlAccentColor) : Color.clear)
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    onSelect()
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    onOpen()
                }
        )
        .onDrag {
            onStartDrag()

            let url = URL(fileURLWithPath: item.fullPath)
            let provider = NSItemProvider(object: url as NSURL)
            return provider
        }
        .if(item.isDirectory) { view in
            view.onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers, _ in
                onDrop(providers, item.fullPath)
                return true
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue, lineWidth: isDropTarget ? 2 : 0)
            )
        }
        .contextMenu {
            contextMenuContent
        }
        .onAppear {
            startOptionKeyMonitoring()
        }
        .onDisappear {
            stopOptionKeyMonitoring()
        }
    }

    private func startOptionKeyMonitoring() {
        let timer = Timer(timeInterval: 0.02, repeats: true) { _ in
            DispatchQueue.main.async {
                isOptionPressed = NSEvent.modifierFlags.contains(.option)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        optionKeyTimer = timer
    }

    private func stopOptionKeyMonitoring() {
        optionKeyTimer?.invalidate()
        optionKeyTimer = nil
    }
}

private extension FSItemListView {
    @ViewBuilder var contextMenuContent: some View {
        Group {
            Button {
                onOpen()
            } label: {
                Label("Open", systemImage: "arrow.up.forward.square")
            }
            .keyboardShortcut(.downArrow, modifiers: [.command])
        }
        .onAppear {
            if !item.isDirectory && applications == nil {
                onLoadApplications()
            }
        }

        if item.isDirectory {
            Button {
                onOpenInNewTab(isOptionPressed)
            } label: {
                Label(
                    isOptionPressed ? "Open in New Window" : "Open in New Tab",
                    systemImage: isOptionPressed ? "macwindow.badge.plus" : "plus.square.on.square"
                )
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        }

        if let apps = applications, !apps.isEmpty {
            Menu {
                let regularApps = apps.filter { $0.id != "other" }

                ForEach(Array(regularApps.enumerated()), id: \.element.id) { _, app in
                    Button {
                        onOpenWithApp(app.bundleID, isOptionPressed)
                    } label: {
                        HStack {
                            if let bundleID = app.bundleID {
                                appIconView(for: bundleID)
                            }
                            Text(app.isDefault ? "\(app.name) (default)" : app.name)
                        }
                    }

                    if app.isDefault {
                        Divider()
                    }
                }

                Divider()
                Button("Other…") {
                    onOpenWithApp(nil, isOptionPressed)
                }
            } label: {
                Label(isOptionPressed ? "Always Open With" : "Open With", systemImage: "app.badge")
            }
        } else if !item.isDirectory {
            Button {
                onOpenWithApp(nil, isOptionPressed)
            } label: {
                Label(isOptionPressed ? "Always Open With…" : "Open With…", systemImage: "app.badge")
            }
        }

        Divider()

        if let onPutBack = onPutBack {
            Button {
                onPutBack()
            } label: {
                Label("Put Back", systemImage: "trash.slash")
            }

            Button {
                onDeleteImmediately()
            } label: {
                Label("Delete Immediately...", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option])

            Button {
                onEmptyTrash()
            } label: {
                Label("Empty Trash", systemImage: "trash")
            }

            Divider()

            Button {
                onQuickLook()
            } label: {
                Label("Quick Look \"\(item.name)\"", systemImage: "eye")
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button {
                onCopy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command])
        } else {
            Button {
                onMoveToTrash()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [.command])

            Button {
                onDeleteImmediately()
            } label: {
                Label("Delete Immediately...", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option])

            Divider()

            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .keyboardShortcut(.return, modifiers: [])

            if showCompress {
                Button {
                    onCompress()
                } label: {
                    Label(selectedCount == 1 ? "Compress \"\(item.name)\"" : "Compress", systemImage: "doc.zipper")
                }
            }

            Button {
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .keyboardShortcut("d", modifiers: [.command])

            if showExtract {
                Button {
                    onExtract()
                } label: {
                    Label("Extract Archive", systemImage: "doc.zipper")
                }
            }

            Button {
                onQuickLook()
            } label: {
                Label("Quick Look", systemImage: "eye")
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button {
                onCopy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command])

            Button {
                onCut()
            } label: {
                Label("Cut", systemImage: "scissors")
            }
            .keyboardShortcut("x", modifiers: [.command])
        }

        Divider()

        Menu {
            ForEach(FSItemTagUtils.getFavoriteTagNames().filter { !$0.isEmpty }.prefix(7), id: \.self) { tag in
                let colorCode = FSItemTagUtils.getTagNameToColorCodeMapping()[tag] ?? 0
                let tagColor = FSItemTagUtils.getTagColor(colorCode: colorCode)
                let isTagged = item.tags?.contains(where: { $0.name == tag }) ?? false

                Button {
                    onToggleTag(tag)
                } label: {
                    HStack {
                        Image(nsImage: colorCircleImage(color: tagColor, size: 10))
                        Text(isTagged ? "\(tag) ✓" : tag)
                    }
                }
            }
        } label: {
            Label("Tags", systemImage: "tag")
        }
    }

    func sizeText(_ item: FSItem) -> String {
        if item.isDirectory { return "--" }
        return Self.byteFormatter.string(fromByteCount: item.size)
    }

    func dateText(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    func kindText(_ item: FSItem) -> String {
        item.kind
    }

    @ViewBuilder
    func appIconView(for bundleID: String) -> some View {
        if let icon = appIcon(for: bundleID, size: 16) {
            Image(nsImage: icon)
        }
    }

    func appIcon(for bundleID: String, size: CGFloat) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }

        let originalIcon = NSWorkspace.shared.icon(forFile: appURL.path)

        // 원본 이미지를 지정된 크기로 리사이즈
        let resizedIcon = NSImage(size: NSSize(width: size, height: size))
        resizedIcon.lockFocus()
        originalIcon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        resizedIcon.unlockFocus()

        return resizedIcon
    }

    func colorCircleImage(color: Color, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor(color).setFill()
        let path = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size))
        path.fill()
        image.unlockFocus()
        return image
    }
}
