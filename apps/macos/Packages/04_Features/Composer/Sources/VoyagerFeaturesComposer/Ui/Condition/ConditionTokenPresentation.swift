import VoyagerEntitiesCollection

enum ConditionTokenPresentation {
    static func buttonText(values: [String]) -> String {
        let committed = ConditionValueNormalizer.deduplicatedTokenValues(values)
        guard !committed.isEmpty else { return "Value" }
        if committed.count <= 2 { return committed.joined(separator: ", ") }
        return "\(committed[0]), \(committed[1]) +\(committed.count - 2)"
    }
}
