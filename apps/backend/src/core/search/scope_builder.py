"""Scope 빌더

Search API의 scopes(경로 범위)를 SQL WHERE절로 변환합니다.
"""


class ScopeBuilder:
    """Scopes를 SQL 경로 필터로 변환하는 빌더"""

    def build_scope_clause(self, scopes: list[str]) -> tuple[str, dict[str, str]]:
        """경로 스코프를 SQL 조건으로 변환

        Args:
            scopes: 절대 경로 목록 (예: ["/Users/foo/Downloads"])

        Returns:
            (sql_fragment, parameters) 튜플

        Example:
            Input: ["/Users/foo/Downloads", "/Users/foo/Documents"]
            Output: (
                "(path LIKE :s0 OR path LIKE :s1)",
                {"s0": "/Users/foo/Downloads/%", "s1": "/Users/foo/Documents/%"}
            )
        """
        if not scopes:
            return "1=1", {}

        clauses: list[str] = []
        params: dict[str, str] = {}

        for index, scope in enumerate(scopes):
            # 경로 정규화: 후행 슬래시 제거 후 /%로 패턴 생성
            normalized = scope.rstrip("/")
            placeholder = f"s{index}"
            clauses.append(f"path LIKE :{placeholder}")
            params[placeholder] = f"{normalized}/%"

        if len(clauses) == 1:
            return clauses[0], params

        return f"({' OR '.join(clauses)})", params
