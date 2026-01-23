from __future__ import annotations

import json
import sys
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def test_registry_json_exists() -> None:
    repo_root = _repo_root()
    mditem_path = repo_root / "shared" / "system_property_registry.json"
    assert mditem_path.exists()


def test_registry_json_structure() -> None:
    repo_root = _repo_root()
    mditem_path = repo_root / "shared" / "system_property_registry.json"
    mditem_data = json.loads(mditem_path.read_text(encoding="utf-8"))

    assert mditem_data.get("$kind") == "system_property_registry"
    assert "$version" in mditem_data

    assert "categories" in mditem_data
    assert "common" in mditem_data["categories"]
    assert "uniform_type_identifier" in mditem_data["categories"]["common"]


def test_loader_reads_registry() -> None:
    repo_root = _repo_root()
    sys.path.insert(0, str(repo_root / "apps" / "backend" / "src"))

    from core.metadata import SYSTEM_PROPERTY_REGISTRY

    mapping = SYSTEM_PROPERTY_REGISTRY.get("uniform_type_identifier")
    assert mapping is not None
    assert mapping.type.value == "string"
    assert mapping.system_keys
