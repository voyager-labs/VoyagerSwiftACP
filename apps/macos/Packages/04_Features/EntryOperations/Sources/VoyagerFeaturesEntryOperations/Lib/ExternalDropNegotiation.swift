@preconcurrency import AppKit
import Foundation
import UniformTypeIdentifiers

/// 하나의 logical drag item이 노출하는 표현 후보.
/// item마다 정확히 하나의 표현을 우선순위(promise > file URL > legacy filename > data flavor)대로 선택한다.
/// data flavor는 형식 하드코딩 없이 UTI만 기록한다.
public enum ExternalDropItemRepresentation: Equatable {
    case promisedFile
    case immediateFileURL(path: String)
    case legacyFilename(String)
    case legacyFilenames([String])
    case dataFlavor(uti: String)
}

/// 즉시 file URL descriptor. `sourcePaths(from:)`의 순서/dedup 계약을 유지한다.
public struct ExternalDropImmediateURLDescriptor: Equatable {
    public var path: String

    public init(path: String) {
        self.path = path
    }
}

/// data-flavor descriptor. `ordinal`은 pasteboard item 순번, `uti`는 물리화할 형식.
public struct ExternalDropDataFlavorDescriptor: Equatable {
    public var ordinal: Int
    public var uti: String

    public init(ordinal: Int, uti: String) {
        self.ordinal = ordinal
        self.uti = uti
    }
}

/// 외부 drag item의 협상(negotiation) 도메인. widget(EntryViewLayout)이 공유하는
/// stateless 협상 타입과 static API를 소유한다. pasteboard의 logical item별 표현을
/// promise-first로 확정하고, Grid/List validateDrop/acceptDrop이 copy/move resolution
/// 전에 이 결과를 소비한다.
///
/// EntryViewLayoutDropValidationAdapter의 pure 협상 구현이 여기로 이동해 공개 경계를
/// 형성한다. 획득(acquisition) 도메인은 widget 쪽에 남는다. 이 타입 자체가 협상 결과이자
/// 협상 static API의 owner다.
public struct ExternalDropNegotiation: Equatable {
    public var wantsCopy: Bool
    public var immediateURLDescriptors: [ExternalDropImmediateURLDescriptor]
    public var promisedOrdinals: [Int]
    public var dataFlavors: [ExternalDropDataFlavorDescriptor]

    public var acceptableLogicalItemCount: Int {
        immediateURLDescriptors.count + promisedOrdinals.count + dataFlavors.count
    }

    public init(
        wantsCopy: Bool,
        immediateURLDescriptors: [ExternalDropImmediateURLDescriptor],
        promisedOrdinals: [Int],
        dataFlavors: [ExternalDropDataFlavorDescriptor],
    ) {
        self.wantsCopy = wantsCopy
        self.immediateURLDescriptors = immediateURLDescriptors
        self.promisedOrdinals = promisedOrdinals
        self.dataFlavors = dataFlavors
    }

    public static func legacyFilenames(from item: NSPasteboardItem) -> [String]? {
        let type = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        guard let propertyList = item.propertyList(forType: type) else {
            guard let filename = item.string(forType: type), !filename.isEmpty else { return nil }
            return [filename]
        }

        if let filenames = propertyList as? [String], !filenames.isEmpty {
            return filenames
        }
        if let values = propertyList as? [Any] {
            let filenames = values.compactMap { $0 as? String }
            guard filenames.count == values.count, !filenames.isEmpty else { return nil }
            return filenames
        }
        if let filename = propertyList as? String, !filename.isEmpty {
            return [filename]
        }
        return nil
    }

