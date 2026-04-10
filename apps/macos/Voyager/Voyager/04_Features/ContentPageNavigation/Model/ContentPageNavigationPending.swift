enum ContentPageNavigationPending: Equatable, Sendable {
    case back
    case forward
    case history(index: Int, isBackHistory: Bool)
    case enclosingDirectory
}
