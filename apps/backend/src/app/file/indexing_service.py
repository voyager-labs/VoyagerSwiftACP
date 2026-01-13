from __future__ import annotations

from collections.abc import Generator, Sequence
from pathlib import Path
from typing import Any

from app.file.file_services import convert_to_file_entry_schema
from core.file_crawler.extractor import (
    convert_path_stat_osxmetadata,
    walk_files_concurrently,
)
from infra.db.engine import engine_manager
from infra.repositories.file_entries import FileEntriesRepository

DEFAULT_BATCH_SIZE = 100
DEFAULT_EXCLUDES = [".git", ".venv", "node_modules", "Library/Caches"]
PROGRESS_INTERVAL = 100


def stream_indexing_events(
    *,
    paths: Sequence[str],
    batch_size: int,
    exclude: Sequence[str],
) -> Generator[dict[str, Any]]:
    """내부 테스트용 임시 인덱싱 스트림 이벤트 생성기."""
    exclude_set = set(exclude)
    total_processed = 0
    total_excluded = 0
    total_stored = 0
    valid_paths = 0

    yield {
        "event": "start",
        "paths": [str(Path(path).expanduser()) for path in paths],
        "batch_size": batch_size,
        "exclude": list(exclude_set),
    }

    for raw_path in paths:
        resolved_path = Path(raw_path).expanduser().resolve()
        if not resolved_path.exists():
            yield {
                "event": "path_error",
                "path": str(resolved_path),
                "reason": "not_found",
            }
            continue
        if not resolved_path.is_dir():
            yield {
                "event": "path_error",
                "path": str(resolved_path),
                "reason": "not_dir",
            }
            continue

        valid_paths += 1
        yield {"event": "path_start", "path": str(resolved_path)}

        path_processed = 0
        path_excluded = 0
        path_stored = 0
        batch = []

        def should_skip(path: Path) -> bool:
            return any(part in exclude_set for part in path.parts)

        try:
            with engine_manager.session(autocommit=False) as session:
                repo = FileEntriesRepository(session)
                items = walk_files_concurrently(resolved_path)
                for path, stat, metadata in convert_path_stat_osxmetadata(items, on_error="skip"):
                    if should_skip(path):
                        path_excluded += 1
                        total_excluded += 1
                        continue

                    entry = convert_to_file_entry_schema(path, stat, metadata)
                    batch.append(entry)
                    path_processed += 1
                    total_processed += 1

                    if len(batch) >= batch_size:
                        stored = _commit_batch(session, repo, batch)
                        path_stored += stored
                        total_stored += stored
                        batch = []
                        yield {
                            "event": "progress",
                            "path": str(resolved_path),
                            "processed": path_processed,
                            "excluded": path_excluded,
                            "stored": path_stored,
                        }
                    elif path_processed % PROGRESS_INTERVAL == 0:
                        yield {
                            "event": "progress",
                            "path": str(resolved_path),
                            "processed": path_processed,
                            "excluded": path_excluded,
                            "stored": path_stored,
                        }

                if batch:
                    stored = _commit_batch(session, repo, batch)
                    path_stored += stored
                    total_stored += stored
                    batch = []

        except Exception as exc:
            yield {
                "event": "path_error",
                "path": str(resolved_path),
                "reason": "exception",
                "details": exc.__class__.__name__,
            }
            continue

        yield {
            "event": "path_complete",
            "path": str(resolved_path),
            "summary": {
                "processed": path_processed,
                "excluded": path_excluded,
                "stored": path_stored,
            },
        }

    yield {
        "event": "complete",
        "summary": {
            "paths": valid_paths,
            "processed": total_processed,
            "excluded": total_excluded,
            "stored": total_stored,
        },
    }


def _commit_batch(
    session: Any,
    repo: FileEntriesRepository,
    batch: list[Any],
) -> int:
    try:
        repo.batch_upsert(batch)
        session.commit()
        return len(batch)
    except Exception:
        session.rollback()
        success = 0
        for entry in batch:
            try:
                repo.upsert_one(entry)
                session.commit()
                success += 1
            except Exception:
                session.rollback()
        return success
