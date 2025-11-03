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
    let onQuickLook: () -> Void
    let onOpenWithApp: (String?) -> Void
    let onSetDefaultApp: (String, UTType?) -> Void
    let onSetDefaultAppWithOther: () -> Void
    let onRenameUpdate: (String) -> Void
    let onRenameCommit: () -> Void
    let onRenameCancel: () -> Void
    let onStartDrag: () -> Void
    let onDrop: (String) -> Void
    let onLoadApplications: () -> Void

    @State private var isDropTarget = false
    @FocusState private var isTextFieldFocused: Bool

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
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue, lineWidth: isDropTarget ? 2 : 0)
            )
        }
        .contextMenu {
            let task = Task {
                if !item.isDirectory && applications == nil {
                    onLoadApplications()
                }
            }

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
        return Self.byteFormatter.string(fromByteCount: item.size)
    }

    private func dateText(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
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
