import logging
import os
import queue
import stat
import threading
from pathlib import Path
from typing import Generator, Iterable, Literal

from core.file_crawler.models import VoyagerFileMeta


def _process_directory_entry(
    entry: os.DirEntry[str],
    dir_q: queue.Queue[Path | None],
    out_q: queue.Queue[Path | None],
) -> None:
    """디렉토리 엔트리를 처리하여 파일 정보를 추출하거나 하위 디렉토리를 큐에 추가"""
    try:
        if entry.is_symlink():
            return
        if entry.is_dir(follow_symlinks=False):
            dir_q.put(Path(entry.path))
            return
        st = entry.stat(follow_symlinks=False)
        if stat.S_ISREG(st.st_mode):
            out_q.put(Path(entry.path))
    except (FileNotFoundError, PermissionError):
        pass


def _directory_scanner_worker(
    dir_q: queue.Queue[Path | None], out_q: queue.Queue[Path | None]
) -> None:
    """디렉토리를 스캔하여 파일들을 찾는 워커 함수"""
    while True:
        d: Path | None = dir_q.get()
        if d is None:
            dir_q.task_done()
            break
        try:
            with os.scandir(d) as it:
                for entry in it:
                    _process_directory_entry(entry, dir_q, out_q)
        except (FileNotFoundError, PermissionError):
            pass
        finally:
            dir_q.task_done()


def _shutdown_workers(
    dir_q: queue.Queue[Path | None],
    out_q: queue.Queue[Path | None],
    threads: list[threading.Thread],
    max_workers: int,
) -> None:
    """워커 스레드들을 정리하고 종료 신호를 보내는 함수"""
    dir_q.join()
    for _ in range(max_workers):
        dir_q.put(None)
    for t in threads:
        t.join()
    out_q.put(None)


def walk_files_concurrently(root: Path) -> Generator[Path]:
    """멀티스레드로 디렉토리 트리를 순회하며 '파일 경로(Path)만' 스트리밍 반환.

    동작
    - 심볼릭 링크는 건너뜁니다.
    - 디렉토리는 내보내지 않습니다(파일만 대상).
    - 예외(FileNotFoundError/PermissionError)는 내부에서 잡아 해당 엔트리만 스킵합니다.

    반환
    - 발견되는 각 파일의 절대 경로를 순차적으로 `yield`합니다.
    """
    root = root.expanduser().resolve(strict=True)
    max_workers = min(32, (os.cpu_count() or 1) * 2)

    dir_q: queue.Queue[Path | None] = queue.Queue()
    out_q: queue.Queue[Path | None] = queue.Queue()

    dir_q.put(root)

    threads = [
        threading.Thread(target=_directory_scanner_worker, args=(dir_q, out_q), daemon=True)
        for _ in range(max_workers)
    ]
    for t in threads:
        t.start()

    threading.Thread(
        target=_shutdown_workers, args=(dir_q, out_q, threads, max_workers), daemon=True
    ).start()

    while True:
        item = out_q.get()
        if item is None:
            break
        yield item


def to_voyager_file_meta(
    items: Iterable[Path],
    *,
    on_error: Literal["log", "skip", "raise"] = "log",
) -> Generator[VoyagerFileMeta, None, None]:
    """Path → VoyagerFileMeta 제너레이터 변환.

    - 입력: Iterable[Path]. 디렉토리는 조용히 스킵합니다.
    - on_error 정책:
      - "log": FileNotFoundError/PermissionError는 warning, 그 외 예외는 error(exc_info=True)로 로깅 후 스킵
      - "skip": 로깅 없이 스킵
      - "raise": 예외를 전파하여 스트림을 중단
    - logger: 사용자 지정 로거 사용 가능(미지정 시 "voyager.pipeline").
    - 반환: `VoyagerFileMeta` 항목을 순차적으로 생성하는 제너레이터.
    """
    # TODO: logger 세팅
    for path in items:
        try:
            yield VoyagerFileMeta.from_file_path(path)
        except (FileNotFoundError, PermissionError) as e:
            if on_error == "raise":
                raise
            if on_error == "log":
                logging.warning("Skip %s (%s): %s", path, e.__class__.__name__, e)
            continue
        except Exception as e:
            if on_error == "raise":
                raise
            if on_error == "log":
                logging.error("Error processing %s: %s", path, e, exc_info=True)
            continue
