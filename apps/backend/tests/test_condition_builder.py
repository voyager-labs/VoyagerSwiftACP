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

    clause, params = builder.build_clause(
        "uniform_type_identifier", "any", ["public.png", "public.jpeg"]
    )

    assert clause == "uniform_type_identifier IN (:p0, :p1)"
    assert params == {"p0": "public.png", "p1": "public.jpeg"}


def test_build_db_range_clause_for_date() -> None:
    builder = _builder()

    clause, params = builder.build_clause(
        "content_creation_date", "btw", ["2024-01-01", "2024-12-31"]
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

    clause, params = builder.build_clause("contact_keywords", "any", ["alpha", "beta"])

    assert clause == (
        "json_type(original_metadata, :p2) = 'array' AND "
        "EXISTS (SELECT 1 FROM json_each(original_metadata, :p2) WHERE value IN (:p0, :p1))"
    )
    assert params == {"p0": "alpha", "p1": "beta", "p2": mapping.json_path}


def test_build_json_categorical_any() -> None:
    builder = _builder()
    mapping = _registry_mapping("city")

    clause, params = builder.build_clause("city", "any", ["Seoul", "Busan"])

    assert clause == (
        f"CAST(json_extract(original_metadata, '{mapping.json_path}') AS TEXT) IN (:p0, :p1)"
    )
    assert params == {"p0": "Seoul", "p1": "Busan"}


def test_build_json_categorical_none() -> None:
    builder = _builder()
    mapping = _registry_mapping("city")

    clause, params = builder.build_clause("city", "none", ["Seoul", "Busan"])

    assert clause == (
        f"CAST(json_extract(original_metadata, '{mapping.json_path}') AS TEXT) NOT IN (:p0, :p1)"
    )
    assert params == {"p0": "Seoul", "p1": "Busan"}


def test_build_db_string_any_of_clause() -> None:
    builder = _builder()

    clause, params = builder.build_clause("extension", "any", ["pdf", "png"])

    assert clause == "extension IN (:p0, :p1)"
    assert params == {"p0": "pdf", "p1": "png"}


def test_build_json_string_list_contains_all_dedupes_values() -> None:
    builder = _builder()
    mapping = _registry_mapping("contact_keywords")

    clause, params = builder.build_clause("contact_keywords", "all", ["alpha", "alpha"])

    assert clause == (
        "(\n"
        "  SELECT (json_type(original_metadata, :p1) = 'array') AND COUNT(DISTINCT value)\n"
        "  FROM json_each(original_metadata, :p1)\n"
        "  WHERE value IN (:p0)\n"
        ") = :p2"
    )
    assert params == {"p0": "alpha", "p1": mapping.json_path, "p2": 1}


def test_build_db_string_list_any_uses_in_clause() -> None:
    builder = _builder()

    clause, params = builder.build_clause(
        "uniform_type_identifier", "any", ["public.png", "public.jpeg"]
    )

    assert clause == "uniform_type_identifier IN (:p0, :p1)"
    assert params == {"p0": "public.png", "p1": "public.jpeg"}


def test_build_db_string_list_none_uses_not_in_clause() -> None:
    builder = _builder()

    clause, params = builder.build_clause("uniform_type_identifier", "none", ["public.png"])

    assert clause == "uniform_type_identifier != :p0"
    assert params == {"p0": "public.png"}


def test_build_db_string_list_none_uses_not_in_clause_for_multi_value() -> None:
    builder = _builder()

    clause, params = builder.build_clause(
        "uniform_type_identifier", "none", ["public.png", "public.jpeg"]
    )

    assert clause == "uniform_type_identifier NOT IN (:p0, :p1)"
    assert params == {"p0": "public.png", "p1": "public.jpeg"}


def test_build_contains_wraps_like_pattern() -> None:
    builder = _builder()

    clause, params = builder.build_clause("name_stem", "cn", "report")

    assert clause == "name_stem LIKE :p0"
    assert params == {"p0": "%report%"}


def test_build_json_string_list_empty() -> None:
    builder = _builder()
    mapping = _registry_mapping("contact_keywords")

    clause, params = builder.build_clause("contact_keywords", "empty", None)

    assert clause == (
        "(json_type(original_metadata, :p0) IS NULL OR "
        "(json_type(original_metadata, :p0) = 'array' AND "
        "json_array_length(original_metadata, :p0) = 0))"
    )
    assert params == {"p0": mapping.json_path}


def test_build_json_exists() -> None:
    builder = _builder()
    mapping = _registry_mapping("contact_keywords")

    clause, params = builder.build_clause("contact_keywords", "exists", None)

    assert clause == "json_type(original_metadata, :p0) IS NOT NULL"
    assert params == {"p0": mapping.json_path}


def test_build_json_string_list_not_any() -> None:
    builder = _builder()
    mapping = _registry_mapping("contact_keywords")

    clause, params = builder.build_clause("contact_keywords", "none", ["alpha", "beta"])

    assert clause == (
        "NOT (json_type(original_metadata, :p2) = 'array' AND "
        "EXISTS (SELECT 1 FROM json_each(original_metadata, :p2) WHERE value IN (:p0, :p1)))"
    )
    assert params == {"p0": "alpha", "p1": "beta", "p2": mapping.json_path}


def test_build_where_missing_property_key_raises() -> None:
    builder = _builder()

    repo_root = _repo_root()
    sys.path.insert(0, str(repo_root / "apps" / "backend" / "src"))
    from core.search.condition_builder import ConditionBuilderError

    with pytest.raises(ConditionBuilderError):
        builder.build_where([{"operator": "eq", "value": "png"}])


def test_build_json_categorical_empty() -> None:
    builder = _builder()
    mapping = _registry_mapping("city")

    clause, params = builder.build_clause("city", "empty", None)

    assert clause == (
        f"(CAST(json_extract(original_metadata, '{mapping.json_path}') AS TEXT) IS NULL "
        f"OR CAST(json_extract(original_metadata, '{mapping.json_path}') AS TEXT) = '')"
    )
    assert params == {}


def test_build_where_missing_operator_raises() -> None:
    builder = _builder()

    repo_root = _repo_root()
    sys.path.insert(0, str(repo_root / "apps" / "backend" / "src"))
    from core.search.condition_builder import ConditionBuilderError

    with pytest.raises(ConditionBuilderError):
        builder.build_where([{"propertyKey": "extension", "value": "png"}])


def test_build_categorical_all_raises() -> None:
    builder = _builder()

    repo_root = _repo_root()
    sys.path.insert(0, str(repo_root / "apps" / "backend" / "src"))
    from core.search.condition_builder import ConditionBuilderError

    with pytest.raises(ConditionBuilderError):
        builder.build_clause("city", "all", ["Seoul"])


def test_between_value_validation() -> None:
    builder = _builder()

    repo_root = _repo_root()
    sys.path.insert(0, str(repo_root / "apps" / "backend" / "src"))
    from core.search.condition_builder import ConditionBuilderError

    with pytest.raises(ConditionBuilderError):
        builder.build_clause("content_creation_date", "btw", ["2024-01-01"])
