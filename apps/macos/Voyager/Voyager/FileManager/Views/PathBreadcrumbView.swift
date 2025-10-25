import SwiftUI

struct PathBreadcrumbView: View {
    let pathComponents: [(name: String, fullPath: String)]
    let onNavigate: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            if pathComponents.isEmpty {
                Text("")
                    .font(.system(size: 13))
                    .opacity(0)
            } else {
                ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, item in
                    Button {
                        onNavigate(item.fullPath)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: index == 0 ? "externaldrive.fill" : "folder.fill")
                                .font(.system(size: 12))
                                .foregroundColor(index == 0 ? .secondary : .blue)

                            Text(item.name)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.borderless)
                    .help(item.fullPath)
                    .contextMenu {
                        Button {
                            AppDelegate.shared?.createNewTab(path: item.fullPath)
                        } label: {
                            Text("Open in New Tab")
                        }

                        Button {
                            let parentPath = URL(fileURLWithPath: item.fullPath).deletingLastPathComponent().path
                            onNavigate(parentPath)
                        } label: {
                            Text("Show in Enclosing Folder")
                        }
                        .disabled(item.fullPath == "/")
                    }

                    if index < pathComponents.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(minHeight: 20)
    }
}
