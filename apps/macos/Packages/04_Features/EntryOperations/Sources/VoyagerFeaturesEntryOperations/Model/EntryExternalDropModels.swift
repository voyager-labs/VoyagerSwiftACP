import Foundation
import UniformTypeIdentifiers

/// 외부(external) Finder drop의 AppKit 기반 파일 획득을 표현하는 Sendable 값 타입 모음.
///
/// `NSFilePromiseReceiver` 같은 AppKit 객체는 여기에 절대 등장하지 않는다. 모든 타입은
/// 순수 값 타입이며 액션/이벤트/상태 경계를 가로질러 안전하게 전달된다. AppKit receiver는
/// `ExternalDropAcquisitionClient`의 private registry 안에서만 존재한다.
public enum EntryExternalDropModels {}

// MARK: - Session ID

/// 외부 drop 획득 세션을 결정적으로 식별하는 타입 ID.
/// begin 시점에 UUID 문자열로 생성되어 reducer/이벤트 경계로 전달된다.
public struct ExternalDropSessionID: Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        rawValue = UUID().uuidString
    }
}

// MARK: - Accepted request metadata

/// Grid/List `acceptDrop`에서 동기적으로 받아들인 외부 drop의 획득 요청 메타데이터.
/// 순서 보장된 immediate descriptors(프로미스 이름)와 promised ordinal 목록을 담는다.
public struct ExternalDropAcceptedRequest: Equatable, Sendable {
    /// 이 획득 세션을 가리키는 고유 식별자.
    public let sessionID: ExternalDropSessionID
    /// 파일이 배치될 최종 목적지 경로.
    public let destination: String
    /// 수신 즉시 순서가 보장된 promised file 이름 목록 (receiver.fileNames 기준).
    public let orderedPromisedNames: [String]
    /// 각 프로미스에 대응하는 콜백 순번. 한 receiver가 여러 파일을 산출하면 같은
    /// receiver index가 여러 번 나타난다.
    public let promisedOrdinals: [Int]
    /// Option 키 강제 복사 여부.
    public let forcedCopy: Bool
    /// 이 세션 전용 staging 디렉터리 경로.
    public let stagingDirectory: String
    /// mixed drop에서 promise/materialization 없이 즉시 획득 가능한 file URL 경로.
    /// accept 시점에 Voyager 보관 디렉터리로 pinning된 경로다(원본은 source 소유 유지).
    /// promise와 함께 온 즉시 URL이 조용히 누락되지 않도록 ordered import plan에 합쳐진다.
    public let immediateURLPaths: [String]
    /// `immediateURLPaths`와 1:1 대응하는 pasteboard logical item 순번. placement 통합
    /// 정렬에 쓰인다(코멘트 #3831133039).
    public let immediateOrdinals: [Int]

    public init(
        sessionID: ExternalDropSessionID,
        destination: String,
        orderedPromisedNames: [String],
        promisedOrdinals: [Int],
        forcedCopy: Bool,
        stagingDirectory: String,
        immediateURLPaths: [String] = [],
        immediateOrdinals: [Int] = [],
    ) {
        self.sessionID = sessionID
        self.destination = destination
        self.orderedPromisedNames = orderedPromisedNames
        self.promisedOrdinals = promisedOrdinals
        self.forcedCopy = forcedCopy
        self.stagingDirectory = stagingDirectory
        self.immediateURLPaths = immediateURLPaths
        self.immediateOrdinals = immediateOrdinals
    }
}

// MARK: - Received-file result

/// receiver 콜백을 통해 staging 디렉터리로 실제 수신된 파일 한 건.
/// item/callback ordinal과 staged 경로를 함께 보존해 순서 있는 결과로 전달한다.
public struct ExternalDropReceivedFile: Equatable, Sendable {
    /// 소속 세션.
    public let sessionID: ExternalDropSessionID
    /// 수신 파일의 항목 순번.
    public let itemOrdinal: Int
    /// 콜백 호출 순번.
    public let callbackOrdinal: Int
    /// staging 디렉터리 안의 실제 파일 경로.
    public let stagedPath: String
    /// placement 정렬용 수신기 순번(pasteboard 순서). data flavor/legacy는 -1이며,
    /// 콜백 도착 순서와 무관한 안정 정렬 키로 쓰인다(코멘트 #3830970670).
    public let pasteboardOrdinal: Int

    public init(
        sessionID: ExternalDropSessionID,
        itemOrdinal: Int,
        callbackOrdinal: Int,
        stagedPath: String,
        pasteboardOrdinal: Int = -1,
    ) {
        self.sessionID = sessionID
        self.itemOrdinal = itemOrdinal
        self.callbackOrdinal = callbackOrdinal
        self.stagedPath = stagedPath
        self.pasteboardOrdinal = pasteboardOrdinal
    }
}

