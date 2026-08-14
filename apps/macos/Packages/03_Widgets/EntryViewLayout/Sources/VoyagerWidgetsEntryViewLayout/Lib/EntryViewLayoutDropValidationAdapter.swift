@preconcurrency import AppKit
import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesEntry

/// Grid/List drop validation·acceptance를 공유하는 stateless adapter.
/// active `draggingSource` identity로 내부/외부 drag를 분류하고,
/// 외부 drag는 active pasteboard를 원자적으로 파싱해 검증한다.
/// source path는 invocation-local이며 reducer state나 named transport에 저장하지 않는다.
enum EntryViewLayoutDropValidationAdapter {
    /// resolveDropOrigin의 결과: active source와 drag origin 분류 결과.
    struct DropOrigin {
        var sourcePaths: [String]
        var wantsCopy: Bool
        var isInternal: Bool
    }

    /// drag origin을 `draggingSource` identity로 분류한다.
    /// 내부 drag는 오직 `draggingSource`가 layout 자체 view(`ownView`)와 동일한 경우에만 인정한다.
    /// `draggingSource`가 nil이거나 다른 객체면 외부 drag로 보고 active pasteboard를 사용한다.
    /// 저장된 transport path는 incoming drop 분류의 근거로 사용하지 않는다.
    @MainActor
    static func isInternalDrag(_ draggingInfo: any NSDraggingInfo, ownView: AnyObject?) -> Bool {
        guard let source = draggingInfo.draggingSource, let ownView else { return false }
        return (source as AnyObject) === ownView
    }

    @MainActor
    static func resolve(
        draggingInfo: any NSDraggingInfo,
        destinationPath: String,
    ) -> EntryDropValidationResult {
        resolve(
            sourcePaths: sourcePaths(from: draggingInfo.draggingPasteboard),
            destinationPath: destinationPath,
            allowedOperations: draggingInfo.draggingSourceOperationMask,
            prefersCopy: NSEvent.modifierFlags.contains(.option),
        )
    }

    /// 외부 drag의 active pasteboard에서 source path를 원자적으로 추출한다.
    /// `pasteboardItems`를 전체 검사해 모든 item이 실제 file URL일 때만 반환하고,
    /// 하나라도 지원하지 않는 item이 있으면 전체 session을 거부(빈 배열)한다.
    /// `readObjects`처럼 지원 항목만 조용히 걸러내는 동작은 하지 않는다.
    /// 입력 순서를 보존하면서 중복 경로를 제거한다.
    @MainActor
    static func sourcePaths(from pasteboard: NSPasteboard) -> [String] {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return [] }
        var paths: [String] = []
        var seen: Set<String> = []
        paths.reserveCapacity(items.count)
        for item in items {
            guard let url = fileURL(from: item) else { return [] }
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted {
                paths.append(path)
            }
        }
        return paths
    }

    /// reducer `resolveDropValidation`과 동일한 검증 primitive를 공유한다.
    /// 빈 source는 `EntryDropValidationResolver`가 no-op으로 resolve한다.
    static func resolve(
        sourcePaths: [String],
        destinationPath: String,
        allowedOperations: NSDragOperation,
        prefersCopy: Bool,
    ) -> EntryDropValidationResult {
        EntryDropValidationResolver.resolve(.init(
            sourcePaths: sourcePaths,
            destinationPath: destinationPath,
            allowedOperationsRawValue: allowedOperations.rawValue,
            prefersCopy: prefersCopy,
        ))
    }

    static func dragOperation(from operation: EntryDropResolvedOperation) -> NSDragOperation {
        switch operation {
        case .none:
            []
        case .copy:
            .copy
        case .move:
            .move
        }
    }

    private static func fileURL(from item: NSPasteboardItem) -> URL? {
        let fileURLType = NSPasteboard.PasteboardType(UTType.fileURL.identifier)
        guard item.availableType(from: [fileURLType]) != nil else { return nil }
        let string = item.string(forType: fileURLType)
            ?? item.data(forType: fileURLType).flatMap { String(data: $0, encoding: .utf8) }
        guard let string, let url = URL(string: string), url.isFileURL else { return nil }
        return url
    }
}
