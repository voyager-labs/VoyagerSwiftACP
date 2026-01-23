from __future__ import annotations

from typing import Any

from langchain_openai import ChatOpenAI
from pydantic import SecretStr


class LangChainProvider:
    """LangChain 기반 LLM 제공자 (OpenAI 전용).

    - TODO: 추후 OpenAI 외의 provider 지원 및 메소드 확장
    """

    def __init__(self, provider: str, base_url: str, **kwargs: Any) -> None:
        if provider != "openai":
            raise ValueError(f"지원하지 않는 provider: {provider}")
        self.base_url = base_url
        self.kwargs = kwargs
        self.llm = ChatOpenAI(
            api_key=SecretStr("gateway"),
            model=self.kwargs.get("model", "gpt-5-mini-2025-08-07"),
            base_url=f"{self.base_url.rstrip('/')}/gateway/openai/v1",
        )