// MARK: - Data-flavor materialization

/// accept 시 MainActor에서 pasteboard item으로부터 추출해 넘기는 data-flavor 물리화 요청 한 건.
/// AppKit pasteboard item은 넘기지 않고 UTI/바이트/확정된 파일명만 Sendable로 전달한다.
/// 바이트는 그대로(변환 없이) staging에 쓰인다.
public struct ExternalDropDataFlavor: Equatable, Sendable {
    /// 물리화할 형식의 UTI.
    public let uti: String
    /// verbatim으로 쓰일 원본 바이트.
    public let bytes: Data
    /// staging에 쓸 최종 파일명 (base name + 확장자).
    public let filename: String
    /// placement 통합 정렬에 쓰는 pasteboard logical item 순번(코멘트 #3831133039).
    public let ordinal: Int

    public init(uti: String, bytes: Data, filename: String, ordinal: Int = -1) {
        self.uti = uti
        self.bytes = bytes
        self.filename = filename
        self.ordinal = ordinal
    }
}

/// 지연 data-flavor 물리화 요청 한 건. `load`는 획득 세션이 소유한 OperationQueue에서
/// main thread 차단 없이 실행되며, 반환된 바이트가 로드 완료 후 staging에 verbatim으로 쓰인다.
/// 다중 MB 원문(Mail `source` export 등)을 acceptDrop 동기 경로에서 꺼내기 위해 사용한다.
public struct ExternalDropDeferredFlavor: Sendable {
    /// 물리화할 형식의 UTI.
    public let uti: String
    /// staging에 쓸 최종 파일명 (base name + 확장자).
    public let filename: String
    /// placement 통합 정렬에 쓰는 pasteboard logical item 순번(코멘트 #3831133039).
    public let ordinal: Int
    /// 원본 바이트를 비동기로 로드한다. nil을 반환하면 타입화 실패로 종단 처리된다.
    public let load: @Sendable () -> Data?

    /// true이면 로드된 바이트에서 파일명을 결정한다(pasteboard data flavor, 코멘트 #3837908192).
    public let nameFromBytes: Bool

    public init(
        uti: String,
        filename: String,
        ordinal: Int = -1,
        nameFromBytes: Bool = false,
        load: @escaping @Sendable () -> Data?,
    ) {
        self.uti = uti
        self.filename = filename
        self.ordinal = ordinal
        self.load = load
        self.nameFromBytes = nameFromBytes
    }
}

/// Mail 메시지 드래그의 원문 조회 키. Mail Automator payload의 numeric ID를 우선하고
/// 없으면 `message:` URL의 RFC Message-ID로 조회한다.
public struct MailMessageSourceLookup: Equatable, Sendable {
    /// Mail scripting의 mailbox 내부 numeric ID.
    public let numericID: Int?
    /// RFC 5322 Message-ID (`message:` URL에서 추출).
    public let messageID: String?

    public init(numericID: Int?, messageID: String?) {
        self.numericID = numericID
        self.messageID = messageID
    }

    /// `message:<Message-ID>` pasteboard URL에서 조회 키를 만든다. 스킴 불일치,
    /// percent-encoding 실패, 빈 값, CR/LF/NUL 포함, 998바이트 초과는 nil을 반환한다.
    public init?(pasteboardURL rawURL: String) {
        guard let separator = rawURL.firstIndex(of: ":"),
              rawURL[..<separator].lowercased() == "message"
        else {
            return nil
        }
        var encoded = String(rawURL[rawURL.index(after: separator)...])
        while encoded.hasPrefix("/") {
            encoded.removeFirst()
        }
        guard let decoded = encoded.removingPercentEncoding else { return nil }
        let messageID = decoded.trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "<>")),
        )
        guard !messageID.isEmpty,
              messageID.utf8.count <= 998,
              !messageID.contains("\r"),
              !messageID.contains("\n"),
              !messageID.contains("\0")
        else {
            return nil
        }
        numericID = nil
        self.messageID = messageID
    }
}

/// data-flavor 파일명 파생 규칙. 형식별 목록 없이 UTI/바이트만으로 이름을 결정한다.
/// 확장자는 `UTType.preferredFilenameExtension`에서 얻고, 없으면 supertype 계층을
/// 탐사하며, 그래도 없으면 단일 fallback 상수를 쓴다.
/// base name은 text 계열이면 첫 줄을 정리한 이름, 그 외엔 `Clipping <n>`.
public enum ExternalDropDataFlavorNaming {
    /// `UTType`이 확장자를 산출하지 못할 때(dynamic/미지 UTI) 쓰는 단일 기본 확장자.
    public static let defaultExtension = "data"

