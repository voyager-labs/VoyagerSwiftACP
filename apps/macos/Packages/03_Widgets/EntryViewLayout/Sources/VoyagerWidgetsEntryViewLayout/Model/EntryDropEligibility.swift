import VoyagerEntitiesEntry

public extension EntryModel {
    /// 드롭 interior(안에 넣기) 대상 여부. filesystem directory이면서 package가 아닌 경우만 허용한다(기존 인라인 판정과 동치).
    /// live 변환은 `.voycoll` 디렉터리를 package로 분류하므로 여기서 제외되며, hierarchy 자격(`supportsListHierarchyExpansion`)의
    /// voycoll 확장자 방어 조건과는 별개다.
    var acceptsDropInto: Bool {
        isFolder && !isPackage
    }
}
