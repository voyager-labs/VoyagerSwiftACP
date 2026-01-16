import ComposableArchitecture
import SwiftUI

struct ScopeChipView: View {
    let paths: [String]
    let store: StoreOf<ComposerFeature>
    let favorites: [ScopeFavoriteItem]
    let backHistory: [String]
    @Binding var isComboBoxPresented: Bool
    @State private var editingPath: String?
    @State private var deleteHoverPath: String?
    @State private var dropdownHovering: Bool = false
    @State private var nameHoverPath: String?
    @Environment(\.colorScheme)
    private var colorScheme: ColorScheme
    @Dependency(\.entryClient)
    private var entryClient

    var body: some View {
        let isRootPlaceholder = paths.isEmpty
            || (paths.count == 1 && paths[0] == ComposerScopeUtils.rootScopePath)
        HStack(spacing: isRootPlaceholder ? 1 : 4) {
            Image(systemName: "folder")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            if isRootPlaceholder {
                Text("This Mac")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .frame(height: 19)
                dropdownButton(compact: true)
            } else {
                ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                    directoryNameChip(path: path, index: index)
                }
                dropdownButton(compact: false)
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

    private func dropdownButton(compact: Bool) -> some View {
        Button {
            isComboBoxPresented = true
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
                .foregroundColor(dropdownHovering ? .primary : .secondary)
                .padding(.horizontal, compact ? 3 : 6)
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

    @ViewBuilder
    private func directoryNameChip(path: String, index _: Int) -> some View {
        let displayName = entryClient.displayName(path)

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
