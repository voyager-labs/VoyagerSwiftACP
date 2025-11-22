"""LLM Provider 추상 인터페이스

다양한 LLM 제공자를 통일된 인터페이스로 사용할 수 있도록 추상화합니다.
"""

from abc import ABC, abstractmethod


class LLMProvider(ABC):
    """LLM 제공자 추상 클래스"""

    @abstractmethod
    async def generate(self, prompt: str, system: str | None = None) -> str:
        """텍스트 생성

        Args:
            prompt: 사용자 프롬프트
            system: 시스템 프롬프트 (선택)

        Returns:
            생성된 텍스트
        """
        pass

    @abstractmethod
    async def health_check(self) -> bool:
        """LLM 서비스 상태 확인

        Returns:
            정상이면 True, 아니면 False
        """
        pass

    @abstractmethod
    async def close(self) -> None:
        """리소스 정리"""
        pass
