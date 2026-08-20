@preconcurrency import AppKit
import Foundation
import UniformTypeIdentifiers

/// file promise provider 쓰기(fixture pasteboard 구성)용 최소 delegate.
/// 실제 파일을 쓰지 않고 UTI/type 선언만 하므로 검증에는 promise type 존재만 사용한다.
final class FilePromiseProviderFixtureDelegate: NSObject, NSFilePromiseProviderDelegate {
    let filename: String

    init(filename: String) {
        self.filename = filename
    }

    func filePromiseProvider(_: NSFilePromiseProvider, fileNameForType _: String) -> String {
        filename
    }

    func filePromiseProvider(
        _: NSFilePromiseProvider,
        writePromiseTo _: URL,
        completionHandler: @escaping (Error?) -> Void,
    ) {
        completionHandler(nil)
    }

    func operationQueue(for _: NSFilePromiseProvider) -> OperationQueue {
        .main
    }
}

/// data-flavor 전용 pasteboard fixture.
/// promise/file URL/legacy filename 없이 임의의 UTI + 바이트만 담는 pasteboard를 구성한다.
/// `dataFlavors`는 `[(uti: String, data: Data)]` 순서대로 item을 만든다.
/// 외부 drop의 universal data-flavor 검증(형식 하드코딩 없음)을 위한 테스트 픽스처다.
func makeDataOnlyPasteboard(_ dataFlavors: [(uti: String, data: Data)]) -> NSPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-DataOnly-\(UUID().uuidString)"))
    pasteboard.clearContents()
    for flavor in dataFlavors {
        let item = NSPasteboardItem()
        item.setData(flavor.data, forType: NSPasteboard.PasteboardType(flavor.uti))
        pasteboard.writeObjects([item])
    }
    return pasteboard
}

/// promise item과 data-flavor item을 섞은 pasteboard fixture.
/// promise는 `count`개만큼, data는 `dataFlavors` 순서대로 뒤에 추가한다.
/// 혼합 drag(promise + data)의 inspection/negotiation 검증을 위한 픽스처다.
func makePromiseDataMixedPasteboard(
    promiseCount: Int,
    dataFlavors: [(uti: String, data: Data)],
) -> NSPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-PromiseData-\(UUID().uuidString)"))
    pasteboard.clearContents()
    for _ in 0 ..< promiseCount {
        pasteboard.writeObjects([
            NSFilePromiseProvider(
                fileType: UTType.plainText.identifier,
                delegate: FilePromiseProviderFixtureDelegate(filename: "promise.txt"),
            ),
        ])
    }
    for flavor in dataFlavors {
        let item = NSPasteboardItem()
        item.setData(flavor.data, forType: NSPasteboard.PasteboardType(flavor.uti))
        pasteboard.writeObjects([item])
    }
    return pasteboard
}

/// Numbers 셀 드래그 조합(단일 item에 iWork 네이티브 UTI + 텍스트 플레이버) pasteboard fixture.
/// `public.utf8-plain-text`는 셀 값, `com.apple.iWork.TSPNativeData`는 네이티브 표현이다.
/// 실측(probe) pasteboard의 조합을 그대로 재현한다.
func makeNumbersCellPasteboard() -> NSPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("EOP002-Numbers-\(UUID().uuidString)"))
    pasteboard.clearContents()
    let item = NSPasteboardItem()
    item.setData(Data([0x01, 0x02, 0x03]), forType: NSPasteboard.PasteboardType("com.apple.iWork.TSPNativeData"))
    item.setString("2024-06-12 08:00:000", forType: .string)
    pasteboard.writeObjects([item])
    return pasteboard
}

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
    private(set) var enumerateDraggingItemsCallCount = 0

    /// enumerateDraggingItems가 방문시킬 modern receiver 목록. 실제 AppKit 드래그와 달리
    /// fixture는 pasteboard reading으로 receiver를 복원할 수 없어 주입으로 대체한다
    /// (Photos처럼 receiver를 소유한 드래그 재현용).
    var enumeratedReceivers: [NSFilePromiseReceiver] = []

    /// 레거시 promised-file 드래그 시뮬레이션용 hook. `atDestination`에 파일을 쓰고 이름을 반환한다.
    /// 기본은 nil(파일 약속 없음)로, 기존 테스트 동작을 유지한다.
    var namesOfPromisedFilesHandler: (@Sendable (URL) -> [String]?)?

    @MainActor
    init(
        source: Any? = nil,
        operationMask: NSDragOperation = [.copy, .move],
        pasteboard: NSPasteboard? = nil,
        location: NSPoint = .zero,
        namesOfPromisedFiles: (@Sendable (URL) -> [String]?)? = nil,
    ) {
        draggingSource = source
        draggingSourceOperationMask = operationMask
        draggingPasteboard = pasteboard
            ?? NSPasteboard(name: NSPasteboard.Name("EOP002-Fixture-\(UUID().uuidString)"))
        draggingLocation = location
        draggedImageLocation = location
        namesOfPromisedFilesHandler = namesOfPromisedFiles
        super.init()
    }

    func slideDraggedImage(to _: NSPoint) {}

    override func namesOfPromisedFilesDropped(atDestination destination: URL) -> [String]? {
        namesOfPromisedFilesHandler?(destination)
    }

    func enumerateDraggingItems(
        options _: NSDraggingItemEnumerationOptions,
        for _: NSView?,
        classes _: [AnyClass],
        searchOptions _: [NSPasteboard.ReadingOptionKey: Any],
        using visitor: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void,
    ) {
        enumerateDraggingItemsCallCount += 1
        for (index, receiver) in enumeratedReceivers.enumerated() {
            let item = ReceiverDraggingItem(receiver: receiver)
            var stop: ObjCBool = false
            visitor(item, index, &stop)
        }
    }

    func resetSpringLoading() {}
}

/// `NSDraggingItem.item`은 get-only라 receiver 노출용으로 getter만 교체한다.
/// 실제 AppKit 드래그와 동일하게 visitor가 `item as? NSFilePromiseReceiver`로 복원한다.
private final class ReceiverDraggingItem: NSDraggingItem {
    private let promisedReceiver: NSFilePromiseReceiver

    init(receiver: NSFilePromiseReceiver) {
        promisedReceiver = receiver
        super.init(pasteboardWriter: NSPasteboardItem())
    }

    override var item: Any {
        promisedReceiver
    }
}
