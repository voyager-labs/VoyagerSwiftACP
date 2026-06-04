#!/usr/bin/env python3
# /// script
# requires-python = ">=3.13"
# dependencies = [
#   "ds-store==1.3.2",
#   "mac-alias==2.2.3",
# ]
# ///
import importlib
import math
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path
from types import ModuleType
from typing import Protocol, TypeAlias, cast


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_BACKGROUND_PATH = SCRIPT_DIR / "assets" / "dmg-background.png"
DEFAULT_WINDOW_WIDTH = 1200
DEFAULT_WINDOW_HEIGHT = 630
Pixel: TypeAlias = tuple[int, int, int]


class BytesConvertible(Protocol):
    def to_bytes(self) -> bytes:
        ...


class AliasFactory(Protocol):
    def for_file(self, path: str) -> BytesConvertible:
        ...


class DSStoreEntry(Protocol):
    def __setitem__(self, code: str, value: object) -> None:
        ...


class DSStoreWriter(Protocol):
    def __enter__(self) -> "DSStoreWriter":
        ...

    def __exit__(self, exc_type: object, exc_value: object, traceback: object) -> None:
        ...

    def __getitem__(self, filename: str) -> DSStoreEntry:
        ...


class DSStoreFactory(Protocol):
    def open(self, file_or_name: str, mode: str) -> DSStoreWriter:
        ...


def module_attr(module: ModuleType, name: str) -> object:
    return cast(object, getattr(module, name))


def log(message: str) -> None:
    print(message)


def fail(message: str) -> int:
    _ = sys.stderr.write(f"{message}\n")
    return 1


def env_flag(name: str, default: str) -> bool:
    return os.environ.get(name, default) == "1"


def env_int(name: str, default: int) -> int:
    return int(os.environ.get(name, str(default)))


def volume_name() -> str:
    return os.environ.get("DMG_VOLUME_NAME", "Voyager")


def png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + chunk_type
        + data
        + struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)
    )


def blend(base: Pixel, overlay: Pixel, alpha: float) -> Pixel:
    return (
        round((1.0 - alpha) * base[0] + alpha * overlay[0]),
        round((1.0 - alpha) * base[1] + alpha * overlay[1]),
        round((1.0 - alpha) * base[2] + alpha * overlay[2]),
    )


def draw_soft_circle(
    pixels: list[list[Pixel]],
    center_x: float,
    center_y: float,
    radius: float,
    color: Pixel,
    max_alpha: float,
) -> None:
    height = len(pixels)
    width = len(pixels[0])
    min_x = max(0, int(center_x - radius))
    max_x = min(width, int(center_x + radius) + 1)
    min_y = max(0, int(center_y - radius))
    max_y = min(height, int(center_y + radius) + 1)

    for y in range(min_y, max_y):
        for x in range(min_x, max_x):
            distance = math.hypot(x - center_x, y - center_y)
            if distance >= radius:
                continue
            alpha = max_alpha * math.pow(1.0 - distance / radius, 1.8)
            pixels[y][x] = blend(pixels[y][x], color, alpha)


