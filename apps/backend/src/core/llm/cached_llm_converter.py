"""캐싱 기능이 추가된 LLM 컨버터"""

from core.llm.llm_provider import LLMProvider
from core.llm.llm_converter import LLMConverter


class CachedLLMConverter(LLMConverter):
    """캐싱 기능이 추가된 LLM 컨버터"""

    def __init__(self, llm_provider: LLMProvider, cache_size: int = 100):
        super().__init__(llm_provider)
        self._cache: dict[str, str | None] = {}
        self._cache_size = cache_size

    async def convert(self, query: str) -> str | None:
        # 캐시 확인
        if query in self._cache:
            return self._cache[query]

        # 부모 클래스의 convert 호출
        sql = await super().convert(query)

        # 캐시 저장 (FIFO)
        if len(self._cache) >= self._cache_size:
            self._cache.pop(next(iter(self._cache)))
        self._cache[query] = sql

        return sql

    def clear_cache(self) -> None:
        """캐시 초기화"""
        self._cache.clear()
