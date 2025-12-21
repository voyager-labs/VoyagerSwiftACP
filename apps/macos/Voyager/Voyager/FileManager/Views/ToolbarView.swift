import AppKit
import ComposableArchitecture
import SwiftUI

struct ToolbarView: View {
    let store: StoreOf<FileManagerFeature>
    @State private var isDark: Bool = isDarkMode()
    @State private var localComposeText: String = ""
    @FocusState private var isComposeFieldFocused: Bool
    @Environment(\.colorScheme)
    var colorScheme
    @State private var escKeyMonitor: Any?

    private let trafficLightAreaWidth: CGFloat = 80
    private let escapeKeyCode: UInt16 = 53 // ESC 키 코드

    var body: some View {
        Group {
            if store.isComposeMode {
                composeModeContent
            } else {
                normalModeContent
            }
        }
        .frame(maxHeight: .infinity)
        .padding(0)
        .padding(.leading, store.sidebarVisible ? 0 : trafficLightAreaWidth)
        .padding(.horizontal, 16)
        .padding(.vertical, store.isComposeMode ? 10 : 0)
        .frame(height: store.isComposeMode ? 88 : 48)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                toolbarBackgroundColor

                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.black.opacity(0.15))
                        .frame(height: 1.0)
                }
            }
        )
        .onAppear {
            isDark = isDarkMode()
        }
        .onChange(of: colorScheme) { newScheme in
            isDark = newScheme == .dark
        }
        .onChange(of: store.isComposeMode) { isCompose in
            if isCompose {
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
            } else {
                cleanupEscKeyMonitor()
            }
        }
        .onDisappear {
            cleanupEscKeyMonitor()
        }
    }

    private var normalModeContent: some View {
        HStack(spacing: 12) {
            Menu {
                if store.backHistory.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(store.backHistory.enumerated().reversed()), id: \.offset) { index, path in
                        Button(
                            action: {
                                let originalIndex = store.backHistory.count - 1 - index
                                store.send(.goToHistoryIndex(originalIndex, isBackHistory: true))
                            },
                            label: {
                                Text(FileManager.default.displayName(atPath: path))
                            }
                        )
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(store.canGoBack ? .primary : .secondary)
            } primaryAction: {
                store.send(.goBack)
            }
            .menuIndicator(.hidden)
            .disabled(!store.canGoBack)
            .buttonStyle(.borderless)

            Menu {
                if store.forwardHistory.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(store.forwardHistory.enumerated().reversed()), id: \.offset) { index, path in
                        Button(
                            action: {
                                let originalIndex = store.forwardHistory.count - 1 - index
                                store.send(.goToHistoryIndex(originalIndex, isBackHistory: false))
                            },
                            label: {
                                Text(FileManager.default.displayName(atPath: path))
                            }
                        )
                    }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(store.canGoForward ? .primary : .secondary)
            } primaryAction: {
                store.send(.goForward)
            }
            .menuIndicator(.hidden)
            .disabled(!store.canGoForward)
            .buttonStyle(.borderless)

            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                Text(FileManager.default.displayName(atPath: store.currentPath))
                    .font(.system(size: 15, weight: .semibold))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                store.send(.enterComposeMode)
            }

            Spacer()

            ToolbarMenuView(store: store)
        }
    }

    private var composeModeContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    // TODO: Undo 기능 추후 구현
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)

                Button {
                    // TODO: Redo 기능 추후 구현
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)

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
            .padding(.bottom, 8)

            Rectangle()
                .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                .frame(height: 1)

            HStack(spacing: 8) {
                scopeChip

                // 스코프 추가 버튼
                Button {
                    // TODO: openScopeMenu (voy-95에서 구현)
                } label: {
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

                // 필터 칩 영역 (추후 백엔드 응답 시 생성)
                // TODO: filterChips forEach

                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private var scopeChip: some View {
        ScopeChipView(
            path: store.currentPath,
            isDark: isDark,
            favorites: store.favorites,
            backHistory: store.backHistory
        )
    }

    private var toolbarBackgroundColor: Color {
        if isDark {
            return Color(red: 0.17, green: 0.17, blue: 0.17)
        } else {
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private func cleanupEscKeyMonitor() {
        if let monitor = escKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escKeyMonitor = nil
        }
    }
}

private struct ScopeChipView: View {
    let path: String
    let isDark: Bool
    let favorites: [SidebarUtils.FavoriteItem]
    let backHistory: [String]
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                // TODO: removeScopeDirectory(path) (voy-95에서 구현)
            } label: {
                Image(systemName: isHovered ? "xmark.circle.fill" : "folder")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)

            Menu {
                ForEach(favorites, id: \.url) { favorite in
                    Button {
                        // TODO: selectScopeDirectory(favorite.url) (voy-95에서 구현)
                    } label: {
                        HStack {
                            Image(systemName: favorite.iconName)
                                .font(.system(size: 11))
                            Text(favorite.name)
                                .font(.system(size: 12))
                        }
                    }
                }

                if !favorites.isEmpty {
                    Divider()
                }

                // TODO: Favorites 제외 로직은 voy-95에서 구현
                ForEach(Array(backHistory.reversed().prefix(10)), id: \.self) { recentPath in
                    Button {
                        // TODO: selectScopeDirectory(URL(fileURLWithPath: recentPath)) (voy-95에서 구현)
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text(FileManager.default.displayName(atPath: recentPath))
                                .font(.system(size: 12))
                        }
                    }
                }

                if !backHistory.isEmpty {
                    Divider()
                }

                Button {
                    // TODO: NSOpenPanel 열기 (voy-95에서 구현)
                } label: {
                    Text("Other...")
                }
            } label: {
                Text(FileManager.default.displayName(atPath: path))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.8))
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
