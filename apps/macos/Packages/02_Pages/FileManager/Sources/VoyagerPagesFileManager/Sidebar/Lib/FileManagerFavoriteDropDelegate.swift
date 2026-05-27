import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct FileManagerFavoriteDropDelegate: DropDelegate {
    @Binding var dropTargetIndex: Int?

    let index: Int
    let onDrop: (_ providers: [NSItemProvider], _ index: Int) -> Bool

    func dropEntered(info: DropInfo) {
        let hasFileURLProvider = !info.itemProviders(for: [UTType.fileURL]).isEmpty
        if hasFileURLProvider {
            dropTargetIndex = index
        } else if dropTargetIndex == index {
            dropTargetIndex = nil
        }
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func dropExited(info _: DropInfo) {
        if dropTargetIndex == index {
            dropTargetIndex = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dropTargetIndex = nil
        return onDrop(info.itemProviders(for: [UTType.fileURL]), index)
    }
}
