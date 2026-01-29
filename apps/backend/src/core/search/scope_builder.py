"""Scope 빌더

Search API의 scopes(경로 범위)를 SQL WHERE절로 변환합니다.
- TODO: Swift Voyager Helper로 이관 [VOY-152]
- TODO: Swift Voyager Helper 이관 시 SQL 구문을 문자열로 반환하는 대신, Swift의 ORM 쿼리 객체를 반환하도록 변경
"""

import os
from pathlib import Path
from typing import Sequence


class ScopeBuilder:
    """Scopes를 SQL 경로 필터로 변환하는 빌더"""

    def build_scope_clause(self, scopes: Sequence[str]) -> tuple[str, dict[str, str]]:
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
        scopes_n = self._normalize_scopes(scopes)
        if not scopes_n:
            return "1=1", {}

        clauses: list[str] = []
        params: dict[str, str] = {}

        for i, base in enumerate(scopes_n):
            s_key = f"s{i}"
            child_key = f"s{i}_child"

            child_pattern = "/%" if base == "/" else f"{base}/%"

            clauses.append(f"(dir_path = :{s_key} OR dir_path LIKE :{child_key})")
            params[s_key] = base
            params[child_key] = child_pattern

        if len(clauses) == 1:
            return clauses[0], params

        return f"({' OR '.join(clauses)})", params

    def _normalize_scopes(self, scopes: Sequence[str]) -> list[str]:
        out: list[str] = []
        seen: set[str] = set()

        for raw in scopes or []:
            s = (raw or "").strip()
            if not s:
                continue

            n = self._normalize_one(s)
            if n not in seen:
                seen.add(n)
                out.append(n)

        if not out:
            return []

        # 상위 스코프가 있으면 하위 스코프 제거 (쿼리 가벼워짐)
        out.sort(key=lambda x: (len(x), x))  # 상위 먼저 오게
        reduced: list[str] = []
        for p in out:
            if any(
                parent == "/" or p == parent or p.startswith(parent + "/") for parent in reduced
            ):
                continue
            reduced.append(p)

        return reduced

    def _normalize_one(self, raw: str) -> str:
        s = os.path.expandvars(raw.strip())
        p = Path(s).expanduser()

        # symlink는 풀지 않고, 문자열 기준으로 절대경로화
        p = Path(os.path.abspath(str(p)))

        norm = p.as_posix()
        return norm if norm == "/" else norm.rstrip("/")