    /// base name의 UTF-8 바이트 상한. APFS component 한도(255 bytes)에서 확장자와
    /// 중복 접미사(` <n>`) 공간을 남긴 값이다(코멘트 #3830824367).
    private static let maxBaseNameUTF8Bytes = 200

    /// UTI 기반 확장자. `preferredFilenameExtension`이 없는 pasteboard 전용 UTI
    /// (`public.utf8-plain-text` 등)는 supertypes를 너비우선으로 순회해 확장자를 가진
    /// 가장 가까운 조상의 확장자를 사용한다. 그래도 없으면(dynamic/미지 UTI) fallback 상수.
    /// 같은 깊이에 확장자 조상이 여럿이면 결정론적으로(알파벳 순) 선택한다.
    public static func fileExtension(for uti: String) -> String {
        guard let type = UTType(uti) else { return defaultExtension }

        // 자기 자신이 직접 확장자를 선언했으면 그대로 사용한다.
        if let own = type.preferredFilenameExtension {
            return own
        }

        // supertypes를 BFS 레벨 단위로 탐사한다. public.data/public.item/public.content처럼
        // 확장자가 없는 조상은 자연스럽게 스킵되고, 처음으로 확장자가 등장한 깊이에서
        // 알파벳 순으로 결정론적으로 하나를 고른다.
        var currentLevel: [UTType] = Array(type.supertypes)
        var visited: Set<String> = [type.identifier]
        while !currentLevel.isEmpty {
            let candidates = currentLevel
                .compactMap(\.preferredFilenameExtension)
                .sorted()
            if let first = candidates.first {
                return first
            }
            var nextLevel: [UTType] = []
            for supertype in currentLevel where !visited.contains(supertype.identifier) {
                visited.insert(supertype.identifier)
                nextLevel.append(contentsOf: supertype.supertypes)
            }
            currentLevel = nextLevel
        }

        return defaultExtension
    }

    /// base name 결정: text 계열은 첫 줄을 정리한 이름, 그 외 `Clipping <n>` (1-based ordinal).
    public static func baseName(uti: String, bytes: Data, ordinal: Int) -> String {
        if isTextFlavor(uti), let name = sanitizedFirstLine(from: bytes), !name.isEmpty {
            return name
        }
        return "Clipping \(ordinal)"
    }

    /// UTI + 바이트 + ordinal로 최종 파일명을 산출한다.
    public static func filename(uti: String, bytes: Data, ordinal: Int) -> String {
        let ext = fileExtension(for: uti)
        let base = baseName(uti: uti, bytes: bytes, ordinal: ordinal)
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    /// 웹 링크 기반 `.webloc` 파일명. `public.url-name` 표시 이름을 우선하고 없으면 URL
    /// host·마지막 경로 성분을 쓴다(#3849679259). Finder의 `.webloc` 물리화와 대응한다.
    public static func weblocFilename(title: String?, rawURL: String) -> String {
        let trimmedTitle = title?
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ") ?? ""
        if !trimmedTitle.isEmpty {
            let sanitized = trimmedTitle
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            return "\(truncatedBaseName(sanitized, maxUTF8Bytes: maxBaseNameUTF8Bytes)).webloc"
        }
        if let url = URL(string: rawURL) {
            let host = url.host ?? ""
            let last = url.lastPathComponent
            let derived = [host, last]
                .filter { !$0.isEmpty }
                .joined(separator: " - ")
            if !derived.isEmpty {
                return "\(truncatedBaseName(derived, maxUTF8Bytes: maxBaseNameUTF8Bytes)).webloc"
            }
        }
        return "Web Link.webloc"
    }

    /// Mail 메시지 제목 기반 `.eml` 파일명. 공백 축약·경로 구분자 치환·파일시스템
    /// 바이트 제한을 적용하고 빈 제목이면 `Mail Message <n>`을 쓰며, 세션 내 중복은
    /// ` <n>` 접미로 회피한다.
    public static func mailMessageFilename(
        subject: String?,
        ordinal: Int,
        usedFilenames: inout Set<String>,
    ) -> String {
        let collapsed = subject?
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ") ?? ""
        let sanitized = collapsed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = sanitized.isEmpty
            ? "Mail Message \(ordinal)"
            : truncatedBaseName(sanitized, maxUTF8Bytes: maxBaseNameUTF8Bytes)
        let filename = "\(baseName).eml"
        guard !usedFilenames.contains(filename.lowercased()) else {
            let duplicate = "\(baseName) \(ordinal).eml"
            usedFilenames.insert(duplicate.lowercased())
            return duplicate
        }
        usedFilenames.insert(filename.lowercased())
        return filename
    }

    /// base name을 grapheme 경계에서 UTF-8 바이트 예산 안으로 자른다. 결합 이모지처럼
    /// 한 Character가 여러 바이트를 차지해도 component 한도를 초과하지 않게 한다.
    static func truncatedBaseName(_ name: String, maxUTF8Bytes: Int) -> String {
        guard name.utf8.count > maxUTF8Bytes else { return name }
        var result = ""
        var bytes = 0
        for character in name {
            let length = String(character).utf8.count
            if bytes + length > maxUTF8Bytes { break }
            result.append(character)
            bytes += length
        }
        return result
    }

    private static func isTextFlavor(_ uti: String) -> Bool {
        guard let type = UTType(uti) else { return false }
        return type.conforms(to: .text) || type.conforms(to: .plainText)
    }

    /// 첫 줄을 정리한 base name: trim·공백 축약·경로 구분자 제거·파일시스템 바이트 제한.
    private static func sanitizedFirstLine(from bytes: Data) -> String? {
        guard let text = String(data: bytes, encoding: .utf8) else { return nil }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let collapsed = firstLine
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let sanitized = collapsed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return nil }
        return truncatedBaseName(sanitized, maxUTF8Bytes: maxBaseNameUTF8Bytes)
    }
}

