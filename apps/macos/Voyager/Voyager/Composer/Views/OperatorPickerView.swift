import ComposableArchitecture
import SwiftUI

struct OperatorPickerView: View {
    let store: StoreOf<OperatorPickerFeature>
    @Environment(\.colorScheme)
    private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewStore.options) { option in
                            Button {
                                viewStore.send(.select(option))
                            } label: {
                                HStack {
                                    Text(option.label)
                                        .foregroundColor(.primary)
                                        .font(.system(size: 12))
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(width: 180)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDark ? Color(red: 0.16, green: 0.16, blue: 0.16) : Color.white),
            )
        })
    }
}
