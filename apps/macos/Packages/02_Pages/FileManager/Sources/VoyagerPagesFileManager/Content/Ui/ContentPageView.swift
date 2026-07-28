import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryOperations
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

enum ContentPagePresentationPolicy: Equatable {
    case entries
    case ordinaryDirectoryLoadingOverlay
    case collectionReplacementLoading

    var replacesEntriesWithLoading: Bool {
        self == .collectionReplacementLoading
    }

    var showsInputBlocker: Bool {
        self == .ordinaryDirectoryLoadingOverlay
    }

    var allowsEntryInteraction: Bool {
        self != .ordinaryDirectoryLoadingOverlay
    }

    var hidesEntriesFromAccessibility: Bool {
        self == .ordinaryDirectoryLoadingOverlay
    }

    var requiresKeyCommandFocus: Bool {
        self == .ordinaryDirectoryLoadingOverlay
    }

    var allowsKeyboardCommandDispatch: Bool {
        self != .ordinaryDirectoryLoadingOverlay
    }

    static func resolve(
        isCollectionSearching: Bool,
        isCollectionContentLoading: Bool,
        isEntryLoading: Bool,
        isCollectionMode: Bool,
    ) -> Self {
        if isCollectionSearching || isCollectionContentLoading {
            return .collectionReplacementLoading
        }
        if isEntryLoading, !isCollectionMode {
            return .ordinaryDirectoryLoadingOverlay
        }
        return .entries
    }
}

struct ContentPageView: View {
    let store: StoreOf<FileManagerContentFeature>

    @StateObject private var contextMenuCoordinatorHolder: ContentPaneContextMenuCoordinatorHolder

    @Environment(\.fileManagerKeyCommandFocusCoordinator)
    private var keyCommandFocusCoordinator
    @FocusState var isKeyCommandFocused: Bool

    init(store: StoreOf<FileManagerContentFeature>) {
        self.store = store
        _contextMenuCoordinatorHolder = StateObject(
            wrappedValue: ContentPaneContextMenuCoordinatorHolder(store: store),
        )
    }

    private var presentationPolicy: ContentPagePresentationPolicy {
        .resolve(
            isCollectionSearching: store.composer.isCollectionSearching,
            isCollectionContentLoading: store.entryViewLayout.isCollectionContentLoading,
            isEntryLoading: store.entryOperations.isLoading,
            isCollectionMode: store.isCollectionMode,
        )
    }

    private var mainContent: some View {
        ZStack {
            entryView
                .allowsHitTesting(presentationPolicy.allowsEntryInteraction)
                .accessibilityHidden(presentationPolicy.hidesEntriesFromAccessibility)
            keyCommandOverlay
            if presentationPolicy.showsInputBlocker {
                inputBlocker
            }
        }
    }

    @ViewBuilder private var entryView: some View {
        if presentationPolicy.replacesEntriesWithLoading {
            loadingView
        } else {
            let entryViewLayoutStore = store.scope(state: \.entryViewLayout, action: \.entryViewLayout)
            let menuProvider = makeBlankSpaceMenuProvider()
            switch store.entryViewLayout.mode {
            case .list:
                EntryListViewRepresentable(store: entryViewLayoutStore, blankSpaceMenuProvider: menuProvider)
            case .grid:
                EntryGridViewRepresentable(store: entryViewLayoutStore, blankSpaceMenuProvider: menuProvider)
            }
        }
    }

    private var keyCommandOverlay: some View {
        KeyCommandView(
            onViewCreated: { [weak keyCommandFocusCoordinator] view in
                keyCommandFocusCoordinator?.register(view)
            },
            onKeyDown: { event in
                handleKeyboardEvent(event)
            },
        )
        .focusable()
        .focused($isKeyCommandFocused)
        .allowsHitTesting(false)
    }

    private var backgroundInteractionLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .contextMenu {
                ContentPaneContextMenu(store: store)
            }
            .onTapGesture {
                guard store.entryOperations.renamingItemId == nil else { return }
                restoreKeyCommandFocus()
            }
    }

    private var inputBlocker: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .allowsHitTesting(true)
    }

    private var loadingView: some View {
        GeometryReader { _ in
            ZStack {
                Color.clear

                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }

    var body: some View {
        mainContent
            .onChange(of: presentationPolicy) { policy in
                guard policy.requiresKeyCommandFocus else { return }
                restoreKeyCommandFocus()
            }
            .onAppear {
                store.send(.internal(.startObservingSystemNotifications))
                guard store.entryOperations.renamingItemId == nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    restoreKeyCommandFocus()
                }
            }
            .onDisappear {
                store.send(.internal(.stopObservingSystemNotifications))
            }
            .background(backgroundInteractionLayer)
    }

    private func handleKeyboardEvent(_ event: NSEvent) {
        guard presentationPolicy.allowsKeyboardCommandDispatch else { return }

        let command = KeyCommand(
            keyCode: event.keyCode,
            modifiers: KeyModifiers(event.modifierFlags),
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
        )
        store.send(.view(.handleKeyCommand(command)))
    }

    private func restoreKeyCommandFocus() {
        isKeyCommandFocused = true
        keyCommandFocusCoordinator?.requestFocus()
    }

    private func makeBlankSpaceMenuProvider() -> (() -> NSMenu)? {
        let coordinator = contextMenuCoordinatorHolder.coordinator
        return { [coordinator] in
            ContentPaneContextMenuBuilder.makeMenu(
                configuration: coordinator.configuration,
                target: coordinator,
            )
        }
    }
}

@MainActor
private final class ContentPaneContextMenuCoordinatorHolder: ObservableObject {
    let coordinator: ContentPaneContextMenuCoordinator

    init(store: StoreOf<FileManagerContentFeature>) {
        coordinator = ContentPaneContextMenuCoordinator(store: store)
    }
}