def draw_line(
    pixels: list[list[Pixel]],
    start: tuple[int, int],
    end: tuple[int, int],
    color: Pixel,
    thickness: int,
) -> None:
    height = len(pixels)
    width = len(pixels[0])
    x1, y1 = start
    x2, y2 = end
    steps = max(abs(x2 - x1), abs(y2 - y1), 1)
    radius = max(1, thickness // 2)

    for step in range(steps + 1):
        t = step / steps
        center_x = round(x1 + (x2 - x1) * t)
        center_y = round(y1 + (y2 - y1) * t)
        for y in range(center_y - radius, center_y + radius + 1):
            if y < 0 or y >= height:
                continue
            for x in range(center_x - radius, center_x + radius + 1):
                if x < 0 or x >= width:
                    continue
                if (x - center_x) ** 2 + (y - center_y) ** 2 <= radius**2:
                    pixels[y][x] = color


def write_png(path: Path, pixels: list[list[Pixel]]) -> None:
    height = len(pixels)
    width = len(pixels[0])
    rows: list[bytes] = []
    for row in pixels:
        row_bytes = bytearray([0])
        for red, green, blue in row:
            row_bytes += bytes((red, green, blue))
        rows.append(bytes(row_bytes))

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    with path.open("wb") as handle:
        _ = handle.write(b"\x89PNG\r\n\x1a\n")
        _ = handle.write(png_chunk(b"IHDR", header))
        _ = handle.write(png_chunk(b"IDAT", zlib.compress(b"".join(rows), 9)))
        _ = handle.write(png_chunk(b"IEND", b""))


def generate_default_background(stage_dir: Path, width: int, height: int) -> Path:
    pixels: list[list[Pixel]] = []
    for y in range(height):
        row: list[Pixel] = []
        for x in range(width):
            horizontal = x / max(width - 1, 1)
            vertical = y / max(height - 1, 1)
            red = round(246 - 10 * horizontal + 8 * vertical)
            green = round(226 - 20 * horizontal + 10 * vertical)
            blue = round(240 - 5 * vertical)
            row.append((red, green, blue))
        pixels.append(row)

    draw_soft_circle(
        pixels, width * 0.50, height * 0.93, width * 0.32, (244, 232, 196), 0.58
    )
    draw_soft_circle(
        pixels, width * 0.47, height * 0.72, width * 0.23, (248, 221, 184), 0.34
    )
    draw_soft_circle(
        pixels, width * 0.88, height * 0.20, width * 0.28, (241, 223, 249), 0.42
    )
    draw_soft_circle(
        pixels, width * 0.15, height * 0.18, width * 0.30, (236, 224, 248), 0.35
    )

    arrow_color = (102, 97, 132)
    center_x = width // 2
    center_y = round(height * 0.53)
    draw_line(
        pixels, (center_x - 22, center_y), (center_x + 22, center_y), arrow_color, 5
    )
    draw_line(
        pixels, (center_x + 6, center_y - 18), (center_x + 24, center_y), arrow_color, 5
    )
    draw_line(
        pixels, (center_x + 6, center_y + 18), (center_x + 24, center_y), arrow_color, 5
    )

    background_path = stage_dir / "voyager-dmg-background.png"
    write_png(background_path, pixels)
    return background_path


def resolve_background_path(stage_dir: Path, width: int, height: int) -> Path:
    background = os.environ.get("DMG_BACKGROUND", "")
    if not background:
        if DEFAULT_BACKGROUND_PATH.is_file():
            return DEFAULT_BACKGROUND_PATH
        return generate_default_background(stage_dir, width, height)

    background_path = Path(background).expanduser()
    if not background_path.is_absolute():
        background_path = REPO_ROOT / background_path
    if not background_path.is_file():
        raise FileNotFoundError(f"DMG background not found: {background_path}")
    return background_path


def mount_point_from_attach_plist(plist_data: bytes) -> tuple[str, Path]:
    attach_info = cast(dict[str, object], plistlib.loads(plist_data))
    raw_entities = attach_info.get("system-entities", [])
    entities = cast(list[dict[str, object]], raw_entities)
    device = ""
    mount_point: Path | None = None
    for entity in entities:
        dev_entry = entity.get("dev-entry")
        mount_point_value = entity.get("mount-point")
        if not device and isinstance(dev_entry, str):
            device = dev_entry
        if isinstance(mount_point_value, str):
            mount_point = Path(mount_point_value)
            if isinstance(dev_entry, str):
                device = dev_entry
    if not device or mount_point is None:
        raise RuntimeError("Unable to resolve mounted DMG device and mount point.")
    return device, mount_point


def write_finder_ds_store(
    mount_point: Path,
    window_width: int,
    window_height: int,
    background_file_name: str,
) -> None:
    ds_store_module = importlib.import_module("ds_store")
    mac_alias_module = importlib.import_module("mac_alias")
    ds_store = cast(DSStoreFactory, module_attr(ds_store_module, "DSStore"))
    alias = cast(AliasFactory, module_attr(mac_alias_module, "Alias"))
    bookmark = cast(AliasFactory, module_attr(mac_alias_module, "Bookmark"))

    background_path = mount_point / ".background" / background_file_name
    background_alias = alias.for_file(str(background_path)).to_bytes()
    background_bookmark = bookmark.for_file(str(background_path)).to_bytes()

    bwsp = {
        "ShowStatusBar": False,
        "ShowToolbar": False,
        "ShowTabView": False,
        "ContainerShowSidebar": False,
        "WindowBounds": f"{{{{120, 120}}, {{{window_width}, {window_height}}}}}",
        "ShowSidebar": False,
    }
    icvp = {
        "backgroundColorBlue": 1.0,
        "backgroundColorGreen": 1.0,
        "backgroundColorRed": 1.0,
        "backgroundImageAlias": background_alias,
        "backgroundType": 2,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "iconSize": float(env_int("DMG_ICON_SIZE", 128)),
        "labelOnBottom": True,
        "showIconPreview": True,
        "showItemInfo": False,
        "textSize": float(env_int("DMG_TEXT_SIZE", 16)),
        "viewOptionsVersion": 1,
        "arrangeBy": "none",
    }

    with ds_store.open(str(mount_point / ".DS_Store"), "w+") as store:
        store["."]["bwsp"] = bwsp
        store["."]["icvp"] = icvp
        store["."]["pBB0"] = ("blob", bytearray(background_bookmark))
        store["Applications"]["Iloc"] = (
            env_int("DMG_APPLICATIONS_LINK_X", 786),
            env_int("DMG_APPLICATIONS_LINK_Y", 300),
        )
        store["Voyager.app"]["Iloc"] = (
            env_int("DMG_APP_ICON_X", 348),
            env_int("DMG_APP_ICON_Y", 300),
        )


def create_pretty_dmg(dmg_path: Path, contents_dir: Path, stage_dir: Path) -> None:
    window_width = env_int("DMG_WINDOW_WIDTH", DEFAULT_WINDOW_WIDTH)
    window_height = env_int("DMG_WINDOW_HEIGHT", DEFAULT_WINDOW_HEIGHT)
    background_path = resolve_background_path(stage_dir, window_width, window_height)

    applications_link = contents_dir / "Applications"
    applications_link.unlink(missing_ok=True)
    applications_link.symlink_to("/Applications")

    background_dir = contents_dir / ".background"
    background_dir.mkdir(exist_ok=True)
    background_file_name = "dmg-background@2x.png"
    _ = shutil.copy2(background_path, background_dir / background_file_name)

    rw_dmg_path = stage_dir / "rw.dmg"
    compressed_dmg_path = stage_dir / "compressed.dmg"
    _ = subprocess.run(
        [
            "hdiutil",
            "create",
            "-volname",
            volume_name(),
            "-srcfolder",
            str(contents_dir),
            "-ov",
            "-fs",
            "HFS+",
            "-format",
            "UDRW",
            str(rw_dmg_path),
        ],
        check=True,
    )

    attach_result = subprocess.run(
        [
            "hdiutil",
            "attach",
            str(rw_dmg_path),
            "-readwrite",
            "-noverify",
            "-noautoopen",
            "-nobrowse",
            "-plist",
        ],
        check=True,
        stdout=subprocess.PIPE,
    )
    device, mount_point = mount_point_from_attach_plist(attach_result.stdout)
    try:
        write_finder_ds_store(
            mount_point,
            window_width,
            window_height,
            background_file_name,
        )
        _ = subprocess.run(["sync"], check=True)
    finally:
        _ = subprocess.run(["hdiutil", "detach", device], check=True)

    _ = subprocess.run(
        [
            "hdiutil",
            "convert",
            str(rw_dmg_path),
            "-format",
            "UDZO",
            "-imagekey",
            "zlib-level=9",
            "-o",
            str(compressed_dmg_path),
        ],
        check=True,
    )
    _ = compressed_dmg_path.replace(dmg_path)


def create_plain_dmg(dmg_path: Path, contents_dir: Path) -> None:
    applications_link = contents_dir / "Applications"
    applications_link.symlink_to("/Applications")
    _ = subprocess.run(
        [
            "hdiutil",
            "create",
            "-volname",
            volume_name(),
            "-srcfolder",
            str(contents_dir),
            "-ov",
            "-format",
            "UDZO",
            str(dmg_path),
        ],
        check=True,
    )


def create_dmg(app_path: Path, dmg_path: Path) -> int:
    if not app_path.is_dir():
        return fail(f"App not found: {app_path}")

    dmg_path.parent.mkdir(parents=True, exist_ok=True)
    dmg_path.unlink(missing_ok=True)

    with tempfile.TemporaryDirectory(prefix="voyager-dmg-stage") as stage_name:
        stage_dir = Path(stage_name)
        contents_dir = stage_dir / "contents"
        contents_dir.mkdir()
        staged_app_path = contents_dir / "Voyager.app"
        _ = shutil.copytree(app_path, staged_app_path, symlinks=True)

        if env_flag("DMG_PRETTIFY", "1"):
            create_pretty_dmg(dmg_path, contents_dir, stage_dir)
        else:
            create_plain_dmg(dmg_path, contents_dir)

    if not dmg_path.is_file():
        return fail(f"DMG not created: {dmg_path}")

    log(f"Created DMG: {dmg_path}")
    return 0


def main() -> int:
    if len(sys.argv) != 3:
        _ = sys.stderr.write(
            "Usage: create-dmg.py /path/to/Voyager.app /path/to/Voyager.dmg\n"
        )
        return 1

    try:
        return create_dmg(Path(sys.argv[1]), Path(sys.argv[2]))
    except FileNotFoundError as error:
        return fail(str(error))
    except subprocess.CalledProcessError as error:
        return fail(f"Command failed with exit code {error.returncode}.")


if __name__ == "__main__":
    raise SystemExit(main())
