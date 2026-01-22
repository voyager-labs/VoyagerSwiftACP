from __future__ import annotations

import asyncio
import json
import os
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

import pytest


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _runs_path() -> Path:
    raw = os.getenv("VOYAGER_OLLAMA_EVAL_RUNS_PATH", "").strip()
    if raw:
        return Path(raw)
    return (
        _repo_root()
        / "apps"
        / "backend"
        / "tests"
        / "evals"
        / "runs"
        / "collection_query_expected_dsl_runs.jsonl"
    )


def _ollama_base_url() -> str:
    return os.getenv("OLLAMA_BASE_URL", "http://localhost:11434").rstrip("/")


def _ollama_model() -> str:
    return os.getenv("OLLAMA_MODEL", "qwen2.5:7b")


def _should_run_ollama_eval() -> bool:
    return os.getenv("VOYAGER_OLLAMA_EVAL", "").lower() in {"1", "true", "yes", "y", "on"}


def _eval_case_id() -> str:
    raw = os.getenv("VOYAGER_OLLAMA_EVAL_CASE", "").strip()
    if not raw:
        raise RuntimeError(
            "VOYAGER_OLLAMA_EVAL_CASE is required (single-case eval only). "
            "Example: VOYAGER_OLLAMA_EVAL_CASE=type_pdf"
        )
    return raw


def _eval_per_case_timeout_ms() -> int:
    raw = os.getenv("VOYAGER_OLLAMA_EVAL_TIMEOUT_MS", "").strip()
    if not raw:
        return 60_000
    try:
        return int(raw)
    except ValueError:
        return 60_000


def _ollama_is_reachable(timeout_sec: float = 0.3) -> bool:
    url = f"{_ollama_base_url()}/api/tags"
    request = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=timeout_sec) as response:
            if response.status != 200:
                return False
            payload = json.loads(response.read().decode("utf-8"))
            return isinstance(payload, dict) and "models" in payload
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return False


def _skip_unless_ollama_ready() -> None:
    if not _should_run_ollama_eval():
        pytest.skip("Set VOYAGER_OLLAMA_EVAL=1 to enable Ollama eval tests.")
    if not _ollama_is_reachable():
        pytest.skip(f"Ollama is not reachable at {_ollama_base_url()}.")


def _run(coro: Any) -> Any:
    return asyncio.run(coro)


@dataclass(frozen=True)
class EvalCase:
    case_id: str
    query: str
    expected: dict[str, Any]
    notes: str | None = None


def _cases_path() -> Path:
    return (
        _repo_root()
        / "apps"
        / "backend"
        / "tests"
        / "evals"
        / "collection_query_expected_dsl_cases.jsonl"
    )


def _load_cases() -> list[EvalCase]:
    cases: list[EvalCase] = []
    for line in _cases_path().read_text(encoding="utf-8").splitlines():
        raw = json.loads(line)
        cases.append(
            EvalCase(
                case_id=str(raw["id"]),
                query=str(raw["query"]),
                expected=dict(raw["expected"]),
                notes=raw.get("notes"),
            )
        )
    return cases


def _load_case(case_id: str) -> EvalCase:
    for case in _load_cases():
        if case.case_id == case_id:
            return case
    raise KeyError(f"Unknown eval case id: {case_id}")


def _iso(dt: datetime) -> str:
    return dt.replace(microsecond=0).isoformat()


def _date(dt: datetime) -> str:
    return dt.date().isoformat()


def _append_run_record(record: dict[str, Any]) -> None:
    runs_path = _runs_path()
    runs_path.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps(record, ensure_ascii=False)
    runs_path.write_text("", encoding="utf-8") if not runs_path.exists() else None
    with runs_path.open("a", encoding="utf-8") as fp:
        fp.write(line + "\n")


def _resolve_placeholders(expected: dict[str, Any], *, now: datetime) -> dict[str, Any]:
    today_start = datetime(year=now.year, month=now.month, day=now.day)
    yesterday_start = today_start - timedelta(days=1)

    mapping = {
        "{NOW_ISO}": _iso(now),
        "{TODAY_START_ISO}": _iso(today_start),
        "{YESTERDAY_START_ISO}": _iso(yesterday_start),
        "{TODAY_DATE}": _date(now),
        "{YESTERDAY_DATE}": _date(now - timedelta(days=1)),
        "{DATE_MINUS_7D}": _date(now - timedelta(days=7)),
        "{DATE_MINUS_30D}": _date(now - timedelta(days=30)),
        "{DATE_MINUS_365D}": _date(now - timedelta(days=365)),
    }

    def replace(value: Any) -> Any:
        if isinstance(value, str):
            for token, replacement in mapping.items():
                value = value.replace(token, replacement)
            return value
        if isinstance(value, list):
            return [replace(item) for item in value]
        if isinstance(value, dict):
            return {key: replace(item) for key, item in value.items()}
        return value

    return replace(expected)


