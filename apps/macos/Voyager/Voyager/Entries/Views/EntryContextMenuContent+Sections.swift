import AppKit
import SwiftUI

// swiftlint:disable attributes

extension EntryContextMenuContent {
    @ViewBuilder
    func quickLookButton(showItemName: Bool) -> some View {
        if let onQuickLook {
            Button {
                onQuickLook()
            } label: {
                Label(showItemName ? "Quick Look \"\(item.name)\"" : "Quick Look", systemImage: "eye")
            }
            .keyboardShortcut(.space, modifiers: [])
        }
    }

    @ViewBuilder
    var getInfoButton: some View {
        if let onGetInfo {
            Button {
                onGetInfo()
            } label: {
                Label("Get Info", systemImage: "info.circle")
            }
            .keyboardShortcut("i", modifiers: [.command])
        }
    }

    @ViewBuilder
    var shareButton: some View {
        if let onShare {
            Button {
                onShare()
            } label: {
                Label("Share...", systemImage: "square.and.arrow.up")
            }
        }
    }

    @ViewBuilder
    var servicesSection: some View {
        if let onPerformService {
            Menu {
                if serviceNames.isEmpty {
                    Button("No Services") {}
                        .disabled(true)
                } else {
                    ForEach(serviceNames, id: \.self) { name in
                        Button(name) {
                            onPerformService(name)
                        }
                    }
                }
            } label: {
                Label("Services", systemImage: "gearshape")
            }
            .onAppear {
                refreshServicesMenuItems()
            }

            if let onRevealInFinder {
                Button {
                    onRevealInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "sidebar.right")
                }
            }
        }
    }

    @ViewBuilder
    var copySection: some View {
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
    }

    @ViewBuilder
    var tagsSection: some View {
        Menu {
            ForEach(EntryTagUtils.getFavoriteTagNames().filter { !$0.isEmpty }.prefix(7), id: \.self) { tag in
                let colorCode = EntryTagUtils.getTagNameToColorCodeMapping()[tag] ?? 0
                let tagColor = EntryTagUtils.getTagColor(colorCode: colorCode)
                let isTagged = item.tags?.contains(where: { $0.name == tag }) ?? false

                Button {
                    onToggleTag?(tag)
                } label: {
                    HStack {
                        Image(nsImage: tagColorImage(tagColor, 10))
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
}

// swiftlint:enable attributes
