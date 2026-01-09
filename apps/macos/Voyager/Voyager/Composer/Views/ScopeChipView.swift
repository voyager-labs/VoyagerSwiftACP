import ComposableArchitecture
import SwiftUI

struct ScopeChipView: View {
    let paths: [String]
    let store: StoreOf<ComposerFeature>
    let favorites: [SidebarUtils.FavoriteItem]
    let backHistory: [String]

    @State private var isComboBoxPresented: Bool = false
    @State private var editingPath: String?
    @State private var deleteHoverPath: String?
    @State private var dropdownHovering: Bool = false
    @State private var nameHoverPath: String?
    @State private var addScopeHovering: Bool = false
    @Environment(\.colorScheme)
    private var colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                directoryNameChip(path: path, index: index)
            }

            if paths.isEmpty {
                Button {
                    editingPath = nil
                    isComboBoxPresented = true
                } label: {
                    Text("Add scope")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(addScopeHovering ? .primary : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .frame(height: 19)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(addScopeHovering ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : .clear),
                        )
                }
                .buttonStyle(.borderless)
                .onHover { hovering in
                    addScopeHovering = hovering
                }
            } else {
                Button {
                    isComboBoxPresented = true
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(dropdownHovering ? .primary : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .frame(height: 19)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(dropdownHovering ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : .clear),
                        )
                }
                .buttonStyle(.borderless)
                .onHover { hovering in
                    dropdownHovering = hovering
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(VoyagerDS.Surface.chipContainerBackground(for: colorScheme)),
        )
        .popover(isPresented: $isComboBoxPresented, arrowEdge: .bottom) {
            ScopePickerView(
                isPresented: $isComboBoxPresented,
                oldPath: editingPath,
                onSelect: { selectedPath in
                    if let oldPath = editingPath {
                        store.send(.updateScope(oldPath: oldPath, newPath: selectedPath))
                    } else {
                        store.send(.addScope(path: selectedPath))
                    }
                    editingPath = nil
                },
                favorites: favorites,
                backHistory: backHistory,
            )
        }
    }

    @ViewBuilder
    private func directoryNameChip(path: String, index _: Int) -> some View {
        let displayName = FileManager.default.displayName(atPath: path)

        HStack(spacing: 4) {
            Button {
                editingPath = path
                isComboBoxPresented = true
            } label: {
                Text(displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(nameHoverPath == path ? .primary : .primary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.borderless)
            .onHover { hovering in
                nameHoverPath = hovering ? path : nil
            }

            Button {
                store.send(.removeScope(path: path))
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(deleteHoverPath == path ? .primary : .secondary)
            }
            .buttonStyle(.borderless)
            .onHover { hovering in
                deleteHoverPath = hovering ? path : nil
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(VoyagerDS.Surface.chipItemBackground(for: colorScheme)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(VoyagerDS.Surface.chipItemBorder(for: colorScheme), lineWidth: 0.5),
        )
    }
}
