import AppKit
import SwiftUI

// swiftlint:disable attributes

struct EntryContextMenuContent: View {
    let item: Entry
    let selectedCount: Int
    let isOptionPressed: Bool
    let applications: [ApplicationInfo]?
    let commonApplications: [ApplicationInfo]?
    let onOpen: () -> Void
    let onOpenInNewTab: ((Bool) -> Void)?
    let onOpenWithApp: ((String?, Bool) -> Void)?
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
    let onQuickLook: (() -> Void)?
    let onGetInfo: (() -> Void)?
    let onShare: (() -> Void)?
    let onCopy: (() -> Void)?
    let onCopyAbsolutePaths: (() -> Void)?
    let onCopyURLs: (() -> Void)?
    let onCut: (() -> Void)?
    let onPerformService: ((String) -> Void)?
    let onRevealInFinder: (() -> Void)?
    let serviceNames: [String]
    let refreshServicesMenuItems: () -> Void
    let showCompress: Bool
    let showExtract: Bool
    let onToggleTag: ((String) -> Void)?
    @Binding var showTagsEditor: Bool
    let appIcon: (String) -> NSImage?
    let tagColorImage: (Color, CGFloat) -> NSImage

    private var appsToShow: [ApplicationInfo]? {
        selectedCount > 1 ? commonApplications : applications
    }

    private var isInTrash: Bool {
        onPutBack != nil
    }

    var body: some View {
        openSection
        openWithSection
        Divider()

        if isInTrash {
            trashActionsSection
        } else {
            regularActionsSection
        }

        Divider()
        tagsSection
    }

    @ViewBuilder
    private var openSection: some View {
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
    }

    @ViewBuilder
    private var openWithSection: some View {
        if !item.isDirectory, let onOpenWithApp {
            Menu {
                if let apps = appsToShow, !apps.isEmpty {
                    let regularApps = apps.filter { $0.id != "other" }

                    ForEach(Array(regularApps.enumerated()), id: \.element.id) { _, app in
                        Button {
                            onOpenWithApp(app.bundleID, isOptionPressed)
                        } label: {
                            HStack {
                                if let bundleID = app.bundleID {
                                    if let icon = appIcon(bundleID) {
                                        Image(nsImage: icon)
                                    }
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
    }

    @ViewBuilder
    private var trashActionsSection: some View {
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

        quickLookButton(showItemName: true)
        getInfoButton
        shareButton
        servicesSection

        Divider()

        copySection
    }

    @ViewBuilder
    private var regularActionsSection: some View {
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

        quickLookButton(showItemName: false)
        getInfoButton
        shareButton
        servicesSection

        Divider()

        copySection

        if let onCut {
            Button {
                onCut()
            } label: {
                Label("Cut", systemImage: "scissors")
            }
            .keyboardShortcut("x", modifiers: [.command])
        }
    }
}

// swiftlint:enable attributes
