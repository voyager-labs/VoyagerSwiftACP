public extension AiChatState {
    func isPassiveContentTabProjection(matching baseline: Self = .init()) -> Bool {
        var normalized = self
        normalized.cancellationOwnerID = baseline.cancellationOwnerID
        normalized.newChatPreparationMutationTracker = baseline.newChatPreparationMutationTracker
        normalized.inspectorReopenMutationBaseline = baseline.inspectorReopenMutationBaseline
        return normalized == baseline
    }
}
