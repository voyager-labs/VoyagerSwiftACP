from __future__ import annotations

import json
import sys
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def test_registry_json_exists() -> None:
    registry_path = _repo_root() / "shared" / "system_property_registry.json"
    assert registry_path.exists()


def test_registry_json_structure() -> None:
    registry_path = _repo_root() / "shared" / "system_property_registry.json"
    data = json.loads(registry_path.read_text(encoding="utf-8"))

    assert "$version" in data
    assert "property_key_registry" in data

    property_keys = data["property_key_registry"]
    mditem_keys = data

    assert "size" in property_keys
    assert "kMDItemContentType" in mditem_keys


def test_loader_reads_registry() -> None:
    repo_root = _repo_root()
    sys.path.insert(0, str(repo_root / "apps" / "backend" / "src"))

    from core.metadata import mditem_registry

    mapping = mditem_registry.get_property_key_mapping("size")
    assert mapping is not None
    assert mapping.db_field == "size"
    assert mapping.value_type.value == "number"
