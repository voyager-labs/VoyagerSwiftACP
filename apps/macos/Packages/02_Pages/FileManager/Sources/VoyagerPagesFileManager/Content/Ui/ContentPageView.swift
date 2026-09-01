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
    case collectionEmptyDraft

    var emptyDraftGuidance: ContentPageEmptyDraftGuidance? {
        guard self == .collectionEmptyDraft else { return nil }
        return .collectionDraft
    }

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
        isFileBackedCollection: Bool = false,
        hasExecutableCollectionDefinition: Bool = false,
        hasCollectionResponse: Bool = false,
        hasCollectionEntries: Bool = false,
        hasCollectionFailure: Bool = false,
        hasInFlightCollectionRequest: Bool = false,
    ) -> Self {
        if isCollectionSearching || isCollectionContentLoading {
            return .collectionReplacementLoading
        }
        if isEntryLoading, !isCollectionMode {
            return .ordinaryDirectoryLoadingOverlay
        }
        if isCollectionMode,
           isFileBackedCollection,
           !hasExecutableCollectionDefinition,
           !hasCollectionResponse,
           !hasCollectionEntries,
           !hasCollectionFailure,
           !hasInFlightCollectionRequest
        {
            return .collectionEmptyDraft
        }
        return .entries
    }

    static func resolve(state: FileManagerContentState) -> Self {
        let context = state.collection.collectionContext ?? state.composer.collectionContext
        let hasExecutableDefinition = context.map { context in
            !context.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || context.conditions.contains(where: \.isExecutionReady)
        } ?? false
        let hasResponse = state.composer.lastSearchResponse != nil
            || state.composer.lastFiltersResponse != nil
        let hasEntries = !state.entryViewLayout.displayItems.isEmpty
        let hasFailure = state.composer.transientFeedback?.kind == .error
            || state.composer.lastFailedFiltersRequestID != nil
        let hasInFlightRequest = state.composer.isFilteringInFlight
            || state.composer.activeSearchRequestID != nil
            || state.composer.activeFiltersRequestID != nil
            || (state.isCollectionMode && state.entryViewLayout.entryOperations.isLoading)

        return resolve(
            isCollectionSearching: state.composer.isCollectionSearching,
            isCollectionContentLoading: state.entryViewLayout.isCollectionContentLoading,
            isEntryLoading: state.entryViewLayout.entryOperations.isLoading,
            isCollectionMode: state.isCollectionMode,
            isFileBackedCollection: state.openedCollectionURLExists && context != nil,
            hasExecutableCollectionDefinition: hasExecutableDefinition,
            hasCollectionResponse: hasResponse,
            hasCollectionEntries: hasEntries,
            hasCollectionFailure: hasFailure,
            hasInFlightCollectionRequest: hasInFlightRequest,
        )
    }
}

struct ContentPageEmptyDraftGuidance: Equatable {
    let title: String
    let description: String
    let titleAccessibilityIdentifier: String
    let descriptionAccessibilityIdentifier: String

    static let collectionDraft = Self(
        title: "Build your collection",
        description: "Add a query or complete condition to search. "
            + "You can add a scope to narrow where Voyager searches.",
        titleAccessibilityIdentifier: "collection-empty-draft-title",
        descriptionAccessibilityIdentifier: "collection-empty-draft-description",
    )
}

struct ContentPageView: View {
    let store: StoreOf<FileManagerContentFeature>
    let onGoBack: () -> Void
    let onGoForward: () -> Void
    let onSwipeProgress: (EntryHistorySwipeProgress?) -> Void

    @StateObject private var contextMenuCoordinatorHolder: ContentPaneContextMenuCoordinatorHolder

    @Environment(\.fileManagerKeyCommandFocusCoordinator)
    private var keyCommandFocusCoordinator

    init(
        store: StoreOf<FileManagerContentFeature>,
        onGoBack: @escaping () -> Void = {},
        onGoForward: @escaping () -> Void = {},
        onSwipeProgress: @escaping (EntryHistorySwipeProgress?) -> Void = { _ in },
    ) {
        self.store = store
        self.onGoBack = onGoBack
        self.onGoForward = onGoForward
        self.onSwipeProgress = onSwipeProgress
        _contextMenuCoordinatorHolder = StateObject(
            wrappedValue: ContentPaneContextMenuCoordinatorHolder(store: store),
        )
    }

    private var presentationPolicy: ContentPagePresentationPolicy {
        .resolve(state: store.state)
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
        } else if let guidance = presentationPolicy.emptyDraftGuidance {
            emptyDraftView(guidance)
        } else {
            let entryViewLayoutStore = store.scope(state: \.entryViewLayout, action: \.entryViewLayout)
            let menuProvider = makeBlankSpaceMenuProvider()
            switch store.entryViewLayout.mode {
            case .list:
                EntryListViewRepresentable(
                    store: entryViewLayoutStore,
                    blankSpaceMenuProvider: menuProvider,
                    onGoBack: onGoBack,
                    onGoForward: onGoForward,
                    onSwipeProgress: onSwipeProgress,
                )
            case .grid:
                EntryGridViewRepresentable(
                    store: entryViewLayoutStore,
                    blankSpaceMenuProvider: menuProvider,
                    onGoBack: onGoBack,
                    onGoForward: onGoForward,
                    onSwipeProgress: onSwipeProgress,
                )
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
            onTextInput: { text in
                guard presentationPolicy.allowsKeyboardCommandDispatch else { return }
                store.send(.view(.handleTextInput(text)))
            },
        )
        .focusable()
        .allowsHitTesting(false)
    }

    private var backgroundInteractionLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .contextMenu {
                ContentPaneContextMenu(store: store)
            }
            .onTapGesture {
                guard store.entryViewLayout.entryOperations.renamingItemId == nil else { return }
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

    private func emptyDraftView(_ guidance: ContentPageEmptyDraftGuidance) -> some View {
        VStack(spacing: 8) {
            Text(guidance.title)
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier(guidance.titleAccessibilityIdentifier)
            Text(guidance.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier(guidance.descriptionAccessibilityIdentifier)
        }
        .frame(maxWidth: 460)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    var body: some View {
        mainContent
            .onChange(of: presentationPolicy) { policy in
                guard policy.requiresKeyCommandFocus else { return }
                restoreKeyCommandFocus()
            }
            .onChange(of: store.entryViewLayout.selectedIds) { _ in
                guard store.entryViewLayout.entryOperations.renamingItemId == nil else { return }
                restoreKeyCommandFocus()
            }
            .onAppear {
                store.send(.internal(.startObservingSystemNotifications))
                guard store.entryViewLayout.entryOperations.renamingItemId == nil else { return }
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
        if keyCommandFocusCoordinator?.routeEntryListKeyDown(event) == true {
            return
        }

        let command = KeyCommand(
            keyCode: event.keyCode,
            modifiers: KeyModifiers(event.modifierFlags),
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
        )
        if FileManagerContentKeyCommandHandler.compositionPolicy(for: command, state: store.state)
            == .cancelMarkedText
        {
            keyCommandFocusCoordinator?.cancelMarkedText()
        }
        store.send(.view(.handleKeyCommand(command)))
    }

    private func restoreKeyCommandFocus() {
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
