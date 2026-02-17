import ComposableArchitecture

@Reducer
struct FileManagerContentFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    var body: some Reducer<State, Action> {
        Scope(state: \.composer, action: \.composer) {
            ComposerFeature()
        }

        Scope(state: \.entryViewLayout, action: \.entryViewLayout) {
            EntryViewLayoutFeature()
        }

        Scope(state: \.entryOperations, action: \.entryOperations) {
            EntryOperationsFeature()
        }

        Scope(state: \.self, action: \.entryArrangements) {
            EntryArrangementsFeature()
        }
        FileManagerContentEntryFeature()
        FileManagerContentEntryAppearanceFeature()
        FileManagerContentEntryOperationsFeature()
        FileManagerContentEntryThumbnailFeature()
        FileManagerContentComposerFeature()
        FileManagerContentLayoutRoutingFeature()
        FileManagerContentCollectionDraftFeature()
        FileManagerContentWindowBridgeFeature()
    }
}
