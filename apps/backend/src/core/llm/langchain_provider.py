"""LangChain 기반 LLM Provider

LangChain을 사용하여 다양한 LLM을 통일된 인터페이스로 제공합니다.
"""

import json
import os
import re
from typing import Any

from langchain_community.llms import Ollama
from langchain_core.language_models import BaseLLM
from langchain_core.prompts import ChatPromptTemplate
from langchain_openai import ChatOpenAI
from pydantic import BaseModel

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
        provider: str,
        base_url: str | None = None,
        **kwargs: Any,
    ):
        """LangChain Provider 초기화

        Args:
            provider: LLM 제공자 (ollama, openai)
            **kwargs: 제공자별 추가 설정
                - base_url: Ollama URL (기본: http://localhost:11434)
                - api_key: OpenAI/Anthropic API 키
                - temperature: 온도 (기본: 0.7)
        """
        self.provider = provider
        self.base_url = base_url
        self.kwargs = kwargs
        self.llm = self._create_llm()

    def _create_llm(self) -> BaseLLM | None:
        """LLM 인스턴스 생성"""
        if self.provider == "ollama":
            return Ollama(
                model=self.kwargs.get("model", "qwen2.5:7b"),
                base_url=self.base_url or "http://localhost:11434",
                temperature=self.kwargs.get("temperature", 0),
            )

        elif self.provider == "openai":
            return ChatOpenAI(
                api_key="gateway",
                model=self.kwargs.get("model", "gpt-5-mini-2025-08-07"),
                base_url=f"{self.base_url.rstrip('/')}/gateway/openai/v1",
                temperature=self.kwargs.get("temperature", 0),
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

    async def generate_structured(
        self,
        prompt: str,
        schema: type[BaseModel],
        system: str | None = None,
    ) -> BaseModel:
        """구조화된 출력 생성

        Args:
            prompt: 사용자 프롬프트
            schema: Pydantic 스키마 클래스
            system: 시스템 프롬프트 (선택)

        Returns:
            스키마에 맞는 구조화된 응답
        """
        try:
            structured_llm = self.llm.with_structured_output(schema)

            if system:
                escaped_system = self._escape_prompt_template(system)
                template = ChatPromptTemplate.from_messages(
                    [
                        ("system", escaped_system),
                        ("human", "{input}"),
                    ]
                )
                chain = template | structured_llm
                return await chain.ainvoke({"input": prompt})
            else:
                return await structured_llm.ainvoke(prompt)

        except Exception as e:
            if self.provider != "ollama":
                raise RuntimeError(f"Structured output 생성 오류: {e}")

            # Ollama 모델들(특히 일부 gpt-oss 계열)은 LangChain structured output 경로가
            # 실패할 수 있어, JSON-only 응답 + 파싱 + Pydantic 검증으로 폴백합니다.
            try:
                json_only_prompt = self._build_json_only_prompt(prompt=prompt, schema=schema)

                # 반복 실행을 피하기 위해 기본은 1회만 호출합니다.
                # 필요 시 환경변수로 폴백 재시도 횟수를 늘릴 수 있습니다.
                retries = _env_int("OLLAMA_STRUCTURED_FALLBACK_RETRIES", default=0)
                last_error: Exception | None = None
                for attempt in range(retries + 1):
                    try:
                        raw = await self.generate(prompt=json_only_prompt, system=system)
                        payload = self._extract_json_object(raw)
                        return schema.model_validate(payload)
                    except Exception as attempt_error:
                        last_error = attempt_error

                raise last_error or RuntimeError("Unknown ollama structured fallback failure.")
            except Exception as fallback_error:
                raise RuntimeError(
                    "Structured output 생성 오류(ollama fallback 포함): "
                    f"{e} / fallback: {fallback_error}"
                )

    def _build_json_only_prompt(self, *, prompt: str, schema: type[BaseModel]) -> str:
        schema_json = schema.model_json_schema()
        schema_text = json.dumps(schema_json, ensure_ascii=False)

        return "\n".join(
            [
                prompt,
                "",
                "IMPORTANT: Output a single JSON object ONLY. No prose, no Markdown, no code fences.",
                "중요: 반드시 JSON 객체만 출력하세요. 설명/문장/코드블록/마크다운 금지.",
                "",
                "If unsure, output empty-but-valid JSON like:",
                '{"conditions":[],"scopes":null,"error":null}',
                "",
                "아래 JSON Schema를 만족해야 합니다(키 이름/타입 엄수):",
                schema_text,
            ]
        )

    def _extract_json_object(self, text: str) -> dict[str, Any]:
        """LLM 출력에서 첫 JSON 객체를 추출합니다.

        Ollama 텍스트 출력이 코드블록/설명 등을 섞는 경우가 있어 방어적으로 파싱합니다.
        """
        stripped = text.strip()

        # ```json ... ``` 형태 우선 처리
        fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", stripped, flags=re.DOTALL)
        if fenced:
            candidate = fenced.group(1).strip()
            return json.loads(candidate)

        # 전체가 JSON 객체면 그대로
        if stripped.startswith("{") and stripped.endswith("}"):
            return json.loads(stripped)

        # 텍스트 내 첫 번째 JSON 객체를 브레이스 매칭으로 추출
        start = stripped.find("{")
        if start == -1:
            raise ValueError("JSON object not found in response.")

        depth = 0
        for i in range(start, len(stripped)):
            char = stripped[i]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    candidate = stripped[start : i + 1]
                    return json.loads(candidate)

        raise ValueError("Unterminated JSON object in response.")


def _env_int(name: str, *, default: int) -> int:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default
