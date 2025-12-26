import ComposableArchitecture
import SwiftUI

struct ValuePickerView: View {
    let store: StoreOf<ValuePickerFeature>
    @Environment(\.colorScheme)
    private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
            VStack(alignment: .leading, spacing: 8) {
                if viewStore.valueArity == 0 {
                    Text("No value needed for this operator.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else if viewStore.valueArity == 1 {
                    valueField(
                        title: fieldTitle(for: viewStore.valueType),
                        text: viewStore.binding(
                            get: { $0.values.first ?? "" },
                            send: { .setValue(index: 0, text: $0) },
                        ),
                    )
                } else {
                    ForEach(Array(viewStore.values.enumerated()), id: \.offset) { index, _ in
                        valueField(
                            title: fieldTitle(for: viewStore.valueType, index: index),
                            text: viewStore.binding(
                                get: { $0.values[safe: index] ?? "" },
                                send: { .setValue(index: index, text: $0) },
                            ),
                        )
                    }
                }

                HStack {
                    Spacer()
                    Button("Apply") {
                        viewStore.send(.commit)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
            .frame(width: 240)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDark ? Color(red: 0.16, green: 0.16, blue: 0.16) : Color.white),
            )
        })
    }

    private func valueField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            TextField("Enter value", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }

    private func fieldTitle(for valueType: ValueType, index: Int? = nil) -> String {
        let base = switch valueType {
        case .string:
            "Text"
        case .number:
            "Number"
        case .date:
            "Date"
        case .boolean:
            "Boolean"
        case .array:
            "List"
        case .unknown:
            "Value"
        }

        if let index {
            return index == 0 ? "\(base) (from)" : "\(base) (to)"
        }
        return base
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
