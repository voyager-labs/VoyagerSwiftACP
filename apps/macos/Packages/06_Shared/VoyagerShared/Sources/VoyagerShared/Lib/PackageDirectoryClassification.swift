import Foundation
import UniformTypeIdentifiers

/// 패키지 디렉터리 판별 — 확장자 목록 하드코딩 없이 시스템 SSOT에 위임한다.
/// 1) 파일시스템 package bit(`.isPackageKey`) — 생성 도구(Xcode 등)가 설정
/// 2) Launch Services가 실제 아이템에 대해 resolve한 UTI(`.typeIdentifierKey`)가
///    package 또는 bundle에 준수 — Finder와 동일 근거, framework류 포획 포함
/// 3) 도메인 fallback — `voycoll`(Voyager collection)만 자체 판정.
///    UTI 등록은 Voyager 설치 머신에서만 유효하므로 미등록 환경/테스트 픽스처의 결정성을 위해 확장자로 판정한다.
public enum PackageDirectoryClassification {
    public static func isPackageDirectory(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isPackageKey, .typeIdentifierKey]) {
            if values.isPackage == true { return true }
            if let identifier = values.typeIdentifier,
               let type = UTType(identifier),
               type.conforms(to: .package) || type.conforms(to: .bundle)
            { return true }
        }
        return url.pathExtension.lowercased() == CollectionConstants.fileExtension
    }
}
