public struct CollectionBaseline: Equatable, Sendable {
    public var context: CollectionContext

    public init(context: CollectionContext) {
        self.context = context
    }
}
