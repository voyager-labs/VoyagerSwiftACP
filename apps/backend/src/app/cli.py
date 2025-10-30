from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

from utils.paths import get_source_path

MAIN_FILE = get_source_path() / "app" / "main.py"


def _run_fastapi(*args: str, env: dict[str, str] | None = None) -> int:
    cmd = [sys.executable, "-m", "fastapi", *args]
    proc = subprocess.Popen(cmd, env=env)
    try:
        return proc.wait()
    except KeyboardInterrupt:
        try:
            proc.wait(timeout=1)
        except Exception:
            pass
        return 130


def _with_env(default_env: str) -> dict[str, str]:
    merged = os.environ.copy()
    merged.setdefault("APP_ENV", default_env)
    return merged


def dev() -> None:
    exit_code = _run_fastapi("dev", str(MAIN_FILE), env=_with_env("dev"))
    raise SystemExit(exit_code)


def prod() -> None:
    exit_code = _run_fastapi("run", str(MAIN_FILE), env=_with_env("prod"))
    raise SystemExit(exit_code)


def index() -> None:
    """파일 메타데이터 수집 CLI"""
    parser = argparse.ArgumentParser(description="파일 메타데이터 수집 및 DB 저장")
    parser.add_argument(
        "--path",
        type=str,
        default="~/Downloads",
        help="스캔할 디렉토리 경로 (기본값: ~/Downloads)",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=100,
        help="배치 저장 크기 (기본값: 100)",
    )
    parser.add_argument(
        "--exclude",
        type=str,
        nargs="+",
        default=[".git", ".venv", "node_modules", "Library/Caches"],
        help="제외할 디렉토리 목록",
    )

    args = parser.parse_args()

    # 동적 import (서버 실행 시 불필요한 import 방지)
    from app.config import load_config
    from app.file.file_services import convert_to_file_entry_schema
    from core.file_crawler.extractor import (
        convert_path_stat_osxmetadata,
        walk_files_concurrently,
    )
    from infra.db.engine import engine_manager
    from infra.repositories.file_entries import FileEntriesRepository

    # 설정 로드 및 DB 초기화
    cfg = load_config()
    engine_manager.initialize(cfg)
    engine_manager.create_tables()

    # 경로 처리
    scan_path = Path(args.path).expanduser().resolve()
    exclude_dirs = set(args.exclude)

    if not scan_path.exists():
        print(f"❌ 오류: 경로를 찾을 수 없습니다 - {scan_path}")
        raise SystemExit(1)

    print(f"📂 스캔 디렉토리: {scan_path}")
    print(f"🚫 제외 디렉토리: {', '.join(exclude_dirs)}")
    print(f"📦 배치 크기: {args.batch_size}")
    print("🔍 파일 크롤링 시작...\n")

    # 파일 수집
    file_count = 0
    batch = []
    exclude_count = 0

    def should_skip(path: Path) -> bool:
        return any(part in exclude_dirs for part in path.parts)

    try:
        with engine_manager.session() as session:
            repo = FileEntriesRepository(session)

            for path, stat, metadata in convert_path_stat_osxmetadata(
                walk_files_concurrently(scan_path), on_error="log"
            ):
                # 제외 디렉토리 필터링
                if should_skip(path):
                    exclude_count += 1
                    continue

                entry = convert_to_file_entry_schema(path, stat, metadata)
                batch.append(entry)
                file_count += 1

                # 진행 상황 출력
                if file_count % 10 == 0:
                    print(
                        f"⏳ 처리 중... {file_count}개 파일 발견 (제외: {exclude_count}개)",
                        end="\r",
                    )

                # 배치 저장
                if len(batch) >= args.batch_size:
                    repo.batch_upsert(batch)
                    print(f"✅ {len(batch)}개 파일 DB 저장 완료 (총 {file_count}개)       ")
                    batch = []

            # 남은 배치 처리
            if batch:
                repo.batch_upsert(batch)
                print(f"✅ 마지막 {len(batch)}개 파일 DB 저장 완료       ")

        print(f"\n🎉 완료! 총 {file_count}개 파일 수집 (제외: {exclude_count}개)")
        print(f"💡 http://localhost:8000/docs 에서 결과 확인 (서버 실행 필요)")

    except KeyboardInterrupt:
        print("\n\n⚠️  사용자가 중단했습니다")
        if batch:
            print(f"📝 마지막 배치 {len(batch)}개 파일 저장 중...")
            with engine_manager.session() as session:
                repo = FileEntriesRepository(session)
                repo.batch_upsert(batch)
        raise SystemExit(130)
    except Exception as e:
        print(f"\n❌ 오류 발생: {e}")
        raise SystemExit(1)
