@preconcurrency import AppKit
import Foundation
import os
import UniformTypeIdentifiers
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations

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

    /// 하나의 logical drag item이 노출하는 표현 후보.
    /// item마다 정확히 하나의 표현을 우선순위(promise > file URL > legacy filename > data flavor)대로 선택한다.
    /// data flavor는 형식 하드코딩 없이 UTI만 기록한다.
    enum ExternalDropItemRepresentation: Equatable {
        case promisedFile
        case immediateFileURL(path: String)
        case legacyFilename(String)
        case dataFlavor(uti: String)
    }

    /// 즉시 file URL descriptor. `sourcePaths(from:)`의 순서/dedup 계약을 유지한다.
    struct ExternalDropImmediateURLDescriptor: Equatable {
        var path: String
    }

    /// data-flavor descriptor. `ordinal`은 pasteboard item 순번, `uti`는 물리화할 형식.
    struct ExternalDropDataFlavorDescriptor: Equatable {
        var ordinal: Int
        var uti: String
    }

    /// Grid/List가 공유하는 negotiated output.
    /// 외부 drag의 logical item별 표현을 promise-first로 확정한 결과다.
    struct ExternalDropNegotiation: Equatable {
        var wantsCopy: Bool
        var immediateURLDescriptors: [ExternalDropImmediateURLDescriptor]
        var promisedOrdinals: [Int]
        var dataFlavors: [ExternalDropDataFlavorDescriptor]

        var acceptableLogicalItemCount: Int {
            immediateURLDescriptors.count + promisedOrdinals.count + dataFlavors.count
        }
    }

    /// Grid/List가 등록해야 하는 dragged types.
    /// `.fileURL` + 모든 promise readable types + legacy filenames + 데이터 전용 표면을
    /// 중복 없이 결정적 순서로 반환한다.
    ///
    /// 데이터 표면은 `UTType.data`(적합성 매칭에 의존하는 범용 후보)와 콘크리트 표준 타입
    /// (`.string`/`.html`/`.rtf`/`.tiff`/`.png`/`.pdf`)으로 구성한다. 이는 AppKit의
    /// `draggingEntered`/`validateDrop` 매칭을 위한 등록 표면일 뿐이며, 핸들링 로직은
    /// 여전히 `dataFlavorUTI` 범용 경유로 형식 목록 없이 수행한다 (포맷 하드코딩이 아니다).
    @MainActor static var registeredDraggedTypes: [NSPasteboard.PasteboardType] {
        var types: [NSPasteboard.PasteboardType] = [.fileURL]
        types.append(contentsOf: NSFilePromiseReceiver.readableDraggedTypes.map {
            NSPasteboard.PasteboardType($0)
        })
        types.append(contentsOf: legacyPromiseTypes.sorted { $0.rawValue < $1.rawValue })
        types.append(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        // 데이터 전용 외부 드래그(예: Numbers 셀)가 view에 도달하도록 등록 표면을 추가한다.
        // 적합성(conformance) 매칭을 타는 범용 후보 + 적합성 매칭이 실패하는 경우의 안전망.
        types.append(NSPasteboard.PasteboardType(UTType.data.identifier))
        types.append(contentsOf: [
            .string,
            .html,
            .rtf,
            .tiff,
            .png,
            .pdf,
        ])
        var seen = Set<NSPasteboard.PasteboardType>()
        var result: [NSPasteboard.PasteboardType] = []
        for type in types where seen.insert(type).inserted {
            result.append(type)
        }
        return result
    }

    /// active pasteboard의 logical item별 표현을 원자적으로 검사한다.
    /// ordinals(입력 순서)를 보존하고, 지원하지 않는 item이 하나라도 있으면 nil(전체 거절)을 반환한다.
    /// item이 promise/file URL/legacy filename 중 어느 것도 아니지만 다른 로드 가능한
    /// data flavor를 노출하면 `.dataFlavor(uti:)`로 수용한다 (형식 하드코딩 없음).
    @MainActor
    static func inspectExternalDropItems(from pasteboard: NSPasteboard) -> [ExternalDropItemRepresentation]? {
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
            if let filename = item.string(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) {
                result.append(.legacyFilename(filename))
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
    static func hasSupportedExternalRepresentation(in pasteboard: NSPasteboard) -> Bool {
        guard let representations = inspectExternalDropItems(from: pasteboard), !representations.isEmpty else {
            return false
        }
        return true
    }

    /// external drag를 promise-first로 negotiation한 결과를 반환한다.
    /// Grid/List validateDrop/acceptDrop이 공유해 copy/move resolution 전에 소비한다.
    /// 빈 pasteboard 또는 지원하지 않는 item이 하나라도 있으면 acceptable logical item 0개로 거절한다.
    @MainActor
    static func negotiateExternalDrop(
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

    private static func fileURL(from item: NSPasteboardItem) -> URL? {
        let fileURLType = NSPasteboard.PasteboardType(UTType.fileURL.identifier)
        guard item.availableType(from: [fileURLType]) != nil else { return nil }
        let string = item.string(forType: fileURLType)
            ?? item.data(forType: fileURLType).flatMap { String(data: $0, encoding: .utf8) }
        guard let string, let url = URL(string: string), url.isFileURL else { return nil }
        return url
    }
}

// MARK: - Shared external-drop acquisition coordinator logic (Grid/List)

extension EntryViewLayoutDropValidationAdapter {
    private struct MailMessageDropDescriptor {
        var lookup: MailMessageSourceLookup
        var subject: String?
    }

    /// 외부 drop 획득 세션을 시작할 때 coordinator가 공급하는 획득/알림 클로저 모음.
    /// `function_parameter_count` 린트 제약을 위해 하나의 컨텍스트로 묶는다.
    struct ExternalDropAcquisitionContext {
        var client: ExternalDropAcquisitionClient
        var sendAccepted: (ExternalDropAcceptedRequest) -> Void
        var clearDropState: () -> Void
    }

    /// promise/mixed 외부 drop의 획득 세션을 시작한다.
    /// 진행 중인 외부 세션이 있으면 거절하고, `.copy` semantics로 `begin`을 호출한 뒤
    /// 반환된 Sendable accepted action만 EntryOperations로 보낸다. transport/hover는 정리한다.
    /// Grid/List가 한 구현을 공유한다 (Todo 5 Must-not, review rule #3).
    @MainActor
    static func beginExternalDropAcquisition(
        activeSessionID: inout ExternalDropSessionID?,
        context: ExternalDropAcquisitionContext,
        draggingInfo: any NSDraggingInfo,
        negotiation: ExternalDropNegotiation,
        destinationPath: String,
    ) -> Bool {
        guard activeSessionID == nil else {
            validationLogger.info("acquisition rejected duplicate-session")
            // 이미 진행 중인 외부 세션이 있으면 두 번째 accept를 거절한다.
            return false
        }
        if let accepted = beginMailMessageDrop(
            activeSessionID: &activeSessionID,
            context: context,
            pasteboard: draggingInfo.draggingPasteboard,
            destinationPath: destinationPath,
        ) {
            return accepted
        }
        if !negotiation.promisedOrdinals.isEmpty,
           declaresLegacyFilePromise(in: draggingInfo.draggingPasteboard)
        {
            validationLogger.info("acquisition path legacy-promise")
            return beginLegacyPromisedFiles(
                activeSessionID: &activeSessionID,
                context: context,
                draggingInfo: draggingInfo,
                negotiation: negotiation,
                destinationPath: destinationPath,
            )
        }
        guard let (receivers, combinedDataFlavors) = resolvedAcquisitionInputs(
            from: draggingInfo,
            negotiation: negotiation,
        ) else {
            validationLogger.info("acquisition rejected receiver/data count mismatch")
            context.clearDropState()
            return false
        }
        logAcquisitionBegin(
            receivers: receivers,
            combinedDataFlavors: combinedDataFlavors,
            negotiation: negotiation,
        )
        guard !receivers.isEmpty || !combinedDataFlavors.isEmpty else {
            validationLogger.info("acquisition rejected no-receivers")
            context.clearDropState()
            return false
        }
        validationLogger
            .info("acquisition path \(receivers.isEmpty ? "data-only" : "modern-promise", privacy: .public)")
        // promise/mixed/data 외부 drop은 항상 `.copy`를 사용하고 path 기반 move(`dropItems` false)를 내지 않는다.
        // mixed drop의 즉시 file URL은 promise/materialization과 함께 복사 배치에 포함시켜 누락을 막는다.
        let immediateURLPaths = negotiation.immediateURLDescriptors.map(\.path)
        let request = context.client.begin(receivers, combinedDataFlavors, destinationPath, true, immediateURLPaths)
        activeSessionID = request.sessionID
        context.sendAccepted(request)
        context.clearDropState()
        return true
    }

    /// receiver/data-flavor 추출을 수행하되, negotiation이 확정한 promised/data 수와
    /// 실제 추출 결과 수가 일치하지 않으면 일부 logical item의 조용한 누락을 막기 위해
    /// nil(전체 거절)을 반환한다.
    @MainActor
    private static func resolvedAcquisitionInputs(
        from draggingInfo: any NSDraggingInfo,
        negotiation: ExternalDropNegotiation,
    ) -> ([NSFilePromiseReceiver], [ExternalDropDataFlavor])? {
        guard let receivers = promiseReceivers(from: draggingInfo, promisedOrdinals: negotiation.promisedOrdinals),
              let combinedDataFlavors = dataFlavorPayloads(
                  from: draggingInfo.draggingPasteboard,
                  negotiation: negotiation,
              )
        else {
            return nil
        }
        return (receivers, combinedDataFlavors)
    }

    /// 획득 진입 요약 로깅. negotiation이 확정한 표현 수/종류와 receiver 구조만 기록한다(파일명·경로 금지).
    @MainActor
    private static func logAcquisitionBegin(
        receivers: [NSFilePromiseReceiver],
        combinedDataFlavors: [ExternalDropDataFlavor],
        negotiation: ExternalDropNegotiation,
    ) {
        let emptyReceiverFileNames = receivers.isEmpty || receivers.allSatisfy(\.fileNames.isEmpty)
        validationLogger.info(
            """
            acquisition begin promised=\(negotiation.promisedOrdinals.count, privacy: .public) \
            immediate=\(negotiation.immediateURLDescriptors.count, privacy: .public) \
            data=\(combinedDataFlavors.count, privacy: .public) \
            receivers=\(receivers.count, privacy: .public) \
            emptyReceiverFileNames=\(emptyReceiverFileNames, privacy: .public)
            """,
        )
    }

    @MainActor
    private static func beginMailMessageDrop(
        activeSessionID: inout ExternalDropSessionID?,
        context: ExternalDropAcquisitionContext,
        pasteboard: NSPasteboard,
        destinationPath: String,
    ) -> Bool? {
        guard let deferredFlavors = mailDeferredFlavors(
            from: pasteboard,
            loadSource: context.client.loadMailSource,
        ) else {
            return nil
        }
        guard !deferredFlavors.isEmpty else {
            validationLogger.info("acquisition rejected mail-identity-unusable")
            context.clearDropState()
            return false
        }
        // Mail 원문 export는 다중 MB `source` 전송에 수 초가 걸리므로 acceptDrop 동기
        // 경로에서 분리한다. load는 세션 OperationQueue에서 실행되고 결과는 기존
        // `.received`/종단 이벤트 스트림으로 흐른다.
        let request = context.client.beginDeferred(deferredFlavors, destinationPath, true)
        activeSessionID = request.sessionID
        context.sendAccepted(request)
        context.clearDropState()
        validationLogger.info("acquisition path message-url files=\(deferredFlavors.count, privacy: .public)")
        return true
    }

    @MainActor
    private static func mailDeferredFlavors(
        from pasteboard: NSPasteboard,
        loadSource: @escaping @Sendable (MailMessageSourceLookup) -> Data?,
    ) -> [ExternalDropDeferredFlavor]? {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return nil }
        var descriptors: [MailMessageDropDescriptor] = []
        for item in items {
            guard let itemDescriptors = mailMessageDescriptors(from: item) else { return nil }
            descriptors.append(contentsOf: itemDescriptors)
        }
        guard !descriptors.isEmpty else { return nil }

        var result: [ExternalDropDeferredFlavor] = []
        var usedFilenames = Set<String>()
        result.reserveCapacity(descriptors.count)
        let emailUTI = UTType(filenameExtension: "eml")?.identifier ?? "com.apple.mail.email"
        for (ordinal, descriptor) in descriptors.enumerated() {
            let filename = ExternalDropDataFlavorNaming.mailMessageFilename(
                subject: descriptor.subject,
                ordinal: ordinal + 1,
                usedFilenames: &usedFilenames,
            )
            let lookup = descriptor.lookup
            result.append(ExternalDropDeferredFlavor(uti: emailUTI, filename: filename) {
                loadSource(lookup)
            })
        }
        return result
    }

    private static func mailMessageDescriptors(from item: NSPasteboardItem) -> [MailMessageDropDescriptor]? {
        let automatorType = NSPasteboard.PasteboardType("com.apple.mail.PasteboardTypeAutomator")
        if let data = item.data(forType: automatorType),
           let records = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
           as? [[String: Any]],
           !records.isEmpty
        {
            let descriptors = records.compactMap { record -> MailMessageDropDescriptor? in
                guard let number = record["id"] as? NSNumber, number.intValue > 0 else { return nil }
                return MailMessageDropDescriptor(
                    lookup: MailMessageSourceLookup(numericID: number.intValue, messageID: nil),
                    subject: record["subject"] as? String,
                )
            }
            return descriptors.count == records.count ? descriptors : []
        }

        let urlType = NSPasteboard.PasteboardType("public.url")
        guard let rawURL = item.string(forType: urlType),
              let lookup = MailMessageSourceLookup(pasteboardURL: rawURL)
        else {
            return nil
        }
        return [
            MailMessageDropDescriptor(
                lookup: lookup,
                subject: item.string(forType: NSPasteboard.PasteboardType("public.url-name")),
            ),
        ]
    }

    /// 레거시 promise 유형 상수들. type 존재 여부로만 판정한다(포맷 switch 없음).
    ///
    /// `com.apple.pasteboard.promised-file-url`만 레거시 promised-file 방식의 고유 마커다.
    /// `promised-file-content-type`은 `NSFilePromiseProvider`(현대 promise)도 함께 쓰므로
    /// 레거시 구분자로 쓰면 일반 promise 드래그까지 폴백으로 오인된다. Mail 실측 pasteboard는
    /// `promised-file-url`을 선언하므로 이 유형 존재만으로 정확히 판정한다.
    private static let legacyPromiseTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
    ]

    /// pasteboard가 레거시 promised-file 유형을 선언하는지 판정한다.
    @MainActor
    private static func declaresLegacyFilePromise(in pasteboard: NSPasteboard) -> Bool {
        guard let items = pasteboard.pasteboardItems else { return false }
        return items.contains { item in
            item.types.contains { legacyPromiseTypes.contains($0) }
        }
    }

    /// 레거시 promised-file 폴백: `acceptDrop` 내부에서 source에 staging으로의 파일 쓰기를 요청하고,
    /// 쓰여진 파일을 staging에서 검증해 세션에 received-item으로 주입한다.
    /// 가드레일 준수: 이 호출은 acceptDrop 콜백 내부에서만 수행한다.
    @MainActor
    private static func beginLegacyPromisedFiles(
        activeSessionID: inout ExternalDropSessionID?,
        context: ExternalDropAcquisitionContext,
        draggingInfo: any NSDraggingInfo,
        negotiation: ExternalDropNegotiation,
        destinationPath: String,
    ) -> Bool {
        let sessionID = ExternalDropSessionID()
        let stagingURL = URL(fileURLWithPath: destinationPath, isDirectory: true)
            .appendingPathComponent(".voyager-external-drop-\(sessionID.rawValue)")
        do {
            try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        } catch {
            context.clearDropState()
            return false
        }

        // source가 staging에 파일을 동기적으로 쓴다(acceptDrop 콜백 내부).
        let names = draggingInfo.namesOfPromisedFilesDropped(atDestination: stagingURL) ?? []
        let stagedPaths = names.compactMap { name -> String? in
            // 일부 source는 절대 경로를, 일부는 이름만 반환한다. 둘 다 staging 내로 정규화한다.
            let url = name.hasPrefix("/")
                ? URL(fileURLWithPath: name).standardizedFileURL
                : stagingURL.appendingPathComponent(name).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path),
                  isInsideDirectory(url.path, of: stagingURL.path)
            else {
                return nil
            }
            return url.path
        }
        // promised 이름 수와 실제 staging 물리화 수가 정확히 일치해야 한다. 일부만 성공한
        // 나머지로 세션을 성공시켜 조용히 누락하는 대신 staging을 정리하고 전체를 거절한다.
        guard !names.isEmpty, stagedPaths.count == names.count else {
            logger.info("legacy promise incomplete (session \(sessionID.rawValue, privacy: .public))")
            try? FileManager.default.removeItem(at: stagingURL)
            context.clearDropState()
            return false
        }
        let request = context.client.beginLegacy(stagedPaths, stagingURL.path, destinationPath, true)
        // legacy 경로도 negotiation이 확정한 즉시 URL을 병합해 modern 경로와 동일한
        // ordered placement plan으로 전달한다(조용한 누락 방지).
        let mergedRequest = ExternalDropAcceptedRequest(
            sessionID: request.sessionID,
            destination: request.destination,
            orderedPromisedNames: request.orderedPromisedNames,
            promisedOrdinals: request.promisedOrdinals,
            forcedCopy: request.forcedCopy,
            stagingDirectory: request.stagingDirectory,
            immediateURLPaths: negotiation.immediateURLDescriptors.map(\.path),
        )
        activeSessionID = mergedRequest.sessionID
        context.sendAccepted(mergedRequest)
        context.clearDropState()
        logger.info("legacy fallback invoked files=\(stagedPaths.count, privacy: .public)")
        return true
    }

    private static func isInsideDirectory(_ path: String, of directory: String) -> Bool {
        let dirComponents = URL(fileURLWithPath: directory).standardizedFileURL.pathComponents
        let fileComponents = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        return fileComponents.starts(with: dirComponents) && fileComponents.count > dirComponents.count
    }

    private static let logger = Logger(subsystem: "fm.voyager.external-drop", category: "legacy-fallback")

    /// 검증→수용 구간 진단 로거. count/종류/결과만 기록하고 파일명·경로·내용은 금지한다.
    static let validationLogger = Logger(subsystem: "fm.voyager.external-drop", category: "validation")

    /// negotiation이 확정한 promised ordinal 순서대로 `NSFilePromiseReceiver`를 추출한다.
    ///
    /// AppKit drop 계약대로 active `NSDraggingInfo`의 dragging item을 열거해 receiver를 받는다.
    /// 테스트 fixture처럼 열거 결과가 없는 경우에만 pasteboard reading으로 보완한다.
    /// negotiation이 확정한 promised 수와 수신된 receiver 수가 정확히 일치하지 않으면
    /// 일부 logical item이 조용히 누락되는 것을 막기 위해 nil(전체 거절)을 반환한다.
    @MainActor
    static func promiseReceivers(
        from draggingInfo: any NSDraggingInfo,
        promisedOrdinals: [Int],
    ) -> [NSFilePromiseReceiver]? {
        guard !promisedOrdinals.isEmpty else { return [] }
        var receivers: [NSFilePromiseReceiver] = []
        draggingInfo.enumerateDraggingItems(
            options: [],
            for: nil,
            classes: [NSFilePromiseReceiver.self],
            searchOptions: [:],
        ) { draggingItem, _, _ in
            guard let receiver = draggingItem.item as? NSFilePromiseReceiver else { return }
            receivers.append(receiver)
        }
        if receivers.isEmpty {
            receivers = draggingInfo.draggingPasteboard.readObjects(
                forClasses: [NSFilePromiseReceiver.self],
                options: [:],
            ) as? [NSFilePromiseReceiver] ?? []
        }
        guard receivers.count == promisedOrdinals.count else {
            return nil
        }
        return receivers
    }

    /// negotiation이 확정한 data-flavor ordinal/UTI 순서대로 pasteboard에서 바이트를 추출해
    /// Sendable `ExternalDropDataFlavor`로 변환한다. pasteboard item(AppKit)은 여기서 소비하고
    /// 넘어가는 값은 전부 Sendable이다. 바이트는 그대로(변환 없이) 보존한다.
    /// negotiation이 확정한 data-flavor 수와 실제 추출된 payload 수가 일치하지 않으면
    /// 일부 logical item이 조용히 누락되는 것을 막기 위해 nil(전체 거절)을 반환한다.
    @MainActor
    static func dataFlavorPayloads(
        from pasteboard: NSPasteboard,
        negotiation: ExternalDropNegotiation,
    ) -> [ExternalDropDataFlavor]? {
        guard let items = pasteboard.pasteboardItems else { return [] }
        var result: [ExternalDropDataFlavor] = []
        result.reserveCapacity(negotiation.dataFlavors.count)
        for descriptor in negotiation.dataFlavors {
            guard items.indices.contains(descriptor.ordinal) else { return nil }
            let item = items[descriptor.ordinal]
            guard let bytes = item.data(forType: NSPasteboard.PasteboardType(descriptor.uti)) else { return nil }
            let filename = ExternalDropDataFlavorNaming.filename(
                uti: descriptor.uti,
                bytes: bytes,
                ordinal: descriptor.ordinal + 1,
            )
            result.append(ExternalDropDataFlavor(uti: descriptor.uti, bytes: bytes, filename: filename))
        }
        return result
    }

    /// 현재 활성 외부 drop 획득 세션이 있으면 해당 세션만 취소하고 정리한다.
    /// representable teardown / current-path change에서 호출되며, 취소된 세션이 다음 Grid/List 세션을 오염시키지 않는다.
    @MainActor
    static func cancelActiveExternalDropSession(
        activeSessionID: inout ExternalDropSessionID?,
        client: ExternalDropAcquisitionClient,
        sendCancelSession: (ExternalDropSessionID) -> Void,
    ) {
        guard let sessionID = activeSessionID else { return }
        activeSessionID = nil
        client.cancel(sessionID)
        sendCancelSession(sessionID)
    }

    /// 세션 종단(성공/실패/취소)을 관찰해 coordinator의 `activeExternalDropSessionID`를 정리한다.
    ///
    /// EntryOperations reducer는 종단 이벤트(`.succeeded`/`.failed`/`.cancelled`)에서
    /// `state.activeExternalDrop`을 nil로 만든다. coordinator는 render loop에서 그 전이
    /// (non-nil → nil)를 관찰해 자신이 소유한 세션 ID를 해제한다. 이로써 한 폴더에서 성공한
    /// 외부 drop 이후에도 같은 폴더에서 다음 promise drop이 다시 수락된다.
    static func handleExternalDropSessionTerminal(
        activeSessionID: inout ExternalDropSessionID?,
        previousActive: ExternalDropActiveSession?,
        currentActive: ExternalDropActiveSession?,
    ) {
        guard previousActive != nil, currentActive == nil else { return }
        activeSessionID = nil
    }
}
