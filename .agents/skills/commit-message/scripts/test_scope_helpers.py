#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import os
import sys
from collections import Counter
from typing import Callable, cast

SCRIPT_DIR = os.path.dirname(__file__)
MODULE_PATH = os.path.join(SCRIPT_DIR, "collect_staged_context.py")
SPEC = importlib.util.spec_from_file_location(
    "commit_message_collect_staged_context", MODULE_PATH
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Failed to load module spec for {MODULE_PATH}")
MODULE = importlib.util.module_from_spec(SPEC)
_ = sys.modules.setdefault("commit_message_collect_staged_context", MODULE)
_ = SPEC.loader.exec_module(MODULE)

_collapse_scope_candidates = cast(
    Callable[[list[str]], Counter[str]], MODULE._collapse_scope_candidates
)
_camel_to_kebab = cast(Callable[[str], str], MODULE._camel_to_kebab)
_infer_macos_scope = cast(Callable[[str], str | None], MODULE._infer_macos_scope)


def test_camel_to_kebab() -> None:
    cases = [
        ("EntryOperations", "entry-operations"),
        ("AI", "ai"),
        ("FileManager", "file-manager"),
    ]
    for value, expected in cases:
        assert _camel_to_kebab(value) == expected


def test_infer_helper() -> None:
    cases = [
        ("apps/macos/Voyager/VoyagerHelper/VoyagerHelperApp.swift", "helper"),
        (
            "apps/macos/Voyager/VoyagerHelper/Infrastructure/HelperStateBroadcaster.swift",
            "helper",
        ),
        (
            "apps/macos/Voyager/VoyagerHelper/Search/Service/SearchService.swift",
            "helper",
        ),
    ]
    for path, expected in cases:
        got = _infer_macos_scope(path)
        assert got == expected, (
            f"_infer_macos_scope({path!r}) = {got!r}, want {expected!r}"
        )


def test_infer_main_app_fsd() -> None:
    cases = [
        ("apps/macos/Voyager/Voyager/01_App/Reducer/AppReducer.swift", "main-app"),
        ("apps/macos/Voyager/Voyager/01_App/Config/Env.swift", "main-app"),
    ]
    for path, expected in cases:
        got = _infer_macos_scope(path)
        assert got == expected, (
            f"_infer_macos_scope({path!r}) = {got!r}, want {expected!r}"
        )


def test_infer_other_voyager_fsd_layer_scopes() -> None:
    cases = [
        (
            "apps/macos/Voyager/Voyager/02_Pages/FileManager/View.swift",
            "pages/file-manager",
        ),
        (
            "apps/macos/Voyager/Voyager/03_Widgets/EntryViewLayout/Helper.swift",
            "widgets/entry-view-layout",
        ),
        (
            "apps/macos/Voyager/Voyager/04_Features/Composer/Reducer.swift",
            "features/composer",
        ),
        (
            "apps/macos/Voyager/Voyager/04_Features/EntryArrangements/Reducer.swift",
            "features/entry-arrangements",
        ),
        (
            "apps/macos/Voyager/Voyager/05_Entities/Collection/Model.swift",
            "entities/collection",
        ),
        ("apps/macos/Voyager/Voyager/05_Entities/Entry/Entry.swift", "entities/entry"),
        ("apps/macos/Voyager/Voyager/05_Entities/Tag/Tag.swift", "entities/tag"),
        ("apps/macos/Voyager/Voyager/06_Shared/Ui/SomeView.swift", "shared"),
        ("apps/macos/Voyager/Voyager/06_Shared/Api/Client.swift", "shared"),
    ]
    for path, expected in cases:
        got = _infer_macos_scope(path)
        assert got == expected, (
            f"_infer_macos_scope({path!r}) = {got!r}, want {expected!r}"
        )


def test_infer_package_layer_scopes() -> None:
    cases = [
        (
            "apps/macos/Voyager/Packages/VoyagerModules/Sources/VoyagerPagesSettings/Foo.swift",
            "pages/settings",
        ),
        (
            "apps/macos/Voyager/Packages/VoyagerModules/Sources/VoyagerFeaturesEntryOperations/Bar.swift",
            "features/entry-operations",
        ),
        (
            "apps/macos/Voyager/Packages/VoyagerModules/Sources/VoyagerShared/Util.swift",
            "shared",
        ),
        (
            "apps/macos/Voyager/Packages/VoyagerModules/Sources/VoyagerEntitiesAI/AI.swift",
            "entities/ai",
        ),
        (
            "apps/macos/Voyager/Packages/VoyagerModules/Tests/VoyagerPagesSettingsTests/TestFoo.swift",
            "pages/settings",
        ),
        (
            "apps/macos/Voyager/Packages/VoyagerModules/Tests/VoyagerEntitiesAITests/TestAI.swift",
            "entities/ai",
        ),
    ]
    for path, expected in cases:
        got = _infer_macos_scope(path)
        assert got == expected, (
            f"_infer_macos_scope({path!r}) = {got!r}, want {expected!r}"
        )


def test_infer_returns_none_for_unmatched() -> None:
    no_match = [
        "apps/macos/Voyager/Voyager.xcodeproj/project.pbxproj",
        "apps/macos/Voyager/Package.swift",
        "apps/macos/Voyager/AGENTS.md",
        "apps/macos/Voyager/.swiftlint.yml",
        "apps/backend/main.py",
        "docs/index.md",
    ]
    for path in no_match:
        got = _infer_macos_scope(path)
        assert got is None, f"_infer_macos_scope({path!r}) = {got!r}, want None"


def test_collapse_helper_and_main_app_adds_macos() -> None:
    collapsed = _collapse_scope_candidates(["helper", "main-app"])
    assert collapsed["helper"] == 1
    assert collapsed["main-app"] == 1
    assert "macos" in collapsed
    assert collapsed["macos"] == 0


def test_collapse_main_app_only_no_macos() -> None:
    collapsed = _collapse_scope_candidates(["main-app", "main-app"])
    assert dict(collapsed) == {"main-app": 2}
    assert "macos" not in collapsed


def test_collapse_multiple_scopes_in_same_layer() -> None:
    collapsed = _collapse_scope_candidates(
        ["features/composer", "features/entry-operations"]
    )
    assert dict(collapsed) == {"features": 2}


def test_keep_single_layer_scope_when_clear_owner() -> None:
    collapsed = _collapse_scope_candidates(["pages/file-manager", "pages/file-manager"])
    assert dict(collapsed) == {"pages/file-manager": 2}


if __name__ == "__main__":
    test_camel_to_kebab()
    test_infer_helper()
    test_infer_main_app_fsd()
    test_infer_other_voyager_fsd_layer_scopes()
    test_infer_package_layer_scopes()
    test_infer_returns_none_for_unmatched()
    test_collapse_helper_and_main_app_adds_macos()
    test_collapse_main_app_only_no_macos()
    test_collapse_multiple_scopes_in_same_layer()
    test_keep_single_layer_scope_when_clear_owner()
    print("All tests passed.")
