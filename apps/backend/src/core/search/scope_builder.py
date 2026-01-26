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
                "(dir_path = :s0 OR dir_path LIKE :s0_child OR dir_path = :s1 OR dir_path LIKE :s1_child)",
                {
                    "s0": "/Users/foo/Downloads",
                    "s0_child": "/Users/foo/Downloads/%",
                    "s1": "/Users/foo/Documents",
                    "s1_child": "/Users/foo/Documents/%",
                }
            )
        """
        if not scopes:
            return "1=1", {}

        clauses: list[str] = []
        params: dict[str, str] = {}

        for index, scope in enumerate(scopes):
            # 경로 정규화: 후행 슬래시 제거 후 /%로 패턴 생성
            normalized = scope.rstrip("/")
            base_placeholder = f"s{index}"
            child_placeholder = f"s{index}_child"
            clauses.append(f"dir_path = :{base_placeholder} OR dir_path LIKE :{child_placeholder}")
            params[base_placeholder] = normalized
            params[child_placeholder] = f"{normalized}/%"

        if len(clauses) == 1:
            return clauses[0], params

        return f"({' OR '.join(clauses)})", params
