import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct EntryListView: View, Equatable {
    static func == (lhs: EntryListView, rhs: EntryListView) -> Bool {
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
    let layout: ListColumnLayoutUtils
    let applications: [ApplicationInfo]?
    let commonApplications: [ApplicationInfo]?
    let isThumbnailReady: Bool
    let iconSize: CGFloat
    let textSize: CGFloat
    let onSelect: (Bool, Bool) -> Void
    let onOpen: () -> Void
    let onOpenInNewTab: (Bool) -> Void
    let onQuickLook: () -> Void
    let onGetInfo: () -> Void
    let onShare: () -> Void
    let onOpenWithApp: (String?, Bool) -> Void
    let onRenameUpdate: (String) -> Void
    let onRenameCommit: () -> Void
    let onRenameCancel: () -> Void
    let onStartDrag: () -> Void
    let onDrop: ([NSItemProvider], String) -> Void
    let onLoadApplications: () -> Void
    let onLoadCommonApplications: (() -> Void)?
    let onPutBack: (() -> Void)?
    let onMoveToTrash: () -> Void
    let onDeleteImmediately: () -> Void
    let onEmptyTrash: () -> Void
    let onRename: () -> Void
    let onCompress: () -> Void
    let onDuplicate: () -> Void
    let onCreateAlias: () -> Void
    let onExtract: () -> Void
    let onCopy: () -> Void
    let onCopyAbsolutePaths: () -> Void
    let onCopyURLs: () -> Void
    let onCut: () -> Void
    let onToggleTag: (String) -> Void
    let onPerformService: (String) -> Void
    let onRevealInFinder: () -> Void
    let selectedURLs: [URL]
    let isContextMenuTarget: Bool
    let contextMenuTargetWasSelected: Bool
    let onContextMenuOpen: (CGPoint) -> Void
    let selectedCount: Int
    let showCompress: Bool
    let showExtract: Bool
    let draggingPaths: [String]

    @Dependency(\.workspaceClient)
    private var workspaceClient
    @State private var isDropTarget = false
    @FocusState private var isTextFieldFocused: Bool
    @State private var isOptionPressed = false
    @State private var optionKeyTimer: Timer?
    @State private var showTagsEditor = false
    @State private var hasPrefetchedApplications = false
    @State private var serviceNames: [String] = []
    @State private var servicesRequestorView: ServicesMenuRequestorView?

    private func styledText(_ text: String, fontSize: CGFloat, isPrimary: Bool = true) -> some View {
        Text(text)
            .font(.system(size: fontSize))
            .foregroundColor(
                ((isSelected || isDropTarget) && !isRenaming) ? .white : (isPrimary ? .primary : .secondary),
            )
            .opacity(item.isHidden || isCut ? 0.5 : 1.0)
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: layout.outerPadding / 2)

            HStack(spacing: 0) {
                Color.clear
                    .frame(width: layout.outerPadding / 2)

                HStack(spacing: layout.columnSpacing) {
                    HStack(spacing: 8) {
                        ThumbnailView(item: item, displaySize: iconSize, isReady: isThumbnailReady)
                            .opacity(item.isHidden || isCut ? 0.5 : 1.0)
                            .frame(width: iconSize, height: iconSize)
                            .popover(isPresented: $showTagsEditor, arrowEdge: .bottom) {
                                TagsEditorView(
                                    fileName: item.name,
                                    currentTags: item.tags ?? [],
                                    onToggleTag: onToggleTag,
                                )
                            }

                        if isRenaming {
                            TextField("", text: Binding(
                                get: { renamingText },
                                set: { onRenameUpdate($0) },
                            ))
                            .font(.system(size: textSize))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textFieldStyle(.plain)
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
                            .fixedSize(horizontal: true, vertical: false)
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
                            styledText(item.name, fontSize: textSize)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 0)

                        if let tags = item.tags, !tags.isEmpty {
                            OverlappingTagsView(
                                tags: tags,
                                isSelected: (isSelected || isDropTarget) && !isRenaming,
                                showBorderWhenUnselected: true,
                            )
                        }
                    }
                    .frame(width: layout.name, alignment: .leading)

                    styledText(item.formattedModifiedDate, fontSize: max(10, textSize - 1), isPrimary: false)
                        .frame(width: layout.date, alignment: .leading)

                    styledText(item.formattedSize, fontSize: max(10, textSize - 1), isPrimary: false)
                        .frame(width: layout.size, alignment: .trailing)

                    styledText(kindText(item), fontSize: max(10, textSize - 1), isPrimary: false)
                        .frame(width: layout.kind, alignment: .leading)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.vertical, 1)
                .contentShape(Rectangle())
                .onDrag {
                    onStartDrag()
                    let url = URL(fileURLWithPath: item.fullPath)
                    let provider = NSItemProvider(object: url as NSURL)
                    return provider
                }

                Color.clear
                    .frame(width: layout.outerPadding / 2)
            }
            .background(
                ((isSelected || isDropTarget) && !isRenaming)
                    ? Color(nsColor: .selectedContentBackgroundColor)
                    : Color.clear,
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isContextMenuTarget
                            ? (contextMenuTargetWasSelected ? Color.white : Color.accentColor)
                            : Color.clear,
                        lineWidth: isContextMenuTarget ? 1 : 0,
                    ),
            )

            Color.clear
                .frame(width: layout.outerPadding / 2)
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
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDropTarget ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear),
            )
        }
        .contextMenu {
            EntryContextMenuContent(
                item: item,
                selectedCount: selectedCount,
                isOptionPressed: isOptionPressed,
                applications: applications,
                commonApplications: commonApplications,
                onOpen: onOpen,
                onOpenInNewTab: onOpenInNewTab,
                onOpenWithApp: onOpenWithApp,
                onLoadApplications: onLoadApplications,
                onLoadCommonApplications: onLoadCommonApplications,
                onPutBack: onPutBack,
                onMoveToTrash: onMoveToTrash,
                onDeleteImmediately: onDeleteImmediately,
                onEmptyTrash: onEmptyTrash,
                onRename: onRename,
                onCompress: onCompress,
                onDuplicate: onDuplicate,
                onCreateAlias: onCreateAlias,
                onExtract: onExtract,
                onQuickLook: onQuickLook,
                onGetInfo: onGetInfo,
                onShare: onShare,
                onCopy: onCopy,
                onCopyAbsolutePaths: onCopyAbsolutePaths,
                onCopyURLs: onCopyURLs,
                onCut: onCut,
                onPerformService: onPerformService,
                onRevealInFinder: onRevealInFinder,
                serviceNames: serviceNames,
                refreshServicesMenuItems: refreshServicesMenuItems,
                showCompress: showCompress,
                showExtract: showExtract,
                onToggleTag: onToggleTag,
                showTagsEditor: $showTagsEditor,
                appIcon: { appIcon(for: $0, size: 16) },
                tagColorImage: { color, size in colorCircleImage(color: color, size: size) },
            )
        }
        .overlay(
            RightClickCaptureView(onRightClick: onContextMenuOpen)
                .allowsHitTesting(false),
        )
        .background(
            ServicesMenuRequestorRepresentable(
                selectedURLs: selectedURLs,
                onViewReady: { servicesRequestorView = $0 },
            )
            .frame(width: 0, height: 0),
        )
        .onHover { isHovering in
            guard isHovering, !hasPrefetchedApplications else { return }
            guard !item.isDirectory, applications == nil else { return }
            hasPrefetchedApplications = true
            onLoadApplications()
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

    private func refreshServicesMenuItems() {
        if let servicesRequestorView, let window = servicesRequestorView.window {
            window.makeFirstResponder(servicesRequestorView)
        }
        NSApp.registerServicesMenuSendTypes([.fileURL], returnTypes: [])
        NSApp.servicesMenu?.update()

        let items = NSApp.servicesMenu?.items ?? []
        var seen = Set<String>()
        serviceNames = items.compactMap { item in
            guard !item.isSeparatorItem else { return nil }
            guard item.isEnabled else { return nil }
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, seen.insert(title).inserted else { return nil }
            return title
        }
    }
}

private struct RightClickCaptureView: NSViewRepresentable {
    let onRightClick: (CGPoint) -> Void

    func makeNSView(context _: Context) -> CaptureView {
        let view = CaptureView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: CaptureView, context _: Context) {
        nsView.onRightClick = onRightClick
    }

    @MainActor
    final class CaptureView: NSView {
        var onRightClick: ((CGPoint) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                let location = convert(event.locationInWindow, from: nil)
                if bounds.contains(location) {
                    onRightClick?(event.locationInWindow)
                }
                return event
            }
        }

        deinit {
            MainActor.assumeIsolated {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
        }
    }
}

private extension EntryListView {
    func kindText(_ item: Entry) -> String {
        if item.fileExtension.lowercased() == "voycoll" {
            return "Voyager Collection"
        }
        return item.kind
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