def _normalize_conditions(conditions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    for condition in conditions:
        c = dict(condition)
        value = c.get("value")
        if isinstance(value, list):
            c["value"] = sorted(value)
        normalized.append(c)
    normalized.sort(
        key=lambda c: (str(c.get("propertyKey")), str(c.get("operator")), str(c.get("value")))
    )
    return normalized


def _normalize_filters(filters: dict[str, Any], *, now: datetime) -> dict[str, Any]:
    resolved = _resolve_placeholders(filters, now=now)
    scopes = resolved.get("scopes", [])
    conditions = resolved.get("conditions", [])
    if not isinstance(scopes, list):
        scopes = []
    if not isinstance(conditions, list):
        conditions = []
    return {
        "scopes": scopes,
        "conditions": _normalize_conditions([dict(c) for c in conditions]),
    }


def _values_to_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def _normalize_uti_pattern(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    return value.strip().strip("%").lower()


def _condition_matches(expected: dict[str, Any], actual: dict[str, Any]) -> bool:
    if expected.get("propertyKey") != actual.get("propertyKey"):
        return False

    expected_op = expected.get("operator")
    actual_op = actual.get("operator")
    expected_value = expected.get("value")
    actual_value = actual.get("value")

    # Exact match first
    if expected_op == actual_op and expected_value == actual_value:
        return True

    # Equivalence rules (looser semantics)
    # 1) content_type_tree matches "%public.pdf%" ≈ extension eq "pdf"
    if (
        expected.get("propertyKey") == "content_type_tree"
        and expected_op == "matches"
        and isinstance(expected_value, str)
    ):
        pattern = _normalize_uti_pattern(expected_value)
        if (
            actual.get("propertyKey") == "extension"
            and actual_op == "eq"
            and isinstance(actual_value, str)
        ):
            ext = actual_value.lower().lstrip(".")
            ext_to_uti = {
                "mp4": "public.mpeg-4",
                "mov": "com.apple.quicktime-movie",
                "pdf": "public.pdf",
                "png": "public.png",
                "jpg": "public.jpeg",
                "jpeg": "public.jpeg",
                "gif": "public.gif",
                "heic": "public.heic",
            }
            expected_uti = ext_to_uti.get(ext)
            if expected_uti and pattern and expected_uti in pattern:
                return True

    # 2) extension eq "mp4" ≈ content_type_tree matches "%public.mpeg-4%" (and similar UTIs)
    if (
        expected.get("propertyKey") == "extension"
        and expected_op == "eq"
        and isinstance(expected_value, str)
    ):
        ext = expected_value.lower().lstrip(".")
        if (
            actual.get("propertyKey") == "content_type_tree"
            and actual_op in {"eq", "matches"}
            and isinstance(actual_value, str)
        ):
            content_type = actual_value.lower()
            ext_to_uti = {
                "mp4": "public.mpeg-4",
                "mov": "com.apple.quicktime-movie",
                "pdf": "public.pdf",
                "png": "public.png",
                "jpg": "public.jpeg",
                "jpeg": "public.jpeg",
                "gif": "public.gif",
                "heic": "public.heic",
            }
            expected_uti = ext_to_uti.get(ext)
            if expected_uti and expected_uti in content_type:
                return True

    # 3) extension in ["md","markdown"] ≈ extension eq "md"
    if expected.get("propertyKey") == "extension" and expected_op == "in":
        expected_set = {str(v).lower().lstrip(".") for v in _values_to_list(expected_value)}
        if (
            actual.get("propertyKey") == "extension"
            and actual_op == "eq"
            and isinstance(actual_value, str)
        ):
            return actual_value.lower().lstrip(".") in expected_set

    return False


def _filters_match(expected: dict[str, Any], actual: dict[str, Any]) -> bool:
    expected_conditions = [dict(c) for c in expected.get("conditions", [])]
    actual_conditions = [dict(c) for c in actual.get("conditions", [])]

    # Scopes are already handled in the test; this function compares conditions only.
    unmatched_actual = actual_conditions[:]
    for expected_condition in expected_conditions:
        matched_index: int | None = None
        for i, actual_condition in enumerate(unmatched_actual):
            if _condition_matches(expected_condition, actual_condition):
                matched_index = i
                break
        if matched_index is None:
            return False
        unmatched_actual.pop(matched_index)
    return True


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


@pytest.fixture(scope="session")
def converter() -> Any:
    _skip_unless_ollama_ready()
    return _build_converter()


def test_collection_query_expected_dsl_matches(converter: Any) -> None:
    case = _load_case(_eval_case_id())
    started_at = time.perf_counter()
    result = _run(converter.convert(case.query))
    elapsed_ms = int((time.perf_counter() - started_at) * 1000)

    assert isinstance(result, dict)
    assert isinstance(result.get("conditions"), list)

    now = datetime.now()
    expected_filters = _normalize_filters(case.expected, now=now)

    actual_scopes = result.get("scopes")
    actual_filters = _normalize_filters(
        {
            "scopes": [] if actual_scopes is None else actual_scopes,
            "conditions": result.get("conditions", []),
        },
        now=now,
    )

    # scopes: 구현에서 "쿼리 언급된 경우만 반환"이라 None이 정상일 수 있음.
    if expected_filters["scopes"] == []:
        assert actual_scopes in (None, [])
    else:
        assert actual_filters["scopes"] == expected_filters["scopes"]

    passed = False
    error: str | None = None
    try:
        assert _filters_match(expected_filters, actual_filters), case.notes or case.case_id
        assert elapsed_ms < _eval_per_case_timeout_ms()
        passed = True
    except AssertionError as e:
        error = str(e)
        raise
    finally:
        _append_run_record(
            {
                "ts": _iso(now),
                "case_id": case.case_id,
                "query": case.query,
                "model": _ollama_model(),
                "base_url": _ollama_base_url(),
                "elapsed_ms": elapsed_ms,
                "passed": passed,
                "error": error,
                "expected": expected_filters,
                "actual": actual_filters,
                "scopes_raw": actual_scopes,
            }
        )
