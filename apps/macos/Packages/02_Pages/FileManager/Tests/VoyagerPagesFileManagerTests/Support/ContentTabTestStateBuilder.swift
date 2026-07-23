@testable import VoyagerPagesFileManager

enum ContentTabTestStateBuilder {
    /// 핀 생성 시점의 디렉토리 metadata와 record를 가진 window 상태를 만든다.
    static func pinnedDirectoryWindowState(
        tabID: ContentTabID,
        path: String,
        record: ContentTabPinnedRecord,
    ) -> FileManagerFeature.State {
        let anchor = ContentTabPageAnchor.directory(path: path)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .directory,
                    anchor: anchor,
                    isPinned: true,
                    title: record.title,
                    iconName: record.iconName,
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
            pinnedRecords: [tabID: record],
        )
        state.content.navigation.seedInitialFolderPath(path)
        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()
        return state
    }
}
