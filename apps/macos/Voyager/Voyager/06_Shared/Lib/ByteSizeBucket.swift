import Foundation

enum ByteSizeBucket: CaseIterable, Hashable, Sendable {
    case zeroBytes
    case lessThanHundredKB
    case hundredKBToOneMB
    case oneMBToHundredMB
    case hundredMBToOneGB
    case moreThanOneGB

    static let hundredKB: Int64 = 100 * 1024
    static let oneMB: Int64 = 1024 * 1024
    static let hundredMB: Int64 = 100 * oneMB
    static let oneGB: Int64 = 1024 * oneMB

    static func bucket(for size: Int64) -> ByteSizeBucket {
        switch size {
        case 0:
            .zeroBytes
        case ..<hundredKB:
            .lessThanHundredKB
        case ..<oneMB:
            .hundredKBToOneMB
        case ..<hundredMB:
            .oneMBToHundredMB
        case ..<oneGB:
            .hundredMBToOneGB
        default:
            .moreThanOneGB
        }
    }
}
