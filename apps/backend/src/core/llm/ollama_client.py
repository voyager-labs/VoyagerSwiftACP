"""Ollama LLM 클라이언트

레거시 지원을 위한 OllamaClient.
새 코드는 LangChainProvider 사용을 권장합니다.
"""

import json
from typing import Any

import httpx

from core.llm.llm_provider import LLMProvider


class OllamaClient(LLMProvider):
    """Ollama API 클라이언트"""

    def __init__(self, base_url: str = "http://localhost:11434", model: str = "llama3.2"):
        self.base_url = base_url
        self.model = model
        self.client = httpx.AsyncClient(timeout=60.0)

    async def generate(self, prompt: str, system: str | None = None) -> str:
        """텍스트 생성"""
        url = f"{self.base_url}/api/generate"

        payload: dict[str, Any] = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
        }

        if system:
            payload["system"] = system

        try:
            response = await self.client.post(url, json=payload)
            response.raise_for_status()
            data = response.json()
            return data.get("response", "")
        except httpx.HTTPError as e:
            raise RuntimeError(f"Ollama API 오류: {e}")

    async def chat(self, messages: list[dict[str, str]]) -> str:
        """채팅 API 사용"""
        url = f"{self.base_url}/api/chat"

        payload = {
            "model": self.model,
            "messages": messages,
            "stream": False,
        }

        try:
            response = await self.client.post(url, json=payload)
            response.raise_for_status()
            data = response.json()
            return data.get("message", {}).get("content", "")
        except httpx.HTTPError as e:
            raise RuntimeError(f"Ollama API 오류: {e}")

    async def health_check(self) -> bool:
        """Ollama 서버 상태 확인"""
        try:
            response = await self.client.get(f"{self.base_url}/api/tags")
            return response.status_code == 200
        except Exception:
            return False

    async def close(self) -> None:
        """클라이언트 종료"""
        await self.client.aclose()
