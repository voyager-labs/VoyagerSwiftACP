import AppKit

protocol EntryGridCollectionViewMenuProviding: AnyObject {
    func contextMenu(for indexPath: IndexPath?, event: NSEvent) -> NSMenu
}

final class EntryGridCollectionView: NSCollectionView {
    weak var contextMenuProvider: EntryGridCollectionViewMenuProviding?

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if indexPathForItem(at: location) == nil {
            deselectAll(nil)
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let indexPath = indexPathForItem(at: location),
           !selectionIndexPaths.contains(indexPath)
        {
            selectItems(at: [indexPath], scrollPosition: [])
        }
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        let indexPath = indexPathForItem(at: location)
        return contextMenuProvider?.contextMenu(for: indexPath, event: event)
    }
}
