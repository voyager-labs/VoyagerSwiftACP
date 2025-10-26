import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FSItemListView: View {
    let item: FSItem
    let isSelected: Bool
    let availableWidth: CGFloat
    let applications: [ApplicationInfo]?
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onQuickLook: () -> Void
    let onOpenWithApp: (String?) -> Void
    let onSetDefaultApp: (String, UTType?) -> Void
    let onSetDefaultAppWithOther: () -> Void

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

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundColor(item.isDirectory ? .blue : .gray)
                    .opacity(item.isHidden ? 0.5 : 1.0)
                    .frame(width: 20)

                Text(item.name)
                    .font(.system(size: 13))
                    .opacity(item.isHidden ? 0.5 : 1.0)
                    .lineLimit(1)
            }
            .frame(width: columnWidths.name, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.leading, 8)

            Text(dateText(item.modifiedDate))
                .font(.system(size: 12))
                .opacity(item.isHidden ? 0.5 : 1.0)
                .frame(width: columnWidths.date, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.leading, 8)

            Text(sizeText(item))
                .font(.system(size: 12))
                .opacity(item.isHidden ? 0.5 : 1.0)
                .frame(width: columnWidths.size, alignment: .trailing)
                .padding(.vertical, 6)
                .padding(.trailing, 8)

            Text(kindText(item))
                .font(.system(size: 12))
                .opacity(item.isHidden ? 0.5 : 1.0)
                .frame(width: columnWidths.kind, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.leading, 8)
        }
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
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
        .contextMenu {
            Button("Open") {
                onOpen()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command])

            Button("Quick Look") {
                onQuickLook()
            }
            .keyboardShortcut(.space, modifiers: [])

            if let apps = applications, !apps.isEmpty {
                Menu("Open With") {
                    let regularApps = apps.filter { $0.id != "other" }

                    ForEach(Array(regularApps.enumerated()), id: \.element.id) { _, app in
                        Button {
                            onOpenWithApp(app.bundleID)
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
                        onOpenWithApp(nil)
                    }
                }
            } else if !item.isDirectory {
                Button("Open With…") {
                    onOpenWithApp(nil)
                }
            }

            if !item.isDirectory, let apps = applications {
                Menu("Set Default App") {
                    let fileType = UTType(filenameExtension: item.fileExtension)
                    let regularApps = apps.filter { $0.bundleID != nil && $0.id != "other" }

                    ForEach(Array(regularApps.enumerated()), id: \.element.id) { _, app in
                        Button {
                            if let bundleID = app.bundleID {
                                onSetDefaultApp(bundleID, fileType)
                            }
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
                        onSetDefaultAppWithOther()
                    }
                }
            }
        }
    }

    private func sizeText(_ item: FSItem) -> String {
        if item.isDirectory { return "--" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: item.size)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func kindText(_ item: FSItem) -> String {
        item.kind
    }

    @ViewBuilder
    private func appIconView(for bundleID: String) -> some View {
        if let icon = appIcon(for: bundleID, size: 16) {
            Image(nsImage: icon)
        }
    }

    private func appIcon(for bundleID: String, size: CGFloat) -> NSImage? {
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
}
