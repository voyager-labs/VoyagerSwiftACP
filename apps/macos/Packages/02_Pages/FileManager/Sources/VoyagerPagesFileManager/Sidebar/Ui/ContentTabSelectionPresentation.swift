struct ContentTabSelectionPresentation: Equatable {
    let selectedTabIDs: Set<ContentTabID>

    func isSelected(_ tabID: ContentTabID) -> Bool {
        selectedTabIDs.contains(tabID)
    }
}
