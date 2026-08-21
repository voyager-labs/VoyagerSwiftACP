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

    /// 외부 drop validate의 단일 판정 결과. Grid/List가 공유한다.
    enum DropVerdict: Equatable {
        case none
        case copy
        case move
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
        types.append(contentsOf: ExternalDropNegotiation.legacyPromiseTypes.sorted { $0.rawValue < $1.rawValue })
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
    /// `pasteboardItems`를 전체 검사해 모든 item이 실제 file URL이거나 legacy filename일 때만
    /// 반환하고, 하나라도 지원하지 않는 item이 있으면 전체 session을 거부(빈 배열)한다.
    /// `readObjects`처럼 지원 항목만 조용히 걸러내는 동작은 하지 않는다.
    /// 입력 순서를 보존하면서 중복 경로를 제거한다.
    @MainActor
    static func sourcePaths(from pasteboard: NSPasteboard) -> [String] {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return [] }
        var paths: [String] = []
        var seen: Set<String> = []
        paths.reserveCapacity(items.count)
        for item in items {
            if let url = ExternalDropNegotiation.fileURL(from: item) {
                let path = url.standardizedFileURL.path
                if seen.insert(path).inserted {
                    paths.append(path)
                }
            } else if let filename = item.string(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) {
                // legacy filename-only 드롭(코멘트 #3826760211): file URL이 없는 item도
                // legacy filename 문자열을 경로로 추출해 validate/accept를 일관되게 만든다.
                // 그래야 validate에서 `.copy`를 제안한 뒤 accept가 빈 source로 거절되는
                // 불일치가 사라진다.
                if seen.insert(filename).inserted {
                    paths.append(filename)
                }
            } else {
                return []
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

    /// 외부 drop validate 판정의 단일 진입점. Grid/List `validateDrop`이 공유한다.
    /// promise 우선 → 빈 source 표현 검증 → path/operation 검증 순서를 한 곳에서 소유한다.
    /// `state.isDropTargeted` 값은 호출자가 변경 시에만 전송하도록 verdict로만 판정한다.
    @MainActor
    static func resolveExternalDropOperation(
        draggingInfo: any NSDraggingInfo,
        isInternalDrag: Bool,
        sourcePaths: [String],
        destinationPath: String,
        allowedOperations: NSDragOperation,
        prefersCopy: Bool,
    ) -> DropVerdict {
        // promise/data 표현이 있으면 source path 유무와 무관하게 획득 경로가 우선한다 (VOY-736 Photos 회귀).
        if ExternalDropNegotiation.prefersPromiseAcquisition(
            draggingInfo: draggingInfo,
            isInternalDrag: isInternalDrag,
        ) {
            return .copy
        }
        // 빈 source는 항상 no-op으로 처리한다. 단, 외부 drag가 pasteboard에 지원 표현을 노출하면
        // `.copy`를 제안해 acceptDrop이 획득 세션을 시작할 수 있게 한다.
        if sourcePaths.isEmpty {
            let hasRepresentation = !isInternalDrag
                && ExternalDropNegotiation.hasSupportedExternalRepresentation(in: draggingInfo.draggingPasteboard)
            let operationRawValue = hasRepresentation ? NSDragOperation.copy.rawValue : NSDragOperation().rawValue
            validationLogger.info(
                "validate empty rep=\(hasRepresentation, privacy: .public) op=\(operationRawValue, privacy: .public)",
            )
            return hasRepresentation ? .copy : .none
        }
        // source path가 있는 일반 내부/외부 drag는 path/operation 검증을 탄다.
        let validation = resolve(
            sourcePaths: sourcePaths,
            destinationPath: destinationPath,
            allowedOperations: allowedOperations,
            prefersCopy: prefersCopy,
        )
        switch validation.resolvedOperation {
        case .none:
            return .none
        case .copy:
            return .copy
        case .move:
            return .move
        }
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

    static func dragOperation(from verdict: DropVerdict) -> NSDragOperation {
        switch verdict {
        case .none:
            []
        case .copy:
            .copy
        case .move:
            .move
        }
    }
}

// MARK: - Shared external-drop acquisition coordinator logic (Grid/List)

extension EntryViewLayoutDropValidationAdapter {
    /// Mail 메시지 드래그 한 건의 조회 키와 표시 제목.
    /// 보안 노트: pasteboard 발신 앱은 인증할 수 없다(PR #489 리뷰, confused deputy).
    /// 임의 앱이 Mail 타입을 위조해 Mail automation 조회를 유도할 수 있는 잔여 리스크를
    /// 인지하며, TCC automation 동의 프롬프트가 1차 게이트다. 기능 폐지(d20236a4a) 대신
    /// 복원을 선택한 근거를 이 문서화로 대신한다.
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
        // 혼합 drop의 즉시 file URL도 canonical 검증을 통과해야 한다. 순수 URL drop은
        // resolver가 destination 자체/조상 복사를 거절하지만, promise/data와 섞이면
        // 이 검증 없이 acquisition에 그대로 흘러들므로 동일 계약을 여기서 적용한다.
        if negotiation.immediateURLDescriptors.contains(where: { descriptor in
            resolve(
                sourcePaths: [descriptor.path],
                destinationPath: destinationPath,
                allowedOperations: [.copy],
                prefersCopy: true,
            ).resolvedOperation == .none
        }) {
            validationLogger.info("acquisition rejected immediate-url containment")
            context.clearDropState()
            return false
        }
        // Mail automator/message-url 드래그는 legacy promise 타입을 함께 선언하므로
        // legacy 폴백보다 먼저 판정해야 Mail 원문 경로로 들어간다.
        if let accepted = beginMailMessageDrop(
            activeSessionID: &activeSessionID,
            context: context,
            pasteboard: draggingInfo.draggingPasteboard,
            destinationPath: destinationPath,
        ) {
            return accepted
        }
        if !negotiation.promisedOrdinals.isEmpty,
           declaresLegacyFilePromise(in: draggingInfo.draggingPasteboard),
           // Photos 등 modern promise 앱도 legacy HFS marker(`promised-file-url`)를 호환용으로
           // 함께 선언한다. marker 존재만으로 legacy 폴백을 선택하면 modern 드래그가 HFS 경로로
           // 오류우팅돼 전체가 실패한다(VOY-736 Photos 회귀). 드래그 세션에 receiver가 있으면
           // (source가 NSFilePromiseProvider로 시작) modern 경로로 보내고, legacy 폴백은
           // receiver가 없는 레거시 드래그에만 적용한다. 판별에 pasteboard reading 폴백을
           // 쓰지 않는 이유: readObjects는 promised-file-content-type만 선언한 legacy
           // pasteboard에서도 receiver를 조립하므로 legacy 드래그를 modern로 오역한다.
           draggingItemPromiseReceivers(from: draggingInfo).isEmpty
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

    /// 신뢰할 수 없는 pasteboard item에서 Mail 조회 키를 추출한다. automator
    /// property-list 레코드의 id가 일부라도 무효(id<=0)하면 빈 배열(거부)을 반환하고,
    /// automator payload가 없으면 `message:` URL 폴백을 시도한다. 둘 다 없으면 nil
    /// (Mail 드래그가 아님)을 반환해 이후 표준 경로가 처리하게 한다.
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

    /// pasteboard가 레거시 promised-file 유형을 선언하는지 판정한다.
    @MainActor
    private static func declaresLegacyFilePromise(in pasteboard: NSPasteboard) -> Bool {
        guard let items = pasteboard.pasteboardItems else { return false }
        return items.contains { item in
            item.types.contains { ExternalDropNegotiation.legacyPromiseTypes.contains($0) }
        }
    }

    /// 레거시 promised-file 폴백: `acceptDrop` 내부에서 source에 staging으로의 파일 쓰기를 요청하고,
    /// 쓰여진 파일을 staging에서 검증해 세션에 received-item으로 주입한다.
    /// 가드레일 준수: 이 호출은 acceptDrop 콜백 내부에서만 수행한다. staging 생성·검증·실패
    /// 정리는 acquisition client가 단일 소유하고, adapter는 `namesOfPromisedFilesDropped` 호출과
    /// semantic 결과 전달만 담당한다.
    @MainActor
    private static func beginLegacyPromisedFiles(
        activeSessionID: inout ExternalDropSessionID?,
        context: ExternalDropAcquisitionContext,
        draggingInfo: any NSDraggingInfo,
        negotiation: ExternalDropNegotiation,
        destinationPath: String,
    ) -> Bool {
        guard let stagingPath = context.client.prepareLegacyStaging(destinationPath) else {
            logger.info("legacy promise staging prepare failed")
            context.clearDropState()
            return false
        }
        let stagingURL = URL(fileURLWithPath: stagingPath, isDirectory: true)
        // source가 staging에 파일을 동기적으로 쓴다(acceptDrop 콜백 내부).
        let names = draggingInfo.namesOfPromisedFilesDropped(atDestination: stagingURL) ?? []
        // negotiation이 확정한 promised cardinality와 staging 안 실제 물리화·존재·containment를
        // client의 finalizeLegacyStaging이 단일 검증하고, 불일치 시 staging을 정리한 뒤 전체를
        // 거절한다(조용한 부분 누락/잔류 차단).
        guard let stagedPaths = context.client.finalizeLegacyStaging(
            names,
            negotiation.promisedOrdinals.count,
            stagingPath,
        ) else {
            logger.info("legacy promise incomplete")
            context.clearDropState()
            return false
        }
        let request = context.client.beginLegacy(stagedPaths, stagingPath, destinationPath, true)
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
        let receivers = enumeratePromiseReceivers(from: draggingInfo)
        guard receivers.count == promisedOrdinals.count else {
            return nil
        }
        return receivers
    }

    /// 드래그에서 modern `NSFilePromiseReceiver`를 열거한다. dragging item 열거가 비면
    /// pasteboard reading으로 보완한다. modern 획득 경로의 receiver 소스다.
    @MainActor
    static func enumeratePromiseReceivers(from draggingInfo: any NSDraggingInfo) -> [NSFilePromiseReceiver] {
        let receivers = draggingItemPromiseReceivers(from: draggingInfo)
        guard receivers.isEmpty else { return receivers }
        return draggingInfo.draggingPasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: [:],
        ) as? [NSFilePromiseReceiver] ?? []
    }

    /// dragging item 열거로만 receiver를 수집한다. pasteboard reading은 legacy marker만
    /// 선언한 드래그에서도 receiver를 합성해낼 수 있어 legacy/modern 판별에는 부적합하다.
    @MainActor
    static func draggingItemPromiseReceivers(from draggingInfo: any NSDraggingInfo) -> [NSFilePromiseReceiver] {
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
}
