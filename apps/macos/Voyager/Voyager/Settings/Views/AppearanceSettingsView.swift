import AppKit
import ComposableArchitecture
import SwiftUI

struct ThemePreviewCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    private var contentBackgroundColor: Color {
        switch theme {
        case .light:
            return Color(red: 0.4, green: 0.6, blue: 0.9)
        case .dark:
            return Color(red: 0.2, green: 0.3, blue: 0.5)
        case .system:
            return Color(white: 0.5)
        }
    }

    private var popupBackgroundColor: Color {
        switch theme {
        case .light:
            return Color.white
        case .dark:
            return Color(white: 0.25)
        case .system:
            return Color(white: 0.5)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if theme == .system {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.clear)
                        .frame(width: 70, height: 42)
                        .overlay(
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color(red: 0.4, green: 0.6, blue: 0.9))
                                    .frame(width: 35, height: 42)
                                Rectangle()
                                    .fill(Color(red: 0.2, green: 0.3, blue: 0.5))
                                    .frame(width: 35, height: 42)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        )
                        .overlay(
                            HStack(spacing: 0) {
                                buildPopupWindow(isLight: true, showAllTrafficLights: false)
                                    .frame(width: 35, height: 42)
                                buildPopupWindow(isLight: false, showAllTrafficLights: false)
                                    .frame(width: 35, height: 42)
                            }
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(contentBackgroundColor)
                        .frame(width: 70, height: 42)
                        .overlay(
                            buildPopupWindow(isLight: theme == .light, showAllTrafficLights: true)
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    .frame(width: 70, height: 42)
            )

            Text(theme.displayName)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(.primary)
        }
        .frame(width: 80)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    @ViewBuilder
    private func buildPopupWindow(isLight: Bool, showAllTrafficLights: Bool) -> some View {
        let popupBg = isLight ? Color.white : Color(white: 0.25)

        let isAuto = !showAllTrafficLights
        let cardWidth: CGFloat = isAuto ? 35 : 70
        let cardHeight: CGFloat = 42

        let startX: CGFloat = isAuto ? 10 : cardWidth / 3
        let startY: CGFloat = cardHeight / 3

        let popupWidth: CGFloat = isAuto ? cardWidth - startX + 6 : cardWidth - startX
        let popupHeight: CGFloat = cardHeight - startY

        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: cardWidth, height: cardHeight)

            RoundedRectangle(cornerRadius: 4)
                .fill(popupBg)
                .frame(width: popupWidth, height: popupHeight)
                .overlay(
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 5, height: 5)
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 5, height: 5)
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 2),
                    alignment: .topLeading
                )
                .offset(x: startX, y: startY)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipped()
    }
}

struct AppearanceSettingsView: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 20) {
                    Text("Theme")
                        .foregroundColor(.primary)
                        .frame(width: 100, alignment: .leading)

                    Spacer()

                    HStack(spacing: 8) {
                        ThemePreviewCard(
                            theme: .system,
                            isSelected: store.appearanceSettings.theme == .system
                        ) {
                            store.send(.appearance(.setTheme(.system)))
                        }

                        ThemePreviewCard(
                            theme: .light,
                            isSelected: store.appearanceSettings.theme == .light
                        ) {
                            store.send(.appearance(.setTheme(.light)))
                        }

                        ThemePreviewCard(
                            theme: .dark,
                            isSelected: store.appearanceSettings.theme == .dark
                        ) {
                            store.send(.appearance(.setTheme(.dark)))
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Icon Size") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 20) {
                        Text("List View")
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: 140, alignment: .leading)

                        Spacer()

                        HStack(spacing: 12) {
                            Slider(
                                value: Binding(
                                    get: { store.appearanceSettings.listIconSize },
                                    set: { store.send(.appearance(.setListIconSize($0))) }
                                ),
                                in: 16 ... 32,
                                step: 1
                            )
                            .frame(width: 200)

                            Text("\(Int(store.appearanceSettings.listIconSize))" +
                                "x\(Int(store.appearanceSettings.listIconSize))")
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                    }

                    HStack(alignment: .top, spacing: 20) {
                        Text("Grid View")
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: 140, alignment: .leading)

                        Spacer()

                        HStack(spacing: 12) {
                            Slider(
                                value: Binding(
                                    get: { store.appearanceSettings.gridIconSize },
                                    set: { store.send(.appearance(.setGridIconSize($0))) }
                                ),
                                in: 16 ... 512,
                                step: 4
                            )
                            .frame(width: 200)

                            Text("\(Int(store.appearanceSettings.gridIconSize))" +
                                "x\(Int(store.appearanceSettings.gridIconSize))")
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Text Size") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 20) {
                        Text("List View")
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: 140, alignment: .leading)

                        Spacer()

                        HStack(spacing: 12) {
                            Slider(
                                value: Binding(
                                    get: { store.appearanceSettings.listTextSize },
                                    set: { store.send(.appearance(.setListTextSize($0))) }
                                ),
                                in: 10 ... 16,
                                step: 1
                            )
                            .frame(width: 200)

                            Text("\(Int(store.appearanceSettings.listTextSize)) pt")
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                    }

                    HStack(alignment: .top, spacing: 20) {
                        Text("Grid View")
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: 140, alignment: .leading)

                        Spacer()

                        HStack(spacing: 12) {
                            Slider(
                                value: Binding(
                                    get: { store.appearanceSettings.gridTextSize },
                                    set: { store.send(.appearance(.setGridTextSize($0))) }
                                ),
                                in: 10 ... 16,
                                step: 1
                            )
                            .frame(width: 200)

                            Text("\(Int(store.appearanceSettings.gridTextSize)) pt")
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
