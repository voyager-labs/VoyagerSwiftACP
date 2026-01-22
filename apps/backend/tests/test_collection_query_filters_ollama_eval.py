from __future__ import annotations

import asyncio
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import pytest


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _ollama_base_url() -> str:
    return os.getenv("OLLAMA_BASE_URL", "http://localhost:11434").rstrip("/")


def _ollama_model() -> str:
    return os.getenv("OLLAMA_MODEL", "qwen2.5:7b")


def _should_run_ollama_eval() -> bool:
    return os.getenv("VOYAGER_OLLAMA_EVAL", "").lower() in {"1", "true", "yes", "y", "on"}


def _ollama_is_reachable(timeout_sec: float = 0.3) -> bool:
    base_url = _ollama_base_url()
    url = f"{base_url}/api/tags"
    request = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=timeout_sec) as response:
            if response.status != 200:
                return False
            payload = json.loads(response.read().decode("utf-8"))
            return isinstance(payload, dict) and "models" in payload
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return False


def _run(coro: Any) -> Any:
    return asyncio.run(coro)


def _normalize_condition(condition: dict[str, Any]) -> dict[str, Any]:
    normalized = dict(condition)
    value = normalized.get("value")
    if isinstance(value, list):
        normalized["value"] = sorted(value)
    return normalized


def _has_condition(
    conditions: list[dict[str, Any]],
    *,
    property_key: str,
    operator: str | None = None,
) -> bool:
    for raw in conditions:
        condition = _normalize_condition(raw)
        if condition.get("propertyKey") != property_key:
            continue
        if operator is not None and condition.get("operator") != operator:
            continue
        return True
    return False


def _skip_unless_ollama_ready() -> None:
    if not _should_run_ollama_eval():
        pytest.skip("Set VOYAGER_OLLAMA_EVAL=1 to enable Ollama eval tests.")
    if not _ollama_is_reachable():
        pytest.skip(f"Ollama is not reachable at {_ollama_base_url()}.")


def _build_converter():
    repo_root = _repo_root()
    import sys

    sys.path.insert(0, str(repo_root / "apps" / "backend" / "src"))

    from core.llm.langchain_provider import LangChainProvider
    from core.llm.search_condition_converter import CachedSearchConditionConverter

    provider = LangChainProvider(
        provider="ollama",
        base_url=_ollama_base_url(),
        model=_ollama_model(),
        temperature=0,
    )
    return CachedSearchConditionConverter(provider)


def test_collection_query_to_filters_pdf_scope_and_type() -> None:
    _skip_unless_ollama_ready()
    converter = _build_converter()

    query = "다운로드 폴더에서 PDF 파일 찾아줘"

    started_at = time.perf_counter()
    result = _run(converter.convert(query))
    elapsed_ms = int((time.perf_counter() - started_at) * 1000)

    assert isinstance(result, dict)
    assert "conditions" in result
    assert "scopes" in result
    assert isinstance(result["conditions"], list)

    # 최소한 PDF 의도는 조건에 반영되어야 함.
    # 구현상 파일 타입 룰이 content_type_tree 또는 extension으로 들어갈 가능성이 높음.
    assert _has_condition(result["conditions"], property_key="content_type_tree") or _has_condition(
        result["conditions"], property_key="extension"
    )

    # 다운로드 폴더 언급 시 scopes가 지정되거나(쿼리 우선) 혹은 시스템 정책상 스코프를 반환할 수 있어야 함.
    # (스코프는 구현에서 "언급된 경우만" 반환하므로 None도 가능)
    assert result["scopes"] is None or isinstance(result["scopes"], list)

    # 로컬 성능 회귀를 잡기 위한 매우 느슨한 상한(필요 시 조정).
    assert elapsed_ms < 30_000


def test_collection_query_to_filters_size_condition() -> None:
    _skip_unless_ollama_ready()
    converter = _build_converter()

    query = "10MB 이상의 파일"
    result = _run(converter.convert(query))

    assert isinstance(result, dict)
    assert isinstance(result.get("conditions"), list)

    # 크기 조건은 file_allocated_size 또는 size 등으로 표현될 수 있음.
    assert _has_condition(
        result["conditions"], property_key="file_allocated_size"
    ) or _has_condition(result["conditions"], property_key="size")
