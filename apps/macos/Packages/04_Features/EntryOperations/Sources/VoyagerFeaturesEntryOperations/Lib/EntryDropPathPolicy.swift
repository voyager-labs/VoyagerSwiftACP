import Foundation

public enum EntryDropPathPolicy {
    public static func areEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs
    }

    public static func isSameOrDescendant(_ candidatePath: String, of parentPath: String) -> Bool {
        areEquivalent(candidatePath, parentPath) || isDescendant(candidatePath, of: parentPath)
    }

    public static func isDescendant(_ candidatePath: String, of parentPath: String) -> Bool {
        let candidateComponents = URL(fileURLWithPath: candidatePath)
            .standardizedFileURL.pathComponents
        let parentComponents = URL(fileURLWithPath: parentPath)
            .standardizedFileURL.pathComponents

        guard candidateComponents.count > parentComponents.count else {
            return false
        }

        return Array(candidateComponents.prefix(parentComponents.count)) == parentComponents
    }
}
