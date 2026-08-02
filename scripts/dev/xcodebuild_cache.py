#!/usr/bin/env python3
"""Resolve, report, and safely prune macOS Xcode development build caches."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import IO, cast


DEFAULT_ROOT = Path.home() / "Library/Caches/Voyager/XcodeBuild"
DEFAULT_EXPIRY_DAYS = 30
METADATA_FILE = "metadata.json"


@dataclass(frozen=True)
class Selection:
    """The Xcode container that determines the SwiftPM resolution file."""

    kind: str
    path: Path

    @property
    def resolved_path(self) -> Path:
        if self.kind == "workspace":
            return self.path / "xcshareddata/swiftpm/Package.resolved"
        return self.path / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

    @property
    def identity(self) -> str:
        return f"{self.kind}:{self.path.name}"


@dataclass(frozen=True)
class CachePaths:
    """All cache paths assigned to one Xcode invocation."""

    root: Path
    worktree: Path
    worktree_key: str
    dependency_key: str

    @property
    def package_cache(self) -> Path:
        return self.root / "package-cache" / self.dependency_key

    @property
    def worktree_entry(self) -> Path:
        return self.root / "worktrees" / self.worktree_key

    @property
    def derived_data(self) -> Path:
        return self.worktree / "build/dev/DerivedData"

    @property
    def source_packages(self) -> Path:
        return self.worktree / "build/dev/SourcePackages"

    @property
    def lock_path(self) -> Path:
        return self.root / "locks/worktrees" / f"{self.worktree_key}.lock"

    @property
    def package_lock_path(self) -> Path:
        return self.root / "locks/package-cache" / f"{self.dependency_key}.lock"


@dataclass(frozen=True)
class PruneResult:
    """Candidate and deletion paths from one pruning pass."""

    candidates: list[Path]
    deleted: list[Path]
    protected: list[Path]


def configured_root(value: str | None = None) -> Path:
    """Return the explicit, environment, or macOS-conventional cache root."""
    configured = value or os.environ.get("VOYAGER_XCODE_CACHE_ROOT")
    return Path(configured).expanduser().resolve() if configured else DEFAULT_ROOT


def _hash(parts: Sequence[bytes]) -> str:
    digest = hashlib.sha256()
    for part in parts:
        digest.update(len(part).to_bytes(8, "big"))
        digest.update(part)
    return digest.hexdigest()


def _canonical_path(path: Path) -> Path:
    return path.expanduser().resolve()


def resolve_selection(arguments: Sequence[str]) -> Selection:
    """Extract exactly one Xcode workspace or project selection from arguments."""
    selections: list[Selection] = []
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        for flag, kind in (("-workspace", "workspace"), ("-project", "project")):
            if argument == flag:
                if index + 1 >= len(arguments):
                    raise ValueError(f"Missing value for {flag}")
                selections.append(
                    Selection(kind, _canonical_path(Path(arguments[index + 1])))
                )
                index += 1
                break
            if argument.startswith(f"{flag}="):
                selections.append(
                    Selection(kind, _canonical_path(Path(argument.split("=", 1)[1])))
                )
                break
        index += 1
    if len(selections) != 1:
        raise ValueError(
            "Exactly one -workspace or -project is required to resolve Package.resolved"
        )
    return selections[0]


def _resolved_bytes(selection: Selection) -> bytes:
    path = selection.resolved_path
    try:
        content = path.read_bytes()
    except FileNotFoundError as error:
        raise ValueError(f"Missing Package.resolved: {path}") from error
    try:
        decoded = content.decode("utf-8")
        parsed = cast(object, json.loads(decoded))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"Malformed Package.resolved: {path}") from error
    if not isinstance(parsed, dict):
        raise ValueError(f"Malformed Package.resolved: expected an object at {path}")
    return content


def resolve_cache_paths(
    root: Path,
    worktree: Path,
    selection: Selection,
    xcode_version: str,
    swift_version: str,
) -> CachePaths:
    """Compute deterministic shared and per-worktree cache locations."""
    canonical_root = _canonical_path(root)
    canonical_worktree = _canonical_path(worktree)
    resolved = _resolved_bytes(selection)
    dependency_key = _hash(
        [
            resolved,
            selection.identity.encode(),
            xcode_version.encode(),
            swift_version.encode(),
        ]
    )
    worktree_key = _hash([str(canonical_worktree).encode()])
    return CachePaths(canonical_root, canonical_worktree, worktree_key, dependency_key)


def _tool_output(command: Sequence[str]) -> str:
    completed = subprocess.run(
        command, check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    if completed.returncode:
        message = (
            completed.stderr.strip()
            or completed.stdout.strip()
            or "unknown tool failure"
        )
        raise ValueError(f"Unable to identify {' '.join(command)}: {message}")
    return completed.stdout


def current_toolchain() -> tuple[str, str]:
    """Read exact selected Xcode and Swift toolchain identities."""
    xcodebuild = os.environ.get("XCODEBUILD_REAL", "/usr/bin/xcodebuild")
    return _tool_output([xcodebuild, "-version"]), _tool_output(
        ["xcrun", "swift", "--version"]
    )


def write_metadata(
    paths: CachePaths, worktree: Path, entrypoint: str = "unknown"
) -> None:
    """Create safe cache directories and record stable ownership metadata."""
    _ = paths.worktree_entry.mkdir(parents=True, exist_ok=True)
    _ = paths.package_cache.mkdir(parents=True, exist_ok=True)
    now = time.time()
    worktree_data = {
        "dependency_key": paths.dependency_key,
        "entrypoint": entrypoint,
        "host": socket.gethostname(),
        "updated_at": now,
        "worktree": str(_canonical_path(worktree)),
    }
    package_data = {"dependency_key": paths.dependency_key, "updated_at": now}
    _atomic_write_json(paths.worktree_entry / METADATA_FILE, worktree_data)
    _atomic_write_json(paths.package_cache / METADATA_FILE, package_data)


def _atomic_write_json(path: Path, value: Mapping[str, object]) -> None:
    """Atomically replace metadata so concurrent readers see complete JSON only."""
    _ = path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w") as temporary:
            _ = temporary.write(json.dumps(value, sort_keys=True) + "\n")
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_path, path)
    except OSError:
        temporary_path.unlink(missing_ok=True)
        raise


def xcode_flags(paths: CachePaths) -> list[str]:
    """Return the three Xcode flags owned by this resolver."""
    return [
        "-derivedDataPath",
        str(paths.derived_data),
        "-clonedSourcePackagesDirPath",
        str(paths.source_packages),
        "-packageCachePath",
        str(paths.package_cache),
    ]


def owns_all_xcode_paths(arguments: Sequence[str], paths: CachePaths) -> bool:
    """Only register payloads when this resolver owns every cache path."""
    expected = dict(zip(xcode_flags(paths)[::2], xcode_flags(paths)[1::2], strict=True))
    found: dict[str, str] = {}
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument in expected and index + 1 < len(arguments):
            found[argument] = arguments[index + 1]
            index += 2
            continue
        for flag in expected:
            if argument.startswith(f"{flag}="):
                found[flag] = argument.split("=", 1)[1]
                break
        index += 1
    return found == expected


def _read_metadata(path: Path) -> dict[str, object] | None:
    try:
        data = cast(object, json.loads((path / METADATA_FILE).read_text()))
    except (FileNotFoundError, json.JSONDecodeError):
        return None
    return cast(dict[str, object], data) if isinstance(data, dict) else None


def active_worktree_paths() -> set[Path]:
    """Return canonical worktrees registered by Git without parsing human output."""
    completed = subprocess.run(
        ["git", "worktree", "list", "--porcelain"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode:
        raise ValueError(completed.stderr.strip() or "Unable to list Git worktrees")
    return {
        _canonical_path(Path(line.removeprefix("worktree ")))
        for line in completed.stdout.splitlines()
        if line.startswith("worktree ")
    }


def is_safe_entry(root: Path, entry: Path, category: str = "worktrees") -> bool:
    """Allow deletion only of real, direct cache children contained by ``root``."""
    canonical_root = _canonical_path(root)
    category_root = canonical_root / category
    try:
        return (
            entry.parent.resolve() == category_root.resolve()
            and entry.resolve().is_relative_to(canonical_root)
            and not entry.is_symlink()
        )
    except (FileNotFoundError, OSError):
        return False


def try_exclusive_lock(path: Path, create: bool = True) -> IO[str] | None:
    """Acquire an exclusive prune lock without waiting for a running build."""
    handle: IO[str] | None = None
    try:
        if create:
            _ = path.parent.mkdir(parents=True, exist_ok=True)
        handle = path.open("a+")
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (BlockingIOError, FileNotFoundError):
        if handle is not None:
            handle.close()
        return None
    return handle


def _metadata_updated_at(metadata: dict[str, object], entry: Path) -> float:
    value = metadata.get("updated_at")
    if isinstance(value, (float, int)) and not isinstance(value, bool) and value >= 0:
        return float(value)
    return entry.stat().st_mtime


def _eligible(metadata: dict[str, object], entry: Path, older_than_days: int) -> bool:
    return (
        time.time() - _metadata_updated_at(metadata, entry)
        >= older_than_days * 24 * 60 * 60
    )


def _payload_size(path: Path) -> int:
    """Measure cache payload only; stable locks and metadata are bookkeeping."""
    total = 0
    for directory, _, files in os.walk(path, followlinks=False):
        for file_name in files:
            if file_name in {METADATA_FILE, ".build.lock"}:
                continue
            candidate = Path(directory) / file_name
            if candidate.is_symlink():
                continue
            try:
                total += candidate.stat().st_size
            except FileNotFoundError:
                continue
    return total


def _central_payload_size(entry: Path) -> int:
    """Measure only abandoned central payload directories for observation."""
    total = 0
    try:
        canonical_entry = entry.resolve()
    except (FileNotFoundError, OSError):
        return 0
    for name in ("DerivedData", "SourcePackages"):
        payload = entry / name
        if not payload.is_dir() or payload.is_symlink():
            continue
        try:
            if payload.resolve() != canonical_entry / name:
                continue
        except (FileNotFoundError, OSError):
            continue
        total += _payload_size(payload)
    return total


def _legacy_worktree_usage(
    worktrees: set[Path], managed_worktrees: set[Path] | None = None
) -> list[dict[str, object]]:
    """Read non-managed build usage without following escaped paths."""
    usage: list[dict[str, object]] = []
    managed = managed_worktrees or set()
    for worktree in sorted(worktrees, key=str):
        canonical_worktree = _canonical_path(worktree)
        build_root = canonical_worktree / "build"
        if build_root.is_symlink() or not build_root.is_dir():
            continue
        try:
            if not build_root.resolve().is_relative_to(canonical_worktree):
                continue
        except FileNotFoundError:
            continue
        legacy_root = build_root / "dev"
        derived_data = legacy_root / "DerivedData"
        source_packages = legacy_root / "SourcePackages"
        derived_bytes = _payload_size(derived_data)
        source_bytes = _payload_size(source_packages)
        extra_caches: list[dict[str, object]] = []
        roots: list[Path] = list(build_root.iterdir())
        if legacy_root.is_dir() and not legacy_root.is_symlink():
            roots.extend(legacy_root.iterdir())
        for child in roots:
            if child.is_symlink() or not child.is_dir():
                continue
            if child.parent == legacy_root and child.name in {
                "DerivedData",
                "SourcePackages",
                "reports",
            }:
                continue
            if child.parent == build_root and child.name == "dev":
                continue
            try:
                if not child.resolve().is_relative_to(build_root):
                    continue
            except FileNotFoundError:
                continue
            extra_caches.append(
                {
                    "name": child.name,
                    "path": str(child),
                    "bytes": _payload_size(child),
                }
            )
        build_bytes = _payload_size(build_root)
        managed_payload_bytes = (
            derived_bytes + source_bytes if canonical_worktree in managed else 0
        )
        accounted_bytes = build_bytes - managed_payload_bytes
        extra_cache_bytes = sum(cast(int, entry["bytes"]) for entry in extra_caches)
        if accounted_bytes:
            usage.append(
                {
                    "worktree": str(canonical_worktree),
                    "build": str(build_root),
                    "derived_data": str(derived_data),
                    "source_packages": str(source_packages),
                    "derived_data_bytes": derived_bytes,
                    "source_packages_bytes": source_bytes,
                    "extra_caches": extra_caches,
                    "extra_cache_bytes": extra_cache_bytes,
                    "other_bytes": accounted_bytes
                    - extra_cache_bytes
                    - (
                        0
                        if canonical_worktree in managed
                        else derived_bytes + source_bytes
                    ),
                    "bytes": accounted_bytes,
                }
            )
    return usage


def _cache_entries(root: Path, category: str) -> list[Path]:
    directory = _canonical_path(root) / category
    if not directory.is_dir():
        return []
    return [
        entry
        for entry in directory.iterdir()
        if entry.is_dir() and is_safe_entry(root, entry, category)
    ]


@dataclass(frozen=True)
class PrunePlan:
    """A non-mutating snapshot of entries safe to delete under stable state."""

    worktree_candidates: list[Path]
    package_candidates: list[Path]
    protected: list[Path]

    @property
    def candidates(self) -> list[Path]:
        return [*self.worktree_candidates, *self.package_candidates]


def _lock_available(path: Path) -> bool:
    """Inspect an existing lease without creating a lock file during planning."""
    try:
        handle = path.open("r+")
    except FileNotFoundError:
        return True
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()
        return False
    handle.close()
    return True


def _trusted_worktree_metadata(
    entry: Path, metadata: dict[str, object]
) -> tuple[Path, str] | None:
    worktree = metadata.get("worktree")
    dependency_key = metadata.get("dependency_key")
    if not isinstance(worktree, str) or not isinstance(dependency_key, str):
        return None
    if not dependency_key or entry.name != _hash(
        [str(_canonical_path(Path(worktree))).encode()]
    ):
        return None
    return _canonical_path(Path(worktree)), dependency_key


def _managed_worktree_payloads(worktree: Path) -> list[Path] | None:
    """Return only real local payload directories proven inside ``build/dev``."""
    if not worktree.is_dir() or worktree.is_symlink():
        return None
    build_dev = worktree / "build/dev"
    if build_dev.is_symlink() or not build_dev.is_dir():
        return None
    try:
        canonical_worktree = worktree.resolve()
        canonical_build_dev = build_dev.resolve()
        if canonical_build_dev != canonical_worktree / "build/dev":
            return None
    except (FileNotFoundError, OSError):
        return None
    payloads: list[Path] = []
    for name in ("DerivedData", "SourcePackages"):
        payload = build_dev / name
        if not payload.exists():
            continue
        if payload.is_symlink() or not payload.is_dir():
            return None
        try:
            if payload.resolve() != canonical_build_dev / name:
                return None
        except (FileNotFoundError, OSError):
            return None
        payloads.append(payload)
    return payloads


def _trusted_package_metadata(entry: Path, metadata: dict[str, object]) -> bool:
    dependency_key = metadata.get("dependency_key")
    return isinstance(dependency_key, str) and dependency_key == entry.name


def plan_prune(
    root: Path,
    active_worktrees: set[Path],
    older_than_days: int,
    held_locks: set[Path] | None = None,
) -> PrunePlan:
    """Plan all safe deletions without writing locks or changing cache state."""
    protected: list[Path] = []
    held = held_locks or set()
    worktree_candidates: list[Path] = []
    survivors: list[tuple[Path, str]] = []
    protect_all_packages = False
    for entry in _cache_entries(root, "worktrees"):
        metadata = _read_metadata(entry)
        trusted = (
            _trusted_worktree_metadata(entry, metadata)
            if metadata is not None
            else None
        )
        if trusted is None:
            protected.append(entry)
            protect_all_packages = True
            continue
        assert metadata is not None
        worktree, dependency_key = trusted
        lock_path = root / "locks/worktrees" / f"{entry.name}.lock"
        payloads = _managed_worktree_payloads(worktree)
        if payloads is None:
            protected.append(entry)
            protect_all_packages = True
            continue
        if (
            worktree in active_worktrees
            or not _eligible(metadata, entry, older_than_days)
            or (lock_path not in held and not _lock_available(lock_path))
        ):
            protected.append(entry)
            survivors.append((entry, dependency_key))
            continue
        worktree_candidates.extend(payloads)

    referenced_keys = {dependency_key for _, dependency_key in survivors}
    package_candidates: list[Path] = []
    for entry in _cache_entries(root, "package-cache"):
        metadata = _read_metadata(entry)
        lock_path = root / "locks/package-cache" / f"{entry.name}.lock"
        if (
            metadata is None
            or not _trusted_package_metadata(entry, metadata)
            or protect_all_packages
            or entry.name in referenced_keys
            or not _eligible(metadata, entry, older_than_days)
            or (lock_path not in held and not _lock_available(lock_path))
        ):
            protected.append(entry)
            continue
        package_candidates.append(entry)
    return PrunePlan(worktree_candidates, package_candidates, protected)


def build_report(
    root: Path,
    active_worktrees: set[Path] | None = None,
    older_than_days: int = DEFAULT_EXPIRY_DAYS,
) -> dict[str, object]:
    """Summarize usage and reclaimable payload using the prune plan."""
    active = (
        active_worktrees if active_worktrees is not None else active_worktree_paths()
    )
    plan = plan_prune(root, active, older_than_days)
    candidates = set(plan.candidates)
    entries: list[dict[str, object]] = []
    stale_central_entries: list[dict[str, object]] = []
    for entry in _cache_entries(root, "worktrees"):
        metadata = _read_metadata(entry) or {}
        trusted = _trusted_worktree_metadata(entry, metadata)
        if trusted is None:
            stale_central_entries.append(
                {
                    "path": str(entry),
                    "bytes": _payload_size(entry),
                    "reason": "untrusted metadata",
                }
            )
            continue
        worktree, _ = trusted
        payloads = _managed_worktree_payloads(worktree)
        if payloads is None:
            stale_central_entries.append(
                {
                    "path": str(entry),
                    "bytes": _payload_size(entry),
                    "reason": "untrusted payload target",
                }
            )
            continue
        central_payload_bytes = _central_payload_size(entry)
        if central_payload_bytes:
            stale_central_entries.append(
                {
                    "path": str(entry),
                    "bytes": central_payload_bytes,
                    "reason": "abandoned central payload",
                }
            )
        derived_data = worktree / "build/dev/DerivedData"
        source_packages = worktree / "build/dev/SourcePackages"
        entries.append(
            {
                "path": str(entry),
                "worktree": str(worktree),
                "host": metadata.get("host"),
                "entrypoint": metadata.get("entrypoint"),
                "derived_data": str(derived_data),
                "source_packages": str(source_packages),
                "bytes": _payload_size(derived_data) + _payload_size(source_packages),
                "reclaimable": any(payload in candidates for payload in payloads),
            }
        )
    package_entries = [
        {
            "path": str(entry),
            "bytes": _payload_size(entry),
            "reclaimable": entry in candidates,
        }
        for entry in _cache_entries(root, "package-cache")
    ]
    legacy_worktrees = _legacy_worktree_usage(
        active, {Path(cast(str, entry["worktree"])) for entry in entries}
    )
    managed_bytes = sum(cast(int, entry["bytes"]) for entry in entries) + sum(
        cast(int, entry["bytes"]) for entry in package_entries
    )
    stale_central_bytes = sum(
        cast(int, entry["bytes"]) for entry in stale_central_entries
    )
    legacy_bytes = sum(cast(int, entry["bytes"]) for entry in legacy_worktrees)
    reclaimable = sum(_payload_size(entry) for entry in plan.worktree_candidates) + sum(
        _payload_size(entry) for entry in plan.package_candidates
    )
    return {
        "root": str(_canonical_path(root)),
        "worktrees": entries,
        "package_caches": package_entries,
        "stale_central_entries": stale_central_entries,
        "legacy_worktrees": legacy_worktrees,
        "total_bytes": managed_bytes + stale_central_bytes + legacy_bytes,
        "reclaimable_bytes": reclaimable,
    }


def _payload_lock_path(root: Path, payload: Path) -> Path | None:
    """Map a trusted local payload back to its central worktree lock."""
    for entry in _cache_entries(root, "worktrees"):
        metadata = _read_metadata(entry)
        trusted = (
            _trusted_worktree_metadata(entry, metadata)
            if metadata is not None
            else None
        )
        if trusted is None:
            continue
        payloads = _managed_worktree_payloads(trusted[0])
        if payloads is not None and payload in payloads:
            return root / "locks/worktrees" / f"{entry.name}.lock"
    return None


def prune_cache(
    root: Path,
    active_worktrees: set[Path] | None = None,
    older_than_days: int = DEFAULT_EXPIRY_DAYS,
    apply: bool = False,
) -> PruneResult:
    """Apply the same plan reported by dry-run, reacquiring leases before deletion."""
    if older_than_days < 0:
        raise ValueError("--older-than-days must be non-negative")
    active = (
        active_worktrees if active_worktrees is not None else active_worktree_paths()
    )
    plan = plan_prune(root, active, older_than_days)
    if not apply:
        return PruneResult(plan.candidates, [], plan.protected)
    deleted: list[Path] = []
    protected = list(plan.protected)
    for payload in plan.worktree_candidates:
        lock_path = _payload_lock_path(root, payload)
        if lock_path is None:
            protected.append(payload)
            continue
        lock = try_exclusive_lock(lock_path)
        if lock is None:
            protected.append(payload)
            continue
        try:
            refreshed = plan_prune(root, active, older_than_days, {lock_path})
            if payload not in refreshed.worktree_candidates:
                protected.append(payload)
                continue
            shutil.rmtree(payload)
            deleted.append(payload)
        finally:
            lock.close()
    for entry in plan.package_candidates:
        lock = try_exclusive_lock(root / "locks/package-cache" / f"{entry.name}.lock")
        if lock is None:
            protected.append(entry)
            continue
        try:
            refreshed = plan_prune(
                root,
                active,
                older_than_days,
                {root / "locks/package-cache" / f"{entry.name}.lock"},
            )
            if entry not in refreshed.package_candidates:
                protected.append(entry)
                continue
            if is_safe_entry(root, entry, "package-cache"):
                shutil.rmtree(entry)
                deleted.append(entry)
        finally:
            lock.close()
    return PruneResult(plan.candidates, deleted, protected)


def resolve_from_arguments(
    arguments: Sequence[str], root: Path | None = None, worktree: Path | None = None
) -> CachePaths:
    """Resolve paths only; flags generation must not create cache state."""
    selection = resolve_selection(arguments)
    xcode_version, swift_version = current_toolchain()
    selected_worktree = worktree or Path.cwd()
    return resolve_cache_paths(
        root or configured_root(),
        selected_worktree,
        selection,
        xcode_version,
        swift_version,
    )


def lock_for_build(paths: CachePaths) -> list[IO[str]]:
    """Serialize worktree builds while sharing package caches across worktrees."""
    handles: list[IO[str]] = []
    for path, operation in (
        (paths.lock_path, fcntl.LOCK_EX),
        (paths.package_lock_path, fcntl.LOCK_SH),
    ):
        _ = path.parent.mkdir(parents=True, exist_ok=True)
        handle = path.open("a+")
        fcntl.flock(handle, operation)
        os.set_inheritable(handle.fileno(), True)
        handles.append(handle)
    return handles


def parser() -> argparse.ArgumentParser:
    argument_parser = argparse.ArgumentParser(description=__doc__)
    subparsers = argument_parser.add_subparsers(dest="command", required=True)
    flags = subparsers.add_parser(
        "flags", help="print resolver-owned Xcode flags as NUL-delimited values"
    )
    _ = flags.add_argument("arguments", nargs=argparse.REMAINDER)
    execute = subparsers.add_parser(
        "exec", help="hold cache leases while executing Xcode"
    )
    _ = execute.add_argument("arguments", nargs=argparse.REMAINDER)
    report = subparsers.add_parser("report", help="report cache usage as JSON")
    _ = report.add_argument("--root")
    prune = subparsers.add_parser(
        "prune", help="report or delete expired orphan cache entries"
    )
    _ = prune.add_argument("--root")
    _ = prune.add_argument("--older-than-days", type=int, default=DEFAULT_EXPIRY_DAYS)
    _ = prune.add_argument("--apply", action="store_true")
    return argument_parser


def main(argv: Sequence[str] | None = None) -> int:
    """Run the resolver CLI."""
    args = parser().parse_args(argv)
    try:
        if args.command == "report":
            print(json.dumps(build_report(configured_root(args.root)), sort_keys=True))
            return 0
        if args.command == "prune":
            result = prune_cache(
                configured_root(args.root),
                older_than_days=args.older_than_days,
                apply=args.apply,
            )
            print(
                json.dumps(
                    {
                        "apply": args.apply,
                        "candidates": [str(path) for path in result.candidates],
                        "deleted": [str(path) for path in result.deleted],
                        "protected": [str(path) for path in result.protected],
                    },
                    sort_keys=True,
                )
            )
            return 0
        command = list(args.arguments)
        if command[:1] == ["--"]:
            command = command[1:]
        if args.command == "flags":
            paths = resolve_from_arguments(command)
            sys.stdout.buffer.write("\0".join(xcode_flags(paths)).encode() + b"\0")
            return 0
        if not command:
            raise ValueError("exec requires a command after --")
        paths = resolve_from_arguments(command[1:])
        _ = lock_for_build(paths)
        if owns_all_xcode_paths(command[1:], paths):
            write_metadata(
                paths,
                Path.cwd(),
                os.environ.get("VOYAGER_XCODE_CACHE_ENTRYPOINT", "xcodebuild-wrapper"),
            )
        os.execvp(command[0], command)
    except (OSError, ValueError) as error:
        print(f"xcodebuild cache: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
