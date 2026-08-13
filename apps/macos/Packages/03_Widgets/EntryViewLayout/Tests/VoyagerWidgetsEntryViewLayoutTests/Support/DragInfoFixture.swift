@preconcurrency import AppKit
import Foundation

/// 최소 `NSDraggingInfo` fixture.
/// EntryViewLayout EOP-002 drop 시나리오가 3개 이상의 테스트에서
/// 외부 drag source / pasteboard / operation mask를 재사용하므로 shared fixture로 둔다.
/// product assertion은 포함하지 않는다.
final class DragInfoFixture: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = [.copy, .move]
    var draggingLocation: NSPoint = .zero
    var draggedImageLocation: NSPoint = .zero
    var draggedImage: NSImage?
    var draggingPasteboard: NSPasteboard
    var draggingSource: Any?
    var draggingSequenceNumber: Int = 0
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    var springLoadingHighlight: NSSpringLoadingHighlight = .none

    @MainActor
    init(
        source: Any? = nil,
        operationMask: NSDragOperation = [.copy, .move],
        pasteboard: NSPasteboard? = nil,
        location: NSPoint = .zero,
    ) {
        draggingSource = source
        draggingSourceOperationMask = operationMask
        draggingPasteboard = pasteboard
            ?? NSPasteboard(name: NSPasteboard.Name("EOP002-Fixture-\(UUID().uuidString)"))
        draggingLocation = location
        draggedImageLocation = location
        super.init()
    }

    func slideDraggedImage(to _: NSPoint) {}

    override func namesOfPromisedFilesDropped(atDestination _: URL) -> [String]? {
        nil
    }

    func enumerateDraggingItems(
        options _: NSDraggingItemEnumerationOptions,
        for _: NSView?,
        classes _: [AnyClass],
        searchOptions _: [NSPasteboard.ReadingOptionKey: Any],
        using _: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void,
    ) {}

    func resetSpringLoading() {}
}
