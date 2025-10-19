import SwiftUI

struct PathBreadcrumbView: View {
    let pathComponents: [(name: String, fullPath: String)]
    let onNavigate: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
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

                if index < pathComponents.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