    /// active pasteboard의 logical item별 표현을 원자적으로 검사한다.
    /// ordinals(입력 순서)를 보존하고, 지원하지 않는 item이 하나라도 있으면 nil(전체 거절)을 반환한다.
    /// item이 promise/file URL/legacy filename 중 어느 것도 아니지만 다른 로드 가능한
    /// data flavor를 노출하면 `.dataFlavor(uti:)`로 수용한다 (형식 하드코딩 없음).
    @MainActor
    public static func inspectExternalDropItems(
        from pasteboard: NSPasteboard,
    ) -> [ExternalDropItemRepresentation]? {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return [] }
        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        var result: [ExternalDropItemRepresentation] = []
        result.reserveCapacity(items.count)
        for item in items {
            if item.availableType(from: promiseTypes) != nil
                || item.types.contains(where: legacyPromiseTypes.contains)
            {
                result.append(.promisedFile)
                continue
            }
            if let url = fileURL(from: item) {
                result.append(.immediateFileURL(path: url.standardizedFileURL.path))
                continue
            }
            if let filenames = legacyFilenames(from: item) {
                result.append(.legacyFilenames(filenames))
                continue
            }
            if let uti = dataFlavorUTI(from: item, promiseTypes: promiseTypes) {
                result.append(.dataFlavor(uti: uti))
                continue
            }
            return nil
        }
        return result
    }

    /// 외부 drag pasteboard가 지원 가능한 표현(promise/file URL/legacy filename)을
    /// 최소 1개 노출하는지 검사한다. `sourcePaths(from:)`이 빈 경우(예: promise drag)에
    /// validateDrop이 `.copy`를 제안할 수 있는지 판정한다.
    /// 빈 pasteboard 또는 지원하지 않는 item만 있는 경우 false를 반환한다.
    @MainActor
    public static func hasSupportedExternalRepresentation(in pasteboard: NSPasteboard) -> Bool {
        guard let representations = inspectExternalDropItems(from: pasteboard), !representations.isEmpty else {
            return false
        }
        return true
    }

    /// external drag를 promise-first로 negotiation한 결과를 반환한다.
    /// Grid/List validateDrop/acceptDrop이 공유해 copy/move resolution 전에 소비한다.
    /// 빈 pasteboard 또는 지원하지 않는 item이 하나라도 있으면 acceptable logical item 0개로 거절한다.
    @MainActor
    public static func negotiateExternalDrop(
        from pasteboard: NSPasteboard,
        wantsCopy: Bool,
    ) -> ExternalDropNegotiation {
        guard let representations = inspectExternalDropItems(from: pasteboard) else {
            return .init(
                wantsCopy: wantsCopy,
                immediateURLDescriptors: [],
                promisedOrdinals: [],
                dataFlavors: [],
            )
        }
        var descriptors: [ExternalDropImmediateURLDescriptor] = []
        var seen = Set<String>()
        var promisedOrdinals: [Int] = []
        var dataFlavors: [ExternalDropDataFlavorDescriptor] = []
        descriptors.reserveCapacity(representations.count)
        for (ordinal, representation) in representations.enumerated() {
            switch representation {
            case .promisedFile:
                promisedOrdinals.append(ordinal)
            case let .immediateFileURL(path):
                if seen.insert(path).inserted {
                    descriptors.append(.init(path: path))
                }
            case let .legacyFilename(filename):
                if seen.insert(filename).inserted {
                    descriptors.append(.init(path: filename))
                }
            case let .legacyFilenames(filenames):
                for filename in filenames where seen.insert(filename).inserted {
                    descriptors.append(.init(path: filename))
                }
            case let .dataFlavor(uti):
                dataFlavors.append(.init(ordinal: ordinal, uti: uti))
            }
        }
        return .init(
            wantsCopy: wantsCopy,
            immediateURLDescriptors: descriptors,
            promisedOrdinals: promisedOrdinals,
            dataFlavors: dataFlavors,
        )
    }

    /// 외부 드래그가 promise/data 표현을 노출하는지 판정한다 (Grid/List validateDrop 공용).
    /// Photos 등 modern promise 앱은 file URL을 함께 제공하므로 sourcePaths가 비지 않아도
    /// promise 획득 경로가 우선해야 한다(VOY-736 Photos 회귀: path 검증만 거치면 조용히
    /// 거부돼 acquisition 계층에 도달하지 못한다). 순수 file URL 드래그(Finder)와 내부
    /// 드래그는 promise 표현이 없어 기존 path 검증을 그대로 탄다.
    @MainActor
    public static func prefersPromiseAcquisition(
        draggingInfo: any NSDraggingInfo,
        isInternalDrag: Bool,
    ) -> Bool {
        guard !isInternalDrag else { return false }
        let negotiation = negotiateExternalDrop(
            from: draggingInfo.draggingPasteboard,
            wantsCopy: false,
        )
        return !negotiation.promisedOrdinals.isEmpty || !negotiation.dataFlavors.isEmpty
    }

    /// 레거시 promise 유형 상수들. type 존재 여부로만 판정한다(포맷 switch 없음).
    ///
    /// `com.apple.pasteboard.promised-file-url`만 레거시 promised-file 방식의 고유 마커다.
    /// `promised-file-content-type`은 `NSFilePromiseProvider`(현대 promise)도 함께 쓰므로
    /// 레거시 구분자로 쓰면 일반 promise 드래그까지 폴백으로 오인된다. Mail 실측 pasteboard는
    /// `promised-file-url`을 선언하므로 이 유형 존재만으로 정확히 판정한다.
    public static let legacyPromiseTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
    ]

    /// data-flavor 후보 UTI를 결정한다. promise/file URL/legacy filename 같은 구조적 타입을
    /// 제외한 나머지 노출 타입 중 text 계열을 우선해 첫 번째 로드 가능한 타입의 UTI를 반환한다.
    /// 형식 목록 없이 item이 노출하는 타입만으로 판정하므로 임의의 UTI를 수용한다.
    private static func dataFlavorUTI(
        from item: NSPasteboardItem,
        promiseTypes: [NSPasteboard.PasteboardType],
    ) -> String? {
        let fileURLType = NSPasteboard.PasteboardType(UTType.fileURL.identifier)
        let legacyType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        let structural = Set(promiseTypes + [fileURLType, legacyType])
        let candidates = item.types.map(\.rawValue).filter { !structural.contains(NSPasteboard.PasteboardType($0)) }
        guard !candidates.isEmpty else { return nil }
        if let text = candidates.first(where: isTextFlavor) {
            return text
        }
        return candidates.first
    }

    private static func isTextFlavor(_ uti: String) -> Bool {
        guard let type = UTType(uti) else { return false }
        return type.conforms(to: .text) || type.conforms(to: .plainText)
    }

    /// pasteboard item에서 file URL을 추출한다. widget의 `sourcePaths(from:)`도 이 구현을 공유한다.
    @MainActor
    public static func fileURL(from item: NSPasteboardItem) -> URL? {
        let fileURLType = NSPasteboard.PasteboardType(UTType.fileURL.identifier)
        guard item.availableType(from: [fileURLType]) != nil else { return nil }
        let string = item.string(forType: fileURLType)
            ?? item.data(forType: fileURLType).flatMap { String(data: $0, encoding: .utf8) }
        guard let string, let url = URL(string: string), url.isFileURL else { return nil }
        return url
    }
}
