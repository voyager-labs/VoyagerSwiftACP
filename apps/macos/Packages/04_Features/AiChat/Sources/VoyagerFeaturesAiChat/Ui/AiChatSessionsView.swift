import ComposableArchitecture
import SwiftUI

struct AiChatSessionsView: View {
    let store: StoreOf<AiChatFeature>
    let state: AiChatState
    let displayModel: AiChatSessionsDisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                displayModel.searchPlaceholder,
                text: Binding(
                    get: { state.sessionList.query },
                    set: { store.send(.sessionSearchQueryChanged($0)) }
                )
            )
            .textFieldStyle(.roundedBorder)

            if let errorMessage = state.sessionList.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if displayModel.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayModel.emptyTitle)
                        .font(.system(size: 15, weight: .semibold))
                    Text(displayModel.emptyDetail)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(displayModel.sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(section.rows) { row in
                                    HStack(alignment: .center, spacing: 8) {
                                        Button {
                                            store.send(.sessionRowTapped(row.id))
                                        } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(row.title)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(.primary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)

                                                if let detail = row.detail, !detail.isEmpty {
                                                    Text(detail)
                                                        .font(.system(size: 12))
                                                        .foregroundStyle(.secondary)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        .lineLimit(2)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)

                                        Button("Delete") {
                                            store.send(.deleteSessionTapped(row.id))
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.red)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.primary.opacity(0.05))
                                    )
                                }
                            }
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            store.send(.sessionsAppeared)
        }
    }
}
