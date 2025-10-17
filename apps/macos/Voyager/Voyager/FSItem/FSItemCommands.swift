import AppKit
import SwiftUI

struct FSItemCommands: Commands {
    @ObservedObject var selectionModel: FSItemSelectionModel

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Open") { open() }
                .keyboardShortcut(.downArrow, modifiers: [.command])
                .disabled(selectionModel.selectedItem == nil)

            Button("Quick Look") { quickLook() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(selectionModel.selectedItem == nil)
        }
    }

    private func open() {
        guard let item = selectionModel.selectedItem, !item.isDirectory else { return }
        Task { try? await FileSystemClient.liveValue.open(item.url, .defaultApp) }
    }

    private func quickLook() {
        guard let item = selectionModel.selectedItem else { return }
        Task { try? await FileSystemClient.liveValue.quickLook(item.url) }
    }
}