// MARK: - Import placement result

/// placement(.applyImport)의 모든 항목이 종료된 뒤 reducer가 emit하는 종합 완료 결과.
/// 성공 목적지 경로/실패와 종단 상태를 함께 전달한다. 항목별로 여러 번이 아니라 정확히 한 번 emit된다.
public struct ExternalDropImportResult: Equatable, Sendable {
    /// 소속 세션.
    public let sessionID: ExternalDropSessionID
    /// placement에 성공해 destination에 남은 파일 경로 목록.
    public let succeededPaths: [String]
    /// placement에 실패해 source/staged 입력을 보존한 파일 경로 목록.
    public let failedPaths: [String]
    /// 모든 항목 종료 후 결정된 종단 상태.
    public let status: ExternalObjectImportStatus

    public init(
        sessionID: ExternalDropSessionID,
        succeededPaths: [String],
        failedPaths: [String],
        status: ExternalObjectImportStatus,
    ) {
        self.sessionID = sessionID
        self.succeededPaths = succeededPaths
        self.failedPaths = failedPaths
        self.status = status
    }
}

// MARK: - Typed reject / failure reason

// 획득 실패/거절의 타입화된 사유. 빈/불확정 cardinality나 잘못된 콜백 출력을
// 추측된 성공으로 승격하지 않기 위해 실패를 명시적으로 모델링한다.

public enum ExternalDropRejectReason: Equatable, Sendable {
    /// receiver.fileNames가 비어 있어 예상 cardinality를 알 수 없음.
    case emptyCardinality
    /// receiver.fileNames가 불확정(indeterminate) 상태여서 수신 완료를 판정할 수 없음.
    case indeterminateCardinality
    /// 콜백이 non-nil error를 전달함.
    case callbackError
    /// 콜백이 URL을 전달하지 않음.
    case missingURL
    /// 콜백이 보고한 파일이 실제로 존재하지 않음.
    case fileAbsent
    /// 콜백이 보고한 경로가 세션 staging 디렉터리 밖에 있음.
    case outsideStaging
    /// data-flavor 바이트를 staging에 쓰는 데 실패함.
    case dataMaterializationFailed
    /// cancel/finish로 인해 세션이 무효화됨.
    case cancelled
}

// MARK: - Terminal acquisition event

/// reducer가 소비하는 획득 종단 이벤트. 성공/실패/취소의 3가지 종단 상태만 존재한다.
/// 수신 파일 각 건은 `.received`로, 그리고 마지막에 정확히 한 번 종단 이벤트가 온다.
public enum ExternalDropAcquisitionEvent: Equatable, Sendable {
    /// staging으로 실제 파일 한 건이 수신됨.
    case received(ExternalDropReceivedFile)
    /// 전체 획득이 성공적으로 종료됨.
    case succeeded(ExternalDropSessionID)
    /// 타입화된 사유로 획득이 실패함.
    case failed(ExternalDropSessionID, ExternalDropRejectReason)
    /// 세션이 취소됨.
    case cancelled(ExternalDropSessionID)
}
