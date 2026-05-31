import ComposableArchitecture
import AppKit
import SwiftUI

struct AiChatSessionsView: View {
    @State private var hoveredRenameAction: RenameAction?

    let store: StoreOf<AiChatFeature>
    let state: AiChatState
    let displayModel: AiChatSessionsDisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchField

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
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(displayModel.sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(section.rows) { row in
                                    sessionRow(row)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
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

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(
                displayModel.searchPlaceholder,
                text: Binding(
                    get: { state.sessionList.query },
                    set: { store.send(.sessionSearchQueryChanged($0)) }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func sessionRow(_ row: AiChatSessionRowDisplayModel) -> some View {
        if state.sessionList.renamingSessionID == row.id {
            renameRow(row)
        } else {
            displayRow(row)
        }
    }

    private func displayRow(_ row: AiChatSessionRowDisplayModel) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                store.send(.sessionRowTapped(row.id))
            } label: {
                rowText(row)
            }
            .buttonStyle(.plain)

            rowActivityIndicator(row)

            AiChatSessionActionsMenuButton(
                onRename: { store.send(.renameSessionTapped(row.id)) },
                onDelete: { store.send(.deleteSessionTapped(row.id)) }
            )
            .frame(width: 24, height: 24)
            .help("Session actions")
        }
    }

    @ViewBuilder
    private func rowActivityIndicator(_ row: AiChatSessionRowDisplayModel) -> some View {
        switch row.activityState {
        case .idle:
            EmptyView()
        case .processing:
            EmptyView()
        case .unreadCompleted:
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Unread completed response")
        }
    }

    private func renameRow(_ row: AiChatSessionRowDisplayModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(
                "Session title",
                text: Binding(
                    get: { state.sessionList.renameDraftText },
                    set: { store.send(.renameSessionTitleChanged($0)) }
                )
            )
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                renameActionButton("Save", action: .save, weight: .semibold) {
                    store.send(.renameSessionConfirmed)
                }

                renameActionButton("Cancel", action: .cancel) {
                    store.send(.renameSessionCancelled)
                }

                Spacer(minLength: 0)
            }

            if let detail = row.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func renameActionButton(
        _ title: String,
        action: RenameAction,
        weight: Font.Weight = .medium,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.system(size: 11, weight: weight))
                .foregroundStyle(hoveredRenameAction == action ? .primary : .secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hoveredRenameAction == action ? Color.primary.opacity(0.08) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredRenameAction = hovering ? action : (hoveredRenameAction == action ? nil : hoveredRenameAction)
        }
    }

    private func rowText(_ row: AiChatSessionRowDisplayModel) -> some View {
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
        .modifier(AiChatProcessingRowTextEffect(isActive: row.activityState == .processing))
        .accessibilityLabel(row.activityState == .processing ? "\(row.title), generating response" : row.title)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AiChatProcessingRowTextEffect: ViewModifier {
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                content
                    .opacity(0.38)
                    .overlay {
                        movingHighlight(at: timeline.date)
                            .mask(content)
                    }
            }
        } else {
            content
        }
    }

    private func movingHighlight(at date: Date) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.45) / 1.45
            let travel = width * 2.4
            let offset = CGFloat(progress) * travel - width * 0.7

            LinearGradient(
                stops: [
                    .init(color: Color.primary.opacity(0.34), location: 0),
                    .init(color: Color.primary.opacity(0.52), location: 0.36),
                    .init(color: Color.primary.opacity(1), location: 0.5),
                    .init(color: Color.primary.opacity(0.52), location: 0.64),
                    .init(color: Color.primary.opacity(0.34), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 1.15)
            .offset(x: offset)
        }
    }
}

private struct AiChatSessionActionsMenuButton: NSViewRepresentable {
    let onRename: () -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.title = ""
        button.image = NSImage(
            systemSymbolName: "ellipsis",
            accessibilityDescription: "Session actions"
        )
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.contentTintColor = .secondaryLabelColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.setButtonType(.momentaryPushIn)
        button.focusRingType = .none
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onRename = onRename
        context.coordinator.onDelete = onDelete
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onRename: onRename, onDelete: onDelete)
    }

    @MainActor
    final class Coordinator: NSObject {
        var onRename: () -> Void
        var onDelete: () -> Void

        init(onRename: @escaping () -> Void, onDelete: @escaping () -> Void) {
            self.onRename = onRename
            self.onDelete = onDelete
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()
            menu.addItem(menuItem(title: "Rename", action: #selector(rename)))
            menu.addItem(menuItem(title: "Delete", action: #selector(delete), isDestructive: true))
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 2), in: sender)
        }

        @objc private func rename() {
            onRename()
        }

        @objc private func delete() {
            onDelete()
        }

        private func menuItem(
            title: String,
            action: Selector,
            isDestructive: Bool = false
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if isDestructive {
                item.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
            }
            return item
        }
    }
}

private enum RenameAction: Equatable {
    case cancel
    case save
}
