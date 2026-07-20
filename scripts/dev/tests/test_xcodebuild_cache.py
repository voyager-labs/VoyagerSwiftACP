import contextlib
import fcntl
import io
import json
import shutil
import tempfile
import time
import unittest
from pathlib import Path
from typing import cast, final, override
from unittest.mock import patch

from scripts.dev import xcodebuild_cache


@final
class XcodebuildCacheTests(unittest.TestCase):
    temp_dir: tempfile.TemporaryDirectory[str] | None = None
    tmpdir: Path = Path()
    root: Path = Path()

    @override
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self.temp_dir.name)
        self.root = self.tmpdir / "cache"

    @override
    def tearDown(self) -> None:
        if self.temp_dir is not None:
            self.temp_dir.cleanup()

    def make_workspace(self, worktree: Path, resolved: object) -> Path:
        workspace = worktree / "App.xcworkspace"
        resolved_path = workspace / "xcshareddata/swiftpm/Package.resolved"
        resolved_path.parent.mkdir(parents=True)
        resolved_path.write_text(json.dumps(resolved))
        return workspace

    def make_project(self, worktree: Path, resolved: object) -> Path:
        project = worktree / "App.xcodeproj"
        resolved_path = (
            project / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        )
        resolved_path.parent.mkdir(parents=True)
        resolved_path.write_text(json.dumps(resolved))
        return project

    def resolve(
        self, worktree: Path, selection: xcodebuild_cache.Selection
    ) -> xcodebuild_cache.CachePaths:
        return xcodebuild_cache.resolve_cache_paths(
            root=self.root,
            worktree=worktree,
            selection=selection,
            xcode_version="Xcode 26.1\nBuild version 17B55\n",
            swift_version="Swift version 6.2.1\n",
        )

    def expire_metadata(self, entry: Path) -> None:
        metadata_path = entry / xcodebuild_cache.METADATA_FILE
        metadata = json.loads(metadata_path.read_text())
        metadata["updated_at"] = time.time() - 60 * 24 * 60 * 60
        metadata_path.write_text(json.dumps(metadata))

    def test_matching_dependency_and_toolchain_share_package_cache(self) -> None:
        first = self.tmpdir / "first"
        second = self.tmpdir / "second"
        first_paths = self.resolve(
            first,
            xcodebuild_cache.Selection(
                "workspace", self.make_workspace(first, {"pins": []})
            ),
        )
        second_paths = self.resolve(
            second,
            xcodebuild_cache.Selection(
                "workspace", self.make_workspace(second, {"pins": []})
            ),
        )

        self.assertEqual(first_paths.package_cache, second_paths.package_cache)
        self.assertNotEqual(first_paths.derived_data, second_paths.derived_data)
        self.assertNotEqual(first_paths.source_packages, second_paths.source_packages)

    def test_payload_paths_are_absolute_and_local_to_the_worktree(self) -> None:
        worktree = self.tmpdir / "worktree"
        paths = self.resolve(
            worktree,
            xcodebuild_cache.Selection(
                "workspace", self.make_workspace(worktree, {"pins": []})
            ),
        )

        self.assertEqual(
            paths.derived_data,
            (worktree / "build/dev/DerivedData").resolve(),
        )
        self.assertEqual(
            paths.source_packages,
            (worktree / "build/dev/SourcePackages").resolve(),
        )
        self.assertTrue(paths.derived_data.is_absolute())
        self.assertTrue(paths.source_packages.is_absolute())
        self.assertEqual(
            paths.worktree_entry,
            (self.root / "worktrees" / paths.worktree_key).resolve(),
        )

    def test_changed_resolved_xcode_or_swift_uses_distinct_package_cache(self) -> None:
        worktree = self.tmpdir / "worktree"
        workspace = self.make_workspace(worktree, {"pins": ["one"]})
        first = self.resolve(
            worktree, xcodebuild_cache.Selection("workspace", workspace)
        )
        workspace.joinpath("xcshareddata/swiftpm/Package.resolved").write_text(
            '{"pins":["two"]}'
        )
        changed_resolved = self.resolve(
            worktree, xcodebuild_cache.Selection("workspace", workspace)
        )
        changed_xcode = xcodebuild_cache.resolve_cache_paths(
            self.root,
            worktree,
            xcodebuild_cache.Selection("workspace", workspace),
            "Xcode 26.2\nBuild version next\n",
            "Swift version 6.2.1\n",
        )
        changed_swift = xcodebuild_cache.resolve_cache_paths(
            self.root,
            worktree,
            xcodebuild_cache.Selection("workspace", workspace),
            "Xcode 26.2\nBuild version next\n",
            "Swift version 6.3\n",
        )

        self.assertNotEqual(first.package_cache, changed_resolved.package_cache)
        self.assertNotEqual(changed_resolved.package_cache, changed_xcode.package_cache)
        self.assertNotEqual(changed_xcode.package_cache, changed_swift.package_cache)

    def test_selects_workspace_and_project_package_resolved_locations(self) -> None:
        worktree = self.tmpdir / "worktree"
        workspace = self.make_workspace(worktree, {"pins": ["workspace"]})
        project = self.make_project(worktree, {"pins": ["project"]})

        self.assertEqual(
            xcodebuild_cache.resolve_selection(
                ["-workspace", str(workspace)]
            ).resolved_path,
            (workspace / "xcshareddata/swiftpm/Package.resolved").resolve(),
        )
        self.assertEqual(
            xcodebuild_cache.resolve_selection(
                ["-project", str(project)]
            ).resolved_path,
            (
                project / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            ).resolve(),
        )

    def test_missing_or_malformed_resolved_fails_clearly(self) -> None:
        workspace = self.tmpdir / "missing/App.xcworkspace"
        selection = xcodebuild_cache.Selection("workspace", workspace)
        with self.assertRaisesRegex(ValueError, "Package.resolved"):
            self.resolve(workspace.parent, selection)

        resolved = workspace / "xcshareddata/swiftpm/Package.resolved"
        resolved.parent.mkdir(parents=True)
        resolved.write_text("not json")
        with self.assertRaisesRegex(ValueError, "Malformed"):
            self.resolve(workspace.parent, selection)

    def test_report_counts_cache_usage_and_prune_dry_run_does_not_delete(self) -> None:
        worktree = self.tmpdir / "retired"
        paths = self.resolve(
            worktree,
            xcodebuild_cache.Selection(
                "workspace", self.make_workspace(worktree, {"pins": []})
            ),
        )
        xcodebuild_cache.write_metadata(paths, worktree)
        paths.derived_data.mkdir(parents=True)
        paths.derived_data.joinpath("artifact").write_bytes(b"1234")
        self.expire_metadata(paths.worktree_entry)

        report = xcodebuild_cache.build_report(self.root, active_worktrees=set())
        result = xcodebuild_cache.prune_cache(
            self.root, active_worktrees=set(), older_than_days=30, apply=False
        )

        self.assertEqual(report["reclaimable_bytes"], 4)
        self.assertEqual(result.deleted, [])
        self.assertEqual(result.candidates, [paths.derived_data])
        self.assertTrue(paths.derived_data.exists())

    def test_apply_deletes_only_expired_orphan_entries(self) -> None:
        retired = self.tmpdir / "retired"
        active = self.tmpdir / "active"
        retired_paths = self.resolve(
            retired,
            xcodebuild_cache.Selection(
                "workspace", self.make_workspace(retired, {"pins": []})
            ),
        )
        active_paths = self.resolve(
            active,
            xcodebuild_cache.Selection(
                "workspace", self.make_workspace(active, {"pins": []})
            ),
        )
        for paths, worktree in ((retired_paths, retired), (active_paths, active)):
            xcodebuild_cache.write_metadata(paths, worktree)
            paths.derived_data.mkdir(parents=True)
            paths.derived_data.joinpath("artifact").write_bytes(b"x")
            self.expire_metadata(paths.worktree_entry)

        result = xcodebuild_cache.prune_cache(
            self.root,
            active_worktrees={active.resolve()},
            older_than_days=30,
            apply=True,
        )

        self.assertEqual(result.deleted, [retired_paths.derived_data])
        self.assertFalse(retired_paths.derived_data.exists())
        self.assertTrue(active_paths.derived_data.exists())
        self.assertTrue(retired_paths.worktree_entry.exists())

    def test_prune_protects_held_lock_and_rejects_path_traversal(self) -> None:
        worktree = self.tmpdir / "retired"
        paths = self.resolve(
            worktree,
            xcodebuild_cache.Selection(
                "workspace", self.make_workspace(worktree, {"pins": []})
            ),
        )
        xcodebuild_cache.write_metadata(paths, worktree)
        paths.derived_data.mkdir(parents=True)
        self.expire_metadata(paths.worktree_entry)
        paths.lock_path.parent.mkdir(parents=True)
        lock = paths.lock_path.open("w")
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            result = xcodebuild_cache.prune_cache(
                self.root, active_worktrees=set(), older_than_days=30, apply=True
            )
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)
            lock.close()

        outside = self.tmpdir / "outside"
        outside.mkdir()
        self.assertEqual(result.deleted, [])
        self.assertTrue(paths.derived_data.exists())
        self.assertFalse(xcodebuild_cache.is_safe_entry(self.root, outside))

    def test_build_locks_are_shared_and_prune_needs_exclusive_lock(self) -> None:
        worktree = self.tmpdir / "worktree"
        paths = self.resolve(
            worktree,
            xcodebuild_cache.Selection(
                "workspace", self.make_workspace(worktree, {"pins": []})
            ),
        )

        first = xcodebuild_cache.lock_for_build(paths)
        second = xcodebuild_cache.lock_for_build(paths)
        try:
            self.assertIsNone(
                xcodebuild_cache.try_exclusive_lock(paths.package_lock_path)
            )
            for handle in first:
                handle.close()
            self.assertIsNone(
                xcodebuild_cache.try_exclusive_lock(paths.package_lock_path)
            )
        finally:
            for handle in second:
                handle.close()

        exclusive = xcodebuild_cache.try_exclusive_lock(paths.package_lock_path)
        self.assertIsNotNone(exclusive)
        if exclusive is not None:
            exclusive.close()

    def test_package_cache_report_and_prune_only_when_unreferenced(self) -> None:
        retired = self.tmpdir / "retired"
        paths = self.resolve(
            retired,
            xcodebuild_cache.Selection(
                "workspace", self.make_workspace(retired, {"pins": []})
            ),
        )
        xcodebuild_cache.write_metadata(paths, retired)
        paths.package_cache.joinpath("artifact").write_bytes(b"package")
        self.expire_metadata(paths.package_cache)

        active_report = xcodebuild_cache.build_report(
            self.root, active_worktrees={retired.resolve()}
        )
        active_prune = xcodebuild_cache.prune_cache(
            self.root,
            active_worktrees={retired.resolve()},
            older_than_days=30,
            apply=True,
        )
        self.assertEqual(active_report["reclaimable_bytes"], 0)
        self.assertNotIn(paths.package_cache, active_prune.deleted)

        paths.worktree_entry.joinpath(xcodebuild_cache.METADATA_FILE).unlink()
        paths.worktree_entry.rmdir()
        report = xcodebuild_cache.build_report(self.root, active_worktrees=set())
        dry_run = xcodebuild_cache.prune_cache(
            self.root, active_worktrees=set(), older_than_days=30, apply=False
        )
        self.assertTrue(paths.package_cache.exists())
        applied = xcodebuild_cache.prune_cache(
            self.root, active_worktrees=set(), older_than_days=30, apply=True
        )

        self.assertEqual(report["reclaimable_bytes"], len(b"package"))
        self.assertIn(paths.package_cache, dry_run.candidates)
        self.assertIn(paths.package_cache, applied.deleted)
        self.assertFalse(paths.package_cache.exists())
        self.assertTrue(paths.package_lock_path.exists())

    def test_flag_resolution_does_not_create_cache_or_metadata(self) -> None:
        worktree = self.tmpdir / "worktree"
        workspace = self.make_workspace(worktree, {"pins": []})
        arguments = ["-workspace", str(workspace)]
        with patch.object(
            xcodebuild_cache,
            "current_toolchain",
            return_value=("Xcode 26.1\nBuild version 17B55\n", "Swift 6.2.1\n"),
        ):
            paths = xcodebuild_cache.resolve_from_arguments(
                arguments, root=self.root, worktree=worktree
            )

        self.assertFalse(paths.root.exists())
        self.assertFalse(paths.worktree_entry.exists())
        self.assertFalse(paths.package_cache.exists())

    def test_missing_or_malformed_cache_metadata_is_never_pruned(self) -> None:
        worktree_entry = self.root / "worktrees" / ("a" * 64)
        package_entry = self.root / "package-cache" / ("b" * 64)
        for entry in (worktree_entry, package_entry):
            entry.mkdir(parents=True)
            entry.joinpath(xcodebuild_cache.METADATA_FILE).write_text("not json")
            entry.joinpath("artifact").write_bytes(b"protected")

        result = xcodebuild_cache.prune_cache(
            self.root, active_worktrees=set(), older_than_days=0, apply=True
        )

        self.assertEqual(result.deleted, [])
        self.assertTrue(worktree_entry.exists())
        self.assertTrue(package_entry.exists())

    def test_dry_run_candidates_match_apply_for_expired_orphan_cache_pair(self) -> None:
        worktree = self.tmpdir / "retired"
        paths = self.resolve(
            worktree,
            xcodebuild_cache.Selection(
                "workspace", self.make_workspace(worktree, {"pins": []})
            ),
        )
        xcodebuild_cache.write_metadata(paths, worktree)
        paths.derived_data.mkdir(parents=True)
        paths.derived_data.joinpath("build").write_bytes(b"worktree")
        paths.package_cache.joinpath("package").write_bytes(b"package")
        self.expire_metadata(paths.worktree_entry)
        self.expire_metadata(paths.package_cache)

        report = xcodebuild_cache.build_report(self.root, active_worktrees=set())
        dry_run = xcodebuild_cache.prune_cache(
            self.root, active_worktrees=set(), older_than_days=30, apply=False
        )
        applied = xcodebuild_cache.prune_cache(
            self.root, active_worktrees=set(), older_than_days=30, apply=True
        )

        self.assertEqual(dry_run.candidates, [paths.derived_data, paths.package_cache])
        self.assertEqual(applied.deleted, dry_run.candidates)
        self.assertEqual(report["reclaimable_bytes"], len(b"worktreepackage"))

    def test_running_worktree_lock_keeps_referenced_package_cache_protected(
        self,
    ) -> None:
        worktree = self.tmpdir / "running"
        paths = self.resolve(
            worktree,
            xcodebuild_cache.Selection(
                "workspace", self.make_workspace(worktree, {"pins": []})
            ),
        )
        xcodebuild_cache.write_metadata(paths, worktree)
        paths.package_cache.joinpath("package").write_bytes(b"package")
        self.expire_metadata(paths.worktree_entry)
        self.expire_metadata(paths.package_cache)
        locks = xcodebuild_cache.lock_for_build(paths)
        try:
            result = xcodebuild_cache.prune_cache(
                self.root, active_worktrees=set(), older_than_days=30, apply=False
            )
        finally:
            for handle in locks:
                handle.close()

        self.assertNotIn(paths.derived_data, result.candidates)
        self.assertNotIn(paths.package_cache, result.candidates)
        self.assertIn(paths.package_cache, result.protected)

    def test_malformed_worktree_metadata_protects_valid_package_cache(self) -> None:
        worktree = self.tmpdir / "unknown"
        paths = self.resolve(
            worktree,
            xcodebuild_cache.Selection(
                "workspace", self.make_workspace(worktree, {"pins": []})
            ),
        )
        xcodebuild_cache.write_metadata(paths, worktree)
        paths.package_cache.joinpath("package").write_bytes(b"package")
        paths.worktree_entry.joinpath(xcodebuild_cache.METADATA_FILE).write_text(
            "not json"
        )
        self.expire_metadata(paths.package_cache)

        result = xcodebuild_cache.prune_cache(
            self.root, active_worktrees=set(), older_than_days=30, apply=True
        )

        self.assertNotIn(paths.package_cache, result.candidates)
        self.assertTrue(paths.package_cache.exists())

    def test_report_accounts_for_registered_legacy_worktree_without_mutation(
        self,
    ) -> None:
        legacy_worktree = self.tmpdir / "legacy"
        derived_artifact = legacy_worktree / "build/dev/DerivedData/artifact"
        source_artifact = legacy_worktree / "build/dev/SourcePackages/artifact"
        host_artifact = legacy_worktree / "build/dev/ComposerHostDerivedData/artifact"
        qa_artifact = legacy_worktree / "build/composerhost-qa/artifact"
        report_artifact = legacy_worktree / "build/dev/reports/build.log"
        derived_artifact.parent.mkdir(parents=True)
        source_artifact.parent.mkdir(parents=True)
        host_artifact.parent.mkdir(parents=True)
        qa_artifact.parent.mkdir(parents=True)
        report_artifact.parent.mkdir(parents=True)
        derived_artifact.write_bytes(b"derived")
        source_artifact.write_bytes(b"source")
        host_artifact.write_bytes(b"host")
        qa_artifact.write_bytes(b"qa")
        report_artifact.write_bytes(b"report")

        report = xcodebuild_cache.build_report(
            self.root, active_worktrees={legacy_worktree.resolve()}
        )
        result = xcodebuild_cache.prune_cache(
            self.root, active_worktrees={legacy_worktree.resolve()}, apply=False
        )

        legacy_worktrees = cast(list[dict[str, object]], report["legacy_worktrees"])
        self.assertEqual(len(legacy_worktrees), 1)
        self.assertEqual(
            legacy_worktrees[0]["bytes"], len(b"derivedsourcehostqareport")
        )
        self.assertEqual(legacy_worktrees[0]["extra_cache_bytes"], len(b"hostqa"))
        self.assertEqual(legacy_worktrees[0]["other_bytes"], len(b"report"))
        extra_caches = cast(
            list[dict[str, object]], legacy_worktrees[0]["extra_caches"]
        )
        self.assertEqual(
            {cache["name"] for cache in extra_caches},
            {"ComposerHostDerivedData", "composerhost-qa"},
        )
        self.assertEqual(report["total_bytes"], len(b"derivedsourcehostqareport"))
        self.assertEqual(result.candidates, [])
        self.assertEqual(derived_artifact.read_bytes(), b"derived")
        self.assertEqual(source_artifact.read_bytes(), b"source")
        self.assertEqual(host_artifact.read_bytes(), b"host")
        self.assertEqual(qa_artifact.read_bytes(), b"qa")

    def test_report_counts_registered_local_payload_once(self) -> None:
        worktree = self.tmpdir / "registered"
        paths = self.resolve(
            worktree,
            xcodebuild_cache.Selection(
                "workspace", self.make_workspace(worktree, {"pins": []})
            ),
        )
        xcodebuild_cache.write_metadata(paths, worktree)
        paths.derived_data.mkdir(parents=True)
        paths.source_packages.mkdir(parents=True)
        paths.derived_data.joinpath("derived").write_bytes(b"derived")
        paths.source_packages.joinpath("source").write_bytes(b"source")
        paths.worktree.joinpath("build/dev/reports/report.log").parent.mkdir(
            parents=True
        )
        paths.worktree.joinpath("build/dev/reports/report.log").write_bytes(b"report")

        report = xcodebuild_cache.build_report(
            self.root, active_worktrees={worktree.resolve()}
        )

        worktrees = cast(list[dict[str, object]], report["worktrees"])
        legacy_worktrees = cast(list[dict[str, object]], report["legacy_worktrees"])
        self.assertEqual(len(worktrees), 1)
        self.assertEqual(worktrees[0]["bytes"], len(b"derivedsource"))
        self.assertEqual(legacy_worktrees[0]["bytes"], len(b"report"))
        self.assertEqual(report["total_bytes"], len(b"derivedsourcereport"))

    def test_report_observes_valid_stale_central_payload_without_pruning_it(
        self,
    ) -> None:
        worktree = self.tmpdir / "registered"
        paths = self.resolve(
            worktree,
            xcodebuild_cache.Selection(
                "workspace", self.make_workspace(worktree, {"pins": []})
            ),
        )
        xcodebuild_cache.write_metadata(paths, worktree)
        paths.derived_data.mkdir(parents=True)
        paths.source_packages.mkdir(parents=True)
        paths.derived_data.joinpath("local-derived").write_bytes(b"local-derived")
        paths.source_packages.joinpath("local-source").write_bytes(b"local-source")
        central_derived = paths.worktree_entry / "DerivedData/central-derived"
        central_source = paths.worktree_entry / "SourcePackages/central-source"
        central_derived.parent.mkdir(parents=True)
        central_source.parent.mkdir(parents=True)
        central_derived.write_bytes(b"central-derived")
        central_source.write_bytes(b"central-source")

        report = xcodebuild_cache.build_report(
            self.root, active_worktrees={worktree.resolve()}
        )
        result = xcodebuild_cache.prune_cache(
            self.root, active_worktrees={worktree.resolve()}, apply=True
        )

        stale_entries = cast(list[dict[str, object]], report["stale_central_entries"])
        self.assertEqual(len(stale_entries), 1)
        self.assertEqual(stale_entries[0]["path"], str(paths.worktree_entry))
        self.assertEqual(
            stale_entries[0]["bytes"], len(b"central-derivedcentral-source")
        )
        self.assertEqual(
            report["total_bytes"],
            len(b"local-derivedlocal-sourcecentral-derivedcentral-source"),
        )
        self.assertNotIn(paths.worktree_entry, result.candidates)
        self.assertNotIn(paths.worktree_entry, result.deleted)
        self.assertTrue(central_derived.exists())
        self.assertTrue(central_source.exists())

    def test_prune_fails_closed_when_deleted_worktree_cannot_prove_payload_path(
        self,
    ) -> None:
        worktree = self.tmpdir / "deleted"
        paths = self.resolve(
            worktree,
            xcodebuild_cache.Selection(
                "workspace", self.make_workspace(worktree, {"pins": []})
            ),
        )
        xcodebuild_cache.write_metadata(paths, worktree)
        paths.derived_data.mkdir(parents=True)
        paths.derived_data.joinpath("artifact").write_bytes(b"protected")
        self.expire_metadata(paths.worktree_entry)
        shutil.rmtree(worktree)

        result = xcodebuild_cache.prune_cache(
            self.root, active_worktrees=set(), older_than_days=30, apply=True
        )

        self.assertEqual(result.deleted, [])
        self.assertEqual(result.candidates, [])
        self.assertIn(paths.worktree_entry, result.protected)

    def test_exec_os_error_returns_concise_cache_diagnostic(self) -> None:
        paths = xcodebuild_cache.CachePaths(
            self.root, self.tmpdir / "worktree", "worktree", "dependency"
        )
        stderr = io.StringIO()
        with (
            patch.object(
                xcodebuild_cache, "resolve_from_arguments", return_value=paths
            ),
            patch.object(
                xcodebuild_cache.os,
                "execvp",
                side_effect=FileNotFoundError(2, "No such file or directory"),
            ),
            contextlib.redirect_stderr(stderr),
        ):
            result = xcodebuild_cache.main(
                ["exec", "--", "/missing/xcodebuild", "-workspace", "ignored"]
            )

        self.assertEqual(result, 2)
        self.assertIn("xcodebuild cache:", stderr.getvalue())


if __name__ == "__main__":
    _ = unittest.main()
