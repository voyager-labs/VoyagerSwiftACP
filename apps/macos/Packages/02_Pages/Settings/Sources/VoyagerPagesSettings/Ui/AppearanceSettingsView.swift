import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesAppPreferences
import VoyagerShared

struct ThemePreviewCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    private enum PreviewMetrics {
        static let width: CGFloat = 70
        static let height: CGFloat = 42
        static let halfWidth: CGFloat = 35
        static let cornerRadius: CGFloat = 8
        static let popupCornerRadius: CGFloat = 4
        static let trafficLightSize: CGFloat = 5
    }

    private var contentBackgroundColor: Color {
        switch theme {
        case .light:
            Color(red: 0.4, green: 0.6, blue: 0.9)
        case .dark:
            Color(red: 0.2, green: 0.3, blue: 0.5)
        case .system:
            Color(white: 0.5)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            previewSurface
                .overlay(previewPopups)
                .overlay(previewBorder)

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
    private var previewSurface: some View {
        if theme == .system {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(red: 0.4, green: 0.6, blue: 0.9))
                    .frame(width: PreviewMetrics.halfWidth, height: PreviewMetrics.height)
                Rectangle()
                    .fill(Color(red: 0.2, green: 0.3, blue: 0.5))
                    .frame(width: PreviewMetrics.halfWidth, height: PreviewMetrics.height)
            }
            .frame(width: PreviewMetrics.width, height: PreviewMetrics.height)
            .clipShape(RoundedRectangle(cornerRadius: PreviewMetrics.cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: PreviewMetrics.cornerRadius)
                .fill(contentBackgroundColor)
                .frame(width: PreviewMetrics.width, height: PreviewMetrics.height)
        }
    }

    @ViewBuilder
    private var previewPopups: some View {
        if theme == .system {
            HStack(spacing: 0) {
                buildPopupWindow(isLight: true, showAllTrafficLights: false)
                    .frame(width: PreviewMetrics.halfWidth, height: PreviewMetrics.height)
                buildPopupWindow(isLight: false, showAllTrafficLights: false)
                    .frame(width: PreviewMetrics.halfWidth, height: PreviewMetrics.height)
            }
        } else {
            buildPopupWindow(isLight: theme == .light, showAllTrafficLights: true)
        }
    }

    private var previewBorder: some View {
        RoundedRectangle(cornerRadius: PreviewMetrics.cornerRadius)
            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            .frame(width: PreviewMetrics.width, height: PreviewMetrics.height)
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

        popupWindowChrome(popupBg: popupBg, width: popupWidth, height: popupHeight)
            .offset(x: startX, y: startY)
            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
            .clipped()
    }

    private func popupWindowChrome(popupBg: Color, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: PreviewMetrics.popupCornerRadius)
            .fill(popupBg)
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                trafficLightDots
                    .padding(.leading, 4)
                    .padding(.top, 2)
            }
    }

    private var trafficLightDots: some View {
        HStack(spacing: 3) {
            trafficLightDot(color: .red)
            trafficLightDot(color: .yellow)
            trafficLightDot(color: .green)
        }
    }

    private func trafficLightDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: PreviewMetrics.trafficLightSize, height: PreviewMetrics.trafficLightSize)
    }
}

struct AppearanceSettingsView: View {
    let store: StoreOf<AppearanceSettingsFeature>

    // TODO(설정-뷰사이즈): 현재 프리셋 UI는 초기 정리 버전입니다.
    // - 프리셋 값이 하드코딩되어 있음 → DesignSystem/SettingsTypes로 이동하고 근거(의도) 문서화
    // - Mixed는 상태 표시용으로 라벨만 노출 중 → 접근성 설명/상태 안내 문구 보강 검토
    // - 프리셋 선택을 별도로 저장하지 않고 icon/text 값으로 역추론 중 → UserDefaults에 preset 저장(마이그레이션 포함) 검토
    // - 기존 커스텀 값에서 가장 가까운 프리셋 추천/원클릭 정리 UX 추가
    // - 문자열 로컬라이즈(Theme, View size, Customize per view 등) 및 접근성 레이블 정리

