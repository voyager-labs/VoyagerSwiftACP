import AppKit
import ComposableArchitecture
import SwiftUI

struct ComposeModeOverlay: View {
    let store: StoreOf<FileManagerFeature>
    @State private var isDark: Bool = isDarkMode()
    @State private var localComposeText: String = ""
    @FocusState private var isComposeFieldFocused: Bool
    @Environment(\.colorScheme)
    var colorScheme
    @State private var escKeyMonitor: Any?

    private let trafficLightAreaWidth: CGFloat = 80
    private let escapeKeyCode: UInt16 = 53

    var body: some View {
        mainContent
            .onAppear {
                setupOnAppear()
            }
            .onDisappear {
                cleanupEscKeyMonitor()
            }
            .onChange(of: colorScheme) { newScheme in
                isDark = newScheme == .dark
            }
            .onChange(of: store.isComposeMode) { isCompose in
                if !isCompose {
                    cleanupEscKeyMonitor()
                }
            }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            firstRow
            horizontalSeparator
            secondRow
        }
        .background(
            RoundedRectangle(cornerRadius: 12) // 둥근 모서리로 독립 창 느낌
                .fill(overlayBackground)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12) // 더 강한 그림자
        )
    }

    private var firstRow: some View {
        HStack(spacing: 12) {
            undoButton
            redoButton
            textField
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.leading, store.sidebarVisible ? 0 : trafficLightAreaWidth)
        .padding(.vertical, 10)
        .frame(height: 48)
    }

    private var undoButton: some View {
        Button {
            // TODO: Undo 기능 추후 구현
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
    }

    private var redoButton: some View {
        Button {
            // TODO: Redo 기능 추후 구현
        } label: {
            Image(systemName: "arrow.uturn.forward")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
    }

    private var textField: some View {
        TextField("Enter your request...", text: $localComposeText)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.12), lineWidth: 1)
            )
            .focused($isComposeFieldFocused)
            .onChange(of: localComposeText) { newValue in
                store.send(.setComposeText(newValue))
            }
            .onSubmit {
                // TODO: Enter 시 동작 추후 구현
            }
    }

    private var horizontalSeparator: some View {
        Rectangle()
            .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
            .frame(height: 1)
    }

    private var secondRow: some View {
        HStack(spacing: 8) {
            scopeChips
            scopeAddButton
            verticalSeparator
            filterChips
            filterAddButton
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.leading, store.sidebarVisible ? 0 : trafficLightAreaWidth)
        .padding(.vertical, 8)
    }

    private var scopeChips: some View {
        ForEach([store.currentPath], id: \.self) { scopePath in
            ScopeChipView(
                path: scopePath,
                isDark: isDark,
                favorites: store.favorites,
                backHistory: store.backHistory
            )
        }
    }

    private var scopeAddButton: some View {
        addButton(action: {
            // TODO: openScopeMenu (voy-95에서 구현)
        })
    }

    private var filterChips: some View {
        ForEach(["name contains test", "size > 100KB", "modified < 7 days"], id: \.self) { filterText in
            filterChipView(text: filterText)
        }
    }

    private func filterChipView(text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.primary.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
            )
    }

    private var filterAddButton: some View {
        addButton(action: {
            // TODO: addFilter (voy-95에서 구현)
        })
    }

    private func setupOnAppear() {
        isDark = isDarkMode()
        localComposeText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isComposeFieldFocused = true
        }
        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == escapeKeyCode {
                store.send(.exitComposeMode)
                return nil
            }
            return event
        }
    }

    // 오버레이 배경색: 툴바보다 약간 밝게/어둡게 조정하여 독립 창 느낌 강화
    private var overlayBackground: Color {
        if isDark {
            // 다크 모드: 약간 더 밝게
            return Color(red: 0.19, green: 0.19, blue: 0.19)
        } else {
            // 라이트 모드: 약간 더 어둡게
            return Color(white: 0.96)
        }
    }

    private var verticalSeparator: some View {
        Rectangle()
            .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
            .frame(width: 1)
            .frame(height: 20)
    }

    private func addButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                )
        }
        .buttonStyle(.borderless)
    }

    private func cleanupEscKeyMonitor() {
        if let monitor = escKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escKeyMonitor = nil
        }
    }
}
