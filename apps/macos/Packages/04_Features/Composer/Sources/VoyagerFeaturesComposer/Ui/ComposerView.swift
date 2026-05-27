import ComposableArchitecture
import SwiftUI
import VoyagerShared

public struct ComposerView: View {
    let store: StoreOf<ComposerFeature>
    let favorites: [ScopeFavoriteItem]
    let historyPaths: [String]
    let isDiscardEnabled: Bool
    let canSaveCollection: Bool
    let isTemporaryCollection: Bool
    let onDiscardCollectionChanges: () -> Void
    let onExitComposer: () -> Void

    @Environment(\.colorScheme)
    private var colorScheme: ColorScheme

    @StateObject private var keyboardMonitor = ComposerKeyboardMonitor()
    @State private var isScopePickerPresented: Bool = false

    private var isDark: Bool { colorScheme == .dark }

    private struct ViewState: Equatable {
        let isPresented: Bool
        let transientFeedback: ComposerTransientFeedback?
    }

    public init(
        store: StoreOf<ComposerFeature>,
        favorites: [ScopeFavoriteItem],
        historyPaths: [String],
        isDiscardEnabled: Bool,
        canSaveCollection: Bool,
        isTemporaryCollection: Bool,
        onDiscardCollectionChanges: @escaping () -> Void,
        onExitComposer: @escaping () -> Void,
    ) {
        self.store = store
        self.favorites = favorites
        self.historyPaths = historyPaths
        self.isDiscardEnabled = isDiscardEnabled
        self.canSaveCollection = canSaveCollection
        self.isTemporaryCollection = isTemporaryCollection
        self.onDiscardCollectionChanges = onDiscardCollectionChanges
        self.onExitComposer = onExitComposer
    }

    public var body: some View {
        WithViewStore(
            store,
            observe: { state in
                ViewState(
                    isPresented: state.isPresented,
                    transientFeedback: state.transientFeedback,
                )
            },
            content: { viewStore in
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        ComposerTopRowView(
                            store: store,
                            colorScheme: colorScheme,
                            isDiscardEnabled: isDiscardEnabled,
                            canSaveCollection: canSaveCollection,
                            isTemporaryCollection: isTemporaryCollection,
                            isOptionKeyPressed: keyboardMonitor.isOptionKeyPressed,
                            onDiscardCollectionChanges: onDiscardCollectionChanges,
                        )
                        .fixedSize(horizontal: false, vertical: true)

                        Rectangle()
                            .fill(VoyagerDS.SystemColor.separator)
                            .frame(height: 1)
                            .padding(.horizontal, 16)

                        ComposerBottomRowView(
                            store: store,
                            favorites: favorites,
                            historyPaths: historyPaths,
                            colorScheme: colorScheme,
                            isScopePickerPresented: $isScopePickerPresented,
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if let feedback = viewStore.transientFeedback {
                        ComposerFeedbackToastView(feedback: feedback)
                            .frame(maxWidth: 360)
                            .padding(.top, 54)
                            .allowsHitTesting(false)
                            .zIndex(1)
                    }
                }
                .background(
                    VisualEffectBackgroundView(
                        material: .popover,
                        blendingMode: .withinWindow,
                        tintColor: NSColor(VoyagerDS.Interaction.composerBackground(for: colorScheme)),
                        tintOpacity: 0.15,
                    )
                    .clipShape(RoundedRectangle(cornerRadius: VoyagerDS.Radius.composer))
                    .overlay(
                        RoundedRectangle(cornerRadius: VoyagerDS.Radius.composer)
                            .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.12), lineWidth: 1),
                    )
                    .shadow(
                        color: Color.black.opacity(isDark ? 0.45 : 0.18),
                        radius: isDark ? 18 : 12,
                        x: 0,
                        y: isDark ? 10 : 6,
                    )
                    .allowsHitTesting(false),
                )
                .allowsHitTesting(true)
                .onAppear {
                    setupOnAppear()
                }
                .onDisappear {
                    keyboardMonitor.stop()
                }
                .onChange(of: viewStore.isPresented) { isPresented in
                    if !isPresented {
                        keyboardMonitor.stop()
                    }
                }
            },
        )
    }

    private func setupOnAppear() {
        keyboardMonitor.start(
            onEscape: {
                if isScopePickerPresented {
                    isScopePickerPresented = false
                    return true
                }
                if store.propertyPicker.isPresented {
                    store.send(.propertyPicker(.setPresented(false)))
                    return true
                }
                if store.operatorPicker.isPresented {
                    store.send(.operatorPicker(.setPresented(false)))
                    return true
                }
                if store.valuePicker.isPresented {
                    store.send(.valuePicker(.setPresented(false)))
                    return true
                }
                onExitComposer()
                return true
            },
            onUndo: {
                if store.canUndo {
                    store.send(.undo)
                }
            },
            onRedo: {
                if store.canRedo {
                    store.send(.redo)
                }
            },
        )
    }
}
