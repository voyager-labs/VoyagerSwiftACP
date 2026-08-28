import Foundation

public extension EntryModel {
    /// 열기/탐색 대상 디렉터리 여부. 판정은 filesystem directory truth(`isFolder`)에서
    /// package directory(`.app` 등)를 제외한 `isFolder && !isPackage`다.
    /// package directory(`.app` 등)는 탐색 대상이 아니며 `openFiles`(Launch Services)로 라우팅된다.
    /// `.voycoll`은 routing 단계에서 collection heuristic이 이 판정에 앞서 `openCollectionFile`로 연다.
    /// hierarchy 확장 자격(`supportsListHierarchyExpansion`)과는 별개다.
    var isDirectoryNavigationTarget: Bool {
        isFolder && !isPackage
    }
}
