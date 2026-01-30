import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct EntryGridView: View, Equatable {
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
    let onGetInfo: (() -> Void)?
    let onShare: (() -> Void)?
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
    let onPerformService: ((String) -> Void)?
    let onRevealInFinder: (() -> Void)?
    let selectedURLs: [URL]
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
    @State private var serviceNames: [String] = []
    @State private var servicesRequestorView: ServicesMenuRequestorView?
    @State private var shouldFocusRename = false
    @State private var renameTextWidth: CGFloat = 120

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
        .background(
            ServicesMenuRequestorRepresentable(
                selectedURLs: selectedURLs,
                onViewReady: { servicesRequestorView = $0 },
            )
            .frame(width: 0, height: 0),
        )
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
    func refreshServicesMenuItems() {
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

// swiftlint:enable vertical_whitespace_closing_braces
