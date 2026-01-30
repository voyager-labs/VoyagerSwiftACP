import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct FileManagerFavoriteDropDelegate: DropDelegate {
    let index: Int
    @Binding var dropTargetIndex: Int?
    let entryClient: EntryClient
    let resolveURL: (_ providers: [NSItemProvider], _ completion: @escaping (URL?) -> Void) -> Void
    let onDrop: (_ providers: [NSItemProvider], _ index: Int) -> Bool

    func dropEntered(info: DropInfo) {
        updateTargetIndicator(with: info)
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

    private func updateTargetIndicator(with info: DropInfo) {
        let providers = info.itemProviders(for: [UTType.fileURL])
        resolveURL(providers) { url in
            guard let url else {
                return
            }

            var isDirectory: ObjCBool = false
            let isVoycoll = url.pathExtension.lowercased() == "voycoll"
            let exists = entryClient.fileExistsAtPath(url.path, &isDirectory)
            let canDrop = exists && (isDirectory.boolValue || isVoycoll)

            DispatchQueue.main.async {
                if canDrop {
                    dropTargetIndex = index
                } else if dropTargetIndex == index {
                    dropTargetIndex = nil
                }
            }
        }
    }
}