    private enum SizePreset: String, CaseIterable, Identifiable {
        case small
        case medium
        case large
        case mixed

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .small:
                "Small"
            case .medium:
                "Medium"
            case .large:
                "Large"
            case .mixed:
                "Mixed"
            }
        }
    }

    private struct ViewSizing {
        let iconSize: CGFloat
        let textSize: CGFloat
    }

    private var listPreset: SizePreset {
        presetForList(iconSize: store.listIconSize, textSize: store.listTextSize)
    }

    private var iconPreset: SizePreset {
        presetForIcon(iconSize: store.gridIconSize, textSize: store.gridTextSize)
    }

    private var overallPreset: SizePreset {
        guard listPreset == iconPreset else {
            return .mixed
        }
        return listPreset == .mixed ? .mixed : listPreset
    }

    private var overallPresetSelection: Binding<SizePreset?> {
        Binding(
            get: {
                let preset = overallPreset
                return preset == .mixed ? nil : preset
            },
            set: { preset in
                guard let preset else { return }
                applyOverallPreset(preset)
            },
        )
    }

    private var listPresetBinding: Binding<SizePreset> {
        Binding(
            get: { listPreset },
            set: { preset in
                applyListPreset(preset)
            },
        )
    }

    private var iconPresetBinding: Binding<SizePreset> {
        Binding(
            get: { iconPreset },
            set: { preset in
                applyIconPreset(preset)
            },
        )
    }

    private var perViewPresets: [SizePreset] {
        SizePreset.allCases.filter { $0 != .mixed }
    }

    private var overallPresets: [SizePreset] {
        perViewPresets
    }

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
                            isSelected: store.theme == .system,
                        ) {
                            store.send(.setTheme(.system))
                        }

                        ThemePreviewCard(
                            theme: .light,
                            isSelected: store.theme == .light,
                        ) {
                            store.send(.setTheme(.light))
                        }

                        ThemePreviewCard(
                            theme: .dark,
                            isSelected: store.theme == .dark,
                        ) {
                            store.send(.setTheme(.dark))
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("File display") {
                Toggle(
                    "Show Hidden Files",
                    isOn: Binding(
                        get: { store.showHiddenFiles },
                        set: { store.send(.setShowHiddenFiles($0)) },
                    ),
                )
            }

            Section("View size") {
                HStack(alignment: .center, spacing: 20) {
                    HStack(spacing: 6) {
                        Text("Overall")
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: true, vertical: false)

                        if overallPreset == .mixed {
                            Text(SizePreset.mixed.title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 140, alignment: .leading)

                    Spacer()

                    Picker("Overall", selection: overallPresetSelection) {
                        ForEach(overallPresets) { preset in
                            Text(preset.title).tag(Optional(preset))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                DisclosureGroup("Customize per view") {
                    Picker("List", selection: listPresetBinding) {
                        ForEach(perViewPresets) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Icon", selection: iconPresetBinding) {
                        ForEach(perViewPresets) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func presetForList(iconSize: CGFloat, textSize: CGFloat) -> SizePreset {
        let icon = Int(iconSize.rounded())
        let text = Int(textSize.rounded())

        if icon == 18, text == 12 { return .small }
        if icon == 20, text == 13 { return .medium }
        if icon == 24, text == 14 { return .large }

        return .mixed
    }

    private func presetForIcon(iconSize: CGFloat, textSize: CGFloat) -> SizePreset {
        let icon = Int(iconSize.rounded())
        let text = Int(textSize.rounded())

        if icon == 48, text == 11 { return .small }
        if icon == 64, text == 12 { return .medium }
        if icon == 96, text == 13 { return .large }

        return .mixed
    }

    private func sizingForListPreset(_ preset: SizePreset) -> ViewSizing? {
        switch preset {
        case .small:
            ViewSizing(iconSize: 18, textSize: 12)
        case .medium:
            ViewSizing(iconSize: 20, textSize: 13)
        case .large:
            ViewSizing(iconSize: 24, textSize: 14)
        case .mixed:
            nil
        }
    }

    private func sizingForIconPreset(_ preset: SizePreset) -> ViewSizing? {
        switch preset {
        case .small:
            ViewSizing(iconSize: 48, textSize: 11)
        case .medium:
            ViewSizing(iconSize: 64, textSize: 12)
        case .large:
            ViewSizing(iconSize: 96, textSize: 13)
        case .mixed:
            nil
        }
    }

    private func applyOverallPreset(_ preset: SizePreset) {
        guard preset != .mixed else { return }
        guard let listSizing = sizingForListPreset(preset) else { return }
        guard let iconSizing = sizingForIconPreset(preset) else { return }

        store.send(.setListIconSize(listSizing.iconSize))
        store.send(.setListTextSize(listSizing.textSize))
        store.send(.setGridIconSize(iconSizing.iconSize))
        store.send(.setGridTextSize(iconSizing.textSize))
    }

    private func applyListPreset(_ preset: SizePreset) {
        guard preset != .mixed else { return }
        guard let sizing = sizingForListPreset(preset) else { return }
        store.send(.setListIconSize(sizing.iconSize))
        store.send(.setListTextSize(sizing.textSize))
    }

    private func applyIconPreset(_ preset: SizePreset) {
        guard preset != .mixed else { return }
        guard let sizing = sizingForIconPreset(preset) else { return }
        store.send(.setGridIconSize(sizing.iconSize))
        store.send(.setGridTextSize(sizing.textSize))
    }
}
