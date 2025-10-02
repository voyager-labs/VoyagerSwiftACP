import AppKit
import SwiftUI

/// 파일 브라우저 뷰
struct FileBrowserView: View {
    let tabId: UUID
    let initialPath: String
    let savedCurrentPath: String?
    @EnvironmentObject var tabManager: TabManager
    @State private var currentPath: String = ""
    @State private var folderContents: [FileItemModel] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // 경로 표시 바
            pathBar

            Divider()

            // 폴더 내용 목록
            if isLoading {
                Spacer()
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Spacer()
            } else {
                folderList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // 탭별로 독립적인 상태 초기화
            let targetPath = savedCurrentPath ?? initialPath
            if currentPath.isEmpty || currentPath != targetPath {
                currentPath = targetPath
                folderContents = []
                isLoading = false
                loadFolderContents()
            }
        }
        .onChange(of: currentPath) { _, newPath in
            loadFolderContents()
            updateTabContent(currentPath: newPath, initialPath: initialPath)
        }
    }

    private var pathBar: some View {
        HStack {
            // 홈 버튼
            Button(action: {
                currentPath = NSHomeDirectory()
            }, label: {
                Image(systemName: "house.fill")
                    .foregroundColor(.blue)
            })
            .buttonStyle(.plain)

            // 뒤로가기 버튼
            Button(action: goBack, label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(.secondary)
            })
            .buttonStyle(.plain)
            .disabled(currentPath == NSHomeDirectory())

            // 경로 표시
            Text(currentPath)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var folderList: some View {
        List(folderContents, id: \.name) { item in
            FileItemRowView(item: item) {
                if item.isDirectory {
                    currentPath = item.fullPath
                } else {
                    // 파일 열기
                    NSWorkspace.shared.open(URL(fileURLWithPath: item.fullPath))
                }
            }
        }
        .listStyle(.inset)
    }

    private func loadFolderContents() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let contents = getFolderContents(at: currentPath)

            DispatchQueue.main.async {
                self.folderContents = contents
                self.isLoading = false
            }
        }
    }

    private func getFolderContents(at path: String) -> [FileItemModel] {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                options: [.skipsHiddenFiles]
            )

            let items = contents.map { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return FileItemModel(
                    name: url.lastPathComponent,
                    fullPath: url.path,
                    isDirectory: isDirectory
                )
            }

            // 폴더를 먼저, 파일을 나중에 표시
            return items.sorted { first, second in
                if first.isDirectory != second.isDirectory {
                    return first.isDirectory
                }
                return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            }
        } catch {
            return []
        }
    }

    private func goBack() {
        let parentPath = (currentPath as NSString).deletingLastPathComponent
        if parentPath != currentPath {
            currentPath = parentPath
        }
    }

    /// 탭의 현재 상태를 TabViewModel에 업데이트
    private func updateTabContent(currentPath: String, initialPath: String) {
        guard let tab = tabManager.tabs.first(where: { $0.id == tabId }) else { return }

        // 현재 경로 업데이트
        let savedPath = currentPath != initialPath ? currentPath : initialPath
        tab.updatePath(savedPath)

        // TabManager를 통해 탭 제목 업데이트
        tabManager.updateTabTitle(id: tabId, currentPath: currentPath)
    }
}
