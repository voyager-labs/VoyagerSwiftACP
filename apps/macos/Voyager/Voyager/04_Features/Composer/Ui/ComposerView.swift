import AppKit
import ComposableArchitecture
import SwiftUI

struct ComposerView: View {
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

    @State private var keyDownMonitor: Any?
    @State private var flagsChangedMonitor: Any?
    @State private var isOptionKeyPressed: Bool = false
    @State private var isScopePickerPresented: Bool = false

    private let escapeKeyCode: UInt16 = 53
    private let zKeyCode: UInt16 = 6

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        WithViewStore(
            store,
            observe: { $0.isPresented },
            content: { viewStore in
                VStack(spacing: 0) {
                    ComposerTopRowView(
                        store: store,
                        colorScheme: colorScheme,
                        isDiscardEnabled: isDiscardEnabled,
                        canSaveCollection: canSaveCollection,
                        isTemporaryCollection: isTemporaryCollection,
                        isOptionKeyPressed: isOptionKeyPressed,
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
                    cleanupKeyMonitor()
                }
                .onChange(of: viewStore.state) { isPresented in
                    if !isPresented {
                        cleanupKeyMonitor()
                    }
                }
            },
        )
    }

    private func setupOnAppear() {
        isOptionKeyPressed = NSEvent.modifierFlags.contains(.option)

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == escapeKeyCode {
                if isScopePickerPresented {
                    isScopePickerPresented = false
                    return nil
                }
                if store.propertyPicker.isPresented {
                    store.send(.propertyPicker(.setPresented(false)))
                    return nil
                }
                if store.operatorPicker.isPresented {
                    store.send(.operatorPicker(.setPresented(false)))
                    return nil
                }
                if store.valuePicker.isPresented {
                    store.send(.valuePicker(.setPresented(false)))
                    return nil
                }
                onExitComposer()
                return nil
            }

            if event.keyCode == zKeyCode, event.modifierFlags.contains(.command) {
                if event.modifierFlags.contains(.shift) {
                    if store.canRedo {
                        store.send(.redo)
                    }
                } else if store.canUndo {
                    store.send(.undo)
                }
                return nil
            }

            return event
        }

        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            isOptionKeyPressed = event.modifierFlags.contains(.option)
            return event
        }
    }

    private func cleanupKeyMonitor() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
    }
}
