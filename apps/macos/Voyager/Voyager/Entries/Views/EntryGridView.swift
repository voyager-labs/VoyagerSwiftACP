// swiftlint:disable file_length
import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct EntryGridView: View, Equatable {
    static func == (lhs: EntryGridView, rhs: EntryGridView) -> Bool {
        // Entry의 Equatable 구현을 활용
        lhs.item == rhs.item &&
            lhs.isSelected == rhs.isSelected &&
            lhs.isCut == rhs.isCut &&
            lhs.isRenaming == rhs.isRenaming &&
            lhs.isThumbnailReady == rhs.isThumbnailReady &&
            lhs.iconSize == rhs.iconSize &&
            lhs.textSize == rhs.textSize
    }

    let item: Entry
    let isSelected: Bool
    let isCut: Bool
    let isRenaming: Bool
    let renamingText: String
    let isThumbnailReady: Bool
    let applications: [ApplicationInfo]?
    let iconSize: CGFloat
    let textSize: CGFloat
    let commonApplications: [ApplicationInfo]?
    let onSelect: (Bool, Bool) -> Void // (isCommandPressed, isShiftPressed)
    let onOpen: () -> Void
    let onOpenInNewTab: ((Bool) -> Void)?
    let onQuickLook: (() -> Void)?
    let onOpenWithApp: ((String?, Bool) -> Void)?
    let onRenameUpdate: (String) -> Void
    let onRenameCommit: () -> Void
    let onRenameCancel: () -> Void
    let onStartDrag: () -> Void
    let onDrop: ([NSItemProvider], String) -> Void
    let onLoadApplications: (() -> Void)?
    let onLoadCommonApplications: (() -> Void)?
    let onPutBack: (() -> Void)?
    let onMoveToTrash: (() -> Void)?
    let onDeleteImmediately: (() -> Void)?
    let onEmptyTrash: (() -> Void)?
    let onRename: (() -> Void)?
    let onCompress: (() -> Void)?
    let onDuplicate: (() -> Void)?
    let onCreateAlias: (() -> Void)?
    let onExtract: (() -> Void)?
    let onCopy: (() -> Void)?
    let onCopyAbsolutePaths: (() -> Void)?
    let onCopyURLs: (() -> Void)?
    let onCut: (() -> Void)?
    let onToggleTag: ((String) -> Void)?
    let selectedCount: Int
    let showCompress: Bool
    let showExtract: Bool
    let draggingPaths: [String]

    @Dependency(\.workspaceClient)
    private var workspaceClient
    @State private var isDropTarget = false
    @State private var isOptionPressed = false
    @State private var optionKeyTimer: Timer?
    @State private var showTagsEditor = false
    @State private var hasPrefetchedApplications = false
    @State private var shouldFocusRename = false
    @State private var renameTextWidth: CGFloat = 120

    private struct RenameTextWidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 120
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    var body: some View {
        VStack(spacing: 1) {
            ThumbnailView(item: item, displaySize: iconSize, isReady: isThumbnailReady)
                .opacity(item.isHidden || isCut ? 0.5 : 1.0)
                .frame(width: iconSize, height: iconSize)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((isSelected || isDropTarget) ? Color.gray.opacity(0.2) : Color.clear),
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ItemPositionKey.self,
                            value: [item.id + "_icon": geo.frame(in: .named("contentPane"))],
                        )
                    },
                )

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    let font = NSFont.systemFont(ofSize: textSize)
                    let lineHeight = ceil(font.ascender - font.descender + font.leading)
                    let tagYOffset = max(0, (lineHeight - 8) / 2)

                    HStack(alignment: .top, spacing: 4) {
                        if let tags = item.tags, !tags.isEmpty {
                            OverlappingTagsView(
                                tags: tags,
                                isSelected: (isSelected || isDropTarget) && !isRenaming,
                                showBorderWhenUnselected: false,
                            )
                            .padding(.top, tagYOffset)
                        }

                        if isRenaming {
                            AutoSizingTextView(
                                text: Binding(
                                    get: { renamingText },
                                    set: { onRenameUpdate($0) },
                                ),
                                font: NSFont.systemFont(ofSize: textSize),
                                textAlignment: .center,
                                availableWidth: renameTextWidth,
                                shouldFocus: shouldFocusRename,
                                onCommit: onRenameCommit,
                                onCancel: onRenameCancel,
                            )
                            .frame(maxWidth: .infinity)
                            .layoutPriority(1)
                            .padding(.horizontal, 0)
                            .padding(.vertical, 0)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(nsColor: .textBackgroundColor)),
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 1),
                            )
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(key: RenameTextWidthKey.self, value: proxy.size.width)
                                },
                            )
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    shouldFocusRename = true
                                }
                            }
                        } else {
                            Text(item.name)
                                .font(.system(size: textSize))
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .multilineTextAlignment(.center)
                                .opacity(item.isHidden || isCut ? 0.5 : 1.0)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .popover(isPresented: $showTagsEditor, arrowEdge: .bottom) {
                        TagsEditorView(
                            fileName: item.name,
                            currentTags: item.tags ?? [],
                            onToggleTag: { tag in
                                onToggleTag?(tag)
                            },
                        )
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                ((isSelected || isDropTarget) && !isRenaming)
                                    ? Color(nsColor: .selectedContentBackgroundColor)
                                    : Color.clear,
                            ),
                    )
                    .foregroundColor(((isSelected || isDropTarget) && !isRenaming) ? .white : .primary)
                    .contentShape(RoundedRectangle(cornerRadius: 4))

                    if let additionalInfo = item.additionalInfo {
                        Text(additionalInfo)
                            .font(.system(size: max(8, textSize - 1)))
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ItemPositionKey.self,
                            value: [item.id + "_text": geo.frame(in: .named("contentPane"))],
                        )
                    },
                )
                .frame(minHeight: 50, alignment: .top)
            }
            .frame(width: 120)
            .padding(.horizontal, 4)
        }
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    let currentEvent = NSApp.currentEvent
                    let isCommandPressed = currentEvent?.modifierFlags.contains(.command) ?? false
                    let isShiftPressed = currentEvent?.modifierFlags.contains(.shift) ?? false
                    onSelect(isCommandPressed, isShiftPressed)
                },
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    onOpen()
                },
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
                delegate: EntryDropDelegate(
                    item: item,
                    onDrop: onDrop,
                    isDropTarget: $isDropTarget,
                    draggingPaths: draggingPaths,
                ),
            )
        }
        .contextMenu {
            contextMenuContent
        }
        .onHover { isHovering in
            guard isHovering, !hasPrefetchedApplications else { return }
            guard !item.isDirectory, applications == nil else { return }
            hasPrefetchedApplications = true
            onLoadApplications?()
        }
        .onAppear {
            startOptionKeyMonitoring()
        }
        .onPreferenceChange(RenameTextWidthKey.self) { width in
            if abs(width - renameTextWidth) > 0.5 {
                renameTextWidth = width
            }
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

private extension EntryGridView {
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
            if selectedCount > 1, commonApplications == nil {
                onLoadCommonApplications?()
            } else if !item.isDirectory, applications == nil {
                onLoadApplications?()
            }
        }

        if item.isDirectory, let onOpenInNewTab {
            Button {
                onOpenInNewTab(isOptionPressed)
            } label: {
                Label("Open in New Window", systemImage: "macwindow.badge.plus")
            }
        }

        if !item.isDirectory, let onOpenWithApp {
            let appsToShow = selectedCount > 1 ? commonApplications : applications

            Menu {
                if let apps = appsToShow, !apps.isEmpty {
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
                } else {
                    Button("Loading…") {}
                        .disabled(true)
                }

                Divider()
                Button("Other…") {
                    onOpenWithApp(nil, isOptionPressed)
                }
            } label: {
                Label(isOptionPressed ? "Always Open With" : "Open With", systemImage: "app.badge")
            }
            .onAppear {
                if appsToShow == nil {
                    if selectedCount > 1 {
                        onLoadCommonApplications?()
                    } else {
                        onLoadApplications?()
                    }
                }
            }
        }

        Divider()

        if onPutBack != nil {
            if let onDeleteImmediately {
                Button {
                    onDeleteImmediately()
                } label: {
                    Label("Delete Immediately...", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
            }

            if let onEmptyTrash {
                Button {
                    onEmptyTrash()
                } label: {
                    Label("Empty Trash", systemImage: "trash")
                }
            }

            Divider()

            if let onQuickLook {
                Button {
                    onQuickLook()
                } label: {
                    Label("Quick Look \"\(item.name)\"", systemImage: "eye")
                }
                .keyboardShortcut(.space, modifiers: [])
            }

            if let onGetInfo {
                Button {
                    onGetInfo()
                } label: {
                    Label("Get Info", systemImage: "info.circle")
                }
                .keyboardShortcut("i", modifiers: [.command])
            }

            Divider()

            if let onCopy {
                Button {
                    onCopy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command])
            }

            if let onCopyAbsolutePaths {
                Button {
                    onCopyAbsolutePaths()
                } label: {
                    Label(
                        selectedCount == 1 ? "Copy Absolute Path" : "Copy Absolute Paths",
                        systemImage: "doc.on.clipboard",
                    )
                }
            }

            if let onCopyURLs {
                Button {
                    onCopyURLs()
                } label: {
                    Label(selectedCount == 1 ? "Copy URL" : "Copy URLs", systemImage: "link")
                }
            }
        } else {
            if let onMoveToTrash {
                Button {
                    onMoveToTrash()
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [.command])
            }

            if let onDeleteImmediately {
                Button {
                    onDeleteImmediately()
                } label: {
                    Label("Delete Immediately...", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
            }

            Divider()

            if let onRename {
                Button {
                    onRename()
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .keyboardShortcut(.return, modifiers: [])
            }

            if showCompress, let onCompress {
                Button {
                    onCompress()
                } label: {
                    Label(selectedCount == 1 ? "Compress \"\(item.name)\"" : "Compress", systemImage: "doc.zipper")
                }
            }

            if let onDuplicate {
                Button {
                    onDuplicate()
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .keyboardShortcut("d", modifiers: [.command])
            }

            if let onCreateAlias {
                Button {
                    onCreateAlias()
                } label: {
                    Label("Make Alias", systemImage: "arrowshape.turn.up.right")
                }
            }

            if showExtract, let onExtract {
                Button {
                    onExtract()
                } label: {
                    Label("Extract Archive", systemImage: "doc.zipper")
                }
            }

            if let onQuickLook {
                Button {
                    onQuickLook()
                } label: {
                    Label("Quick Look", systemImage: "eye")
                }
                .keyboardShortcut(.space, modifiers: [])
            }

            Divider()

            if let onCopy {
                Button {
                    onCopy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command])
            }

            if let onCopyAbsolutePaths {
                Button {
                    onCopyAbsolutePaths()
                } label: {
                    Label(
                        selectedCount == 1 ? "Copy Absolute Path" : "Copy Absolute Paths",
                        systemImage: "doc.on.clipboard",
                    )
                }
            }

            if let onCopyURLs {
                Button {
                    onCopyURLs()
                } label: {
                    Label(selectedCount == 1 ? "Copy URL" : "Copy URLs", systemImage: "link")
                }
            }

            if let onCut {
                Button {
                    onCut()
                } label: {
                    Label("Cut", systemImage: "scissors")
                }
                .keyboardShortcut("x", modifiers: [.command])
            }
        }

        Divider()

        Menu {
            ForEach(EntryTagUtils.getFavoriteTagNames().filter { !$0.isEmpty }.prefix(7), id: \.self) { tag in
                let colorCode = EntryTagUtils.getTagNameToColorCodeMapping()[tag] ?? 0
                let tagColor = EntryTagUtils.getTagColor(colorCode: colorCode)
                let isTagged = item.tags?.contains(where: { $0.name == tag }) ?? false

                Button {
                    onToggleTag?(tag)
                } label: {
                    HStack {
                        Image(nsImage: colorCircleImage(color: tagColor, size: 10))
                        Text(isTagged ? "\(tag) ✓" : tag)
                    }
                }
            }

            Divider()

            Button("Edit Tags...") {
                showTagsEditor = true
            }
        } label: {
            Label("Tags", systemImage: "tag")
        }
    }

    @ViewBuilder
    func appIconView(for bundleID: String) -> some View {
        if let icon = appIcon(for: bundleID, size: 16) {
            Image(nsImage: icon)
        }
    }

    func appIcon(for bundleID: String, size: CGFloat) -> NSImage? {
        guard let appURL = workspaceClient.urlForApplication(bundleID) else {
            return nil
        }
        let originalIcon = workspaceClient.iconForFile(appURL.path)

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

extension View {
    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// swiftlint:enable file_length
