"""LangChain 기반 LLM Provider

LangChain을 사용하여 다양한 LLM을 통일된 인터페이스로 제공합니다.
"""

from typing import Any

from langchain_anthropic import ChatAnthropic
from langchain_community.llms import Ollama
from langchain_core.language_models import BaseLLM
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_core.prompts import ChatPromptTemplate
from langchain_openai import ChatOpenAI

from core.llm.llm_provider import LLMProvider


class LangChainProvider(LLMProvider):
    """LangChain 기반 LLM 제공자

    다양한 LLM을 쉽게 교체하여 사용할 수 있습니다:
    - ollama: 로컬 Ollama (qwen2.5:7b, llama3.2 등)
    - openai: OpenAI (gpt-4, gpt-3.5-turbo 등)
    - anthropic: Anthropic Claude (claude-3-opus, claude-3-sonnet 등)
    """

    def __init__(
        self,
        provider: str = "ollama",
        model: str = "qwen2.5:7b",
        **kwargs: Any,
    ):
        """LangChain Provider 초기화

        Args:
            provider: LLM 제공자 (ollama, openai, anthropic)
            model: 모델 이름
            **kwargs: 제공자별 추가 설정
                - base_url: Ollama URL (기본: http://localhost:11434)
                - api_key: OpenAI/Anthropic API 키
                - temperature: 온도 (기본: 0.7)
        """
        self.provider = provider
        self.model = model
        self.kwargs = kwargs
        self.llm = self._create_llm()

    def _create_llm(self) -> BaseLLM:
        """LLM 인스턴스 생성"""
        if self.provider == "ollama":
            base_url = self.kwargs.get("base_url", "http://localhost:11434")
            return Ollama(
                model=self.model,
                base_url=base_url,
                temperature=self.kwargs.get("temperature", 0.7),
            )

        elif self.provider == "openai":
            api_key = self.kwargs.get("api_key")
            return ChatOpenAI(
                model=self.model,
                api_key=api_key,
                temperature=self.kwargs.get("temperature", 0.7),
            )

        elif self.provider == "anthropic":
            api_key = self.kwargs.get("api_key")
            return ChatAnthropic(
                model=self.model,
                anthropic_api_key=api_key,
                temperature=self.kwargs.get("temperature", 0.7),
            )

        else:
            raise ValueError(f"지원하지 않는 provider: {self.provider}")

    def _escape_prompt_template(self, text: str) -> str:
        """프롬프트 템플릿 내 중괄호를 이스케이프

        ChatPromptTemplate은 모든 중괄호 {}를 변수로 인식하므로
        이중 중괄호 {{}}로 이스케이프해야 합니다.
        """
        return text.replace("{", "{{").replace("}", "}}")

    async def generate(self, prompt: str, system: str | None = None) -> str:
        """텍스트 생성

        Args:
            prompt: 사용자 프롬프트
            system: 시스템 프롬프트 (선택)

        Returns:
            생성된 텍스트
        """
        try:
            # 시스템 프롬프트가 있으면 템플릿 사용
            if system:
                # system 프롬프트의 중괄호를 이스케이프
                escaped_system = self._escape_prompt_template(system)

                # ChatPromptTemplate 사용
                template = ChatPromptTemplate.from_messages(
                    [
                        ("system", escaped_system),
                        ("human", "{input}"),
                    ]
                )

                # Chain 생성 및 실행
                chain = template | self.llm

                # Ollama는 invoke, Chat 모델은 ainvoke 사용
                if self.provider == "ollama":
                    response = chain.invoke({"input": prompt})
                else:
                    response = await chain.ainvoke({"input": prompt})

                # 응답 추출
                if hasattr(response, "content"):
                    return response.content
                else:
                    return str(response)

            else:
                # 시스템 프롬프트 없으면 직접 호출
                if self.provider == "ollama":
                    response = self.llm.invoke(prompt)
                else:
                    response = await self.llm.ainvoke(prompt)

                # 응답 추출
                if hasattr(response, "content"):
                    return response.content
                else:
                    return str(response)

        except Exception as e:
            raise RuntimeError(f"LLM API 오류: {e}")

    async def health_check(self) -> bool:
        """LLM 서비스 상태 확인

        Returns:
            정상이면 True, 아니면 False
        """
        try:
            # 간단한 테스트 프롬프트
            if self.provider == "ollama":
                self.llm.invoke("test")
            else:
                await self.llm.ainvoke("test")
            return True
        except Exception:
            return False

    async def close(self) -> None:
        """리소스 정리

        현재 LangChain은 자동으로 리소스를 관리하므로 별도 작업 없음
        """
        pass
