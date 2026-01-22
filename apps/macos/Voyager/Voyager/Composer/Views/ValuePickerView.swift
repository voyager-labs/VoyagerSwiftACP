import ComposableArchitecture
import SwiftUI

struct ValuePickerView: View {
    let store: StoreOf<ValuePickerFeature>
    @Environment(\.colorScheme)
    private var colorScheme

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
                        placeholder: fieldPlaceholder(for: viewStore.valueType),
                        text: viewStore.binding(
                            get: { $0.values.first ?? "" },
                            send: { .setValue(index: 0, text: $0) },
                        ),
                    )
                } else {
                    ForEach(Array(viewStore.values.enumerated()), id: \.offset) { index, _ in
                        valueField(
                            title: fieldTitle(for: viewStore.valueType, index: index),
                            placeholder: fieldPlaceholder(for: viewStore.valueType),
                            text: viewStore.binding(
                                get: { $0.values[safe: index] ?? "" },
                                send: { .setValue(index: index, text: $0) },
                            ),
                        )
                    }
                }

                if let error = viewStore.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
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
                    .fill(VoyagerDS.Surface.popoverBackground(for: colorScheme)),
            )
        })
    }

    private func valueField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }

    private func fieldTitle(for valueType: String, index: Int? = nil) -> String {
        let base = switch valueType {
        case "string":
            "Text"
        case "number":
            "Number"
        case "date", "datetime":
            "Date"
        case "boolean":
            "Boolean"
        case "string_list":
            "List"
        default:
            "Value"
        }

        if let index {
            return index == 0 ? "\(base) (from)" : "\(base) (to)"
        }
        return base
    }

    private func fieldPlaceholder(for valueType: String) -> String {
        switch valueType {
        case "number":
            "Number Value"
        default:
            "Enter value"
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
