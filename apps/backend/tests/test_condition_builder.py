from __future__ import annotations

import sys
from pathlib import Path

import pytest


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _builder():
    repo_root = _repo_root()
    sys.path.insert(0, str(repo_root / "apps" / "backend" / "src"))

    from core.search import ConditionBuilder

    return ConditionBuilder()


def _registry_mapping(key: str):
    repo_root = _repo_root()
    sys.path.insert(0, str(repo_root / "apps" / "backend" / "src"))

    from core.metadata import SYSTEM_PROPERTY_REGISTRY

    return SYSTEM_PROPERTY_REGISTRY[key]


def test_build_db_comparison_clause() -> None:
    builder = _builder()

    clause, params = builder.build_clause("uniform_type_identifier", "eq", "public.png")

    assert clause == "uniform_type_identifier = ?"
    assert params == ["public.png"]


def test_build_db_range_clause_for_date() -> None:
    builder = _builder()

    clause, params = builder.build_clause(
        "content_creation_date", "between", ["2024-01-01", "2024-12-31"]
    )

    assert clause == "DATE(content_creation_date) BETWEEN ? AND ?"
    assert params == ["2024-01-01", "2024-12-31"]


def test_build_json_string_list_contains_any() -> None:
    builder = _builder()
    mapping = _registry_mapping("contact_keywords")

    clause, params = builder.build_clause("contact_keywords", "contains_any", ["alpha", "beta"])

    assert clause == (
        "EXISTS (SELECT 1 FROM json_each(original_metadata, ?) WHERE value IN (?, ?))"
    )
    assert params == [mapping.json_path, "alpha", "beta"]


def test_build_json_string_list_empty() -> None:
    builder = _builder()
    mapping = _registry_mapping("contact_keywords")

    clause, params = builder.build_clause("contact_keywords", "empty", None)

    assert clause == (
        "(json_array_length(original_metadata, ?) IS NULL OR "
        "json_array_length(original_metadata, ?) = 0)"
    )
    assert params == [mapping.json_path, mapping.json_path]


def test_build_json_exists() -> None:
    builder = _builder()
    mapping = _registry_mapping("contact_keywords")

    clause, params = builder.build_clause("contact_keywords", "exists", None)

    assert clause == "json_type(original_metadata, ?) IS NOT NULL"
    assert params == [mapping.json_path]


def test_between_value_validation() -> None:
    builder = _builder()

    repo_root = _repo_root()
    sys.path.insert(0, str(repo_root / "apps" / "backend" / "src"))
    from core.search.condition_builder import ConditionBuilderError

    with pytest.raises(ConditionBuilderError):
        builder.build_clause("content_creation_date", "between", ["2024-01-01"])
