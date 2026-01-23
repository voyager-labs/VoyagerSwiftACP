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

    assert clause == "uniform_type_identifier = :p0"
    assert params == {"p0": "public.png"}


def test_build_db_range_clause_for_date() -> None:
    builder = _builder()

    clause, params = builder.build_clause(
        "content_creation_date", "between", ["2024-01-01", "2024-12-31"]
    )

    assert clause == "DATE(content_creation_date) BETWEEN :p0 AND :p1"
    assert params == {"p0": "2024-01-01", "p1": "2024-12-31"}


def test_build_json_date_clause() -> None:
    builder = _builder()
    mapping = _registry_mapping("recording_date")

    clause, params = builder.build_clause("recording_date", "eq", "2024-01-01")

    assert clause == (
        f"DATE(CAST(json_extract(original_metadata, '{mapping.json_path}') AS TEXT)) = :p0"
    )
    assert params == {"p0": "2024-01-01"}


def test_build_json_string_list_contains_any() -> None:
    builder = _builder()
    mapping = _registry_mapping("contact_keywords")

    clause, params = builder.build_clause("contact_keywords", "contains_any", ["alpha", "beta"])

    assert clause == (
        "EXISTS (SELECT 1 FROM json_each(original_metadata, :p2) WHERE value IN (:p0, :p1))"
    )
    assert params == {"p0": "alpha", "p1": "beta", "p2": mapping.json_path}


def test_build_json_string_list_contains_all_dedupes_values() -> None:
    builder = _builder()
    mapping = _registry_mapping("contact_keywords")

    clause, params = builder.build_clause("contact_keywords", "contains_all", ["alpha", "alpha"])

    assert clause == (
        "(\n"
        "  SELECT COUNT(DISTINCT value)\n"
        "  FROM json_each(original_metadata, :p1)\n"
        "  WHERE value IN (:p0)\n"
        ") = :p2"
    )
    assert params == {"p0": "alpha", "p1": mapping.json_path, "p2": 1}


def test_build_json_string_list_empty() -> None:
    builder = _builder()
    mapping = _registry_mapping("contact_keywords")

    clause, params = builder.build_clause("contact_keywords", "empty", None)

    assert clause == (
        "(json_array_length(original_metadata, :p0) IS NULL OR "
        "json_array_length(original_metadata, :p1) = 0)"
    )
    assert params == {"p0": mapping.json_path, "p1": mapping.json_path}


def test_build_json_exists() -> None:
    builder = _builder()
    mapping = _registry_mapping("contact_keywords")

    clause, params = builder.build_clause("contact_keywords", "exists", None)

    assert clause == "json_type(original_metadata, :p0) IS NOT NULL"
    assert params == {"p0": mapping.json_path}


def test_between_value_validation() -> None:
    builder = _builder()

    repo_root = _repo_root()
    sys.path.insert(0, str(repo_root / "apps" / "backend" / "src"))
    from core.search.condition_builder import ConditionBuilderError

    with pytest.raises(ConditionBuilderError):
        builder.build_clause("content_creation_date", "between", ["2024-01-01"])
