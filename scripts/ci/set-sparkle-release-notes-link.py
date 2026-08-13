from __future__ import annotations

import os
import sys
import tempfile
import xml.etree.ElementTree as element_tree
from pathlib import Path


SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SHORT_VERSION_TAG = f"{{{SPARKLE_NAMESPACE}}}shortVersionString"
RELEASE_NOTES_TAG = f"{{{SPARKLE_NAMESPACE}}}releaseNotesLink"


def set_release_notes_link(
    appcast_path: Path | str,
    version: str,
    release_notes_url: str,
) -> None:
    path = Path(appcast_path)
    tree = element_tree.parse(path)
    root = tree.getroot()

    if root.tag != "rss":
        raise ValueError("appcast root must be rss")

    channels = [child for child in root if child.tag == "channel"]
    if len(channels) != 1:
        raise ValueError("appcast must contain exactly one direct channel")

    matching_items = [
        item
        for item in channels[0]
        if item.tag == "item"
        and any(
            child.tag == SHORT_VERSION_TAG and child.text == version for child in item
        )
    ]
    if len(matching_items) != 1:
        raise ValueError(f"expected exactly one appcast item for version {version}")

    target_item = matching_items[0]
    release_notes_links = [
        child for child in target_item if child.tag == RELEASE_NOTES_TAG
    ]
    if len(release_notes_links) > 1:
        raise ValueError("target appcast item has duplicate release notes links")

    if not release_notes_links:
        release_notes_link = element_tree.Element(RELEASE_NOTES_TAG)
        release_notes_link.text = release_notes_url
        target_item.append(release_notes_link)
    elif (
        release_notes_links[0].text != release_notes_url
        or release_notes_links[0].attrib
    ):
        existing_link = release_notes_links[0]
        replacement_link = element_tree.Element(RELEASE_NOTES_TAG)
        replacement_link.text = release_notes_url
        replacement_link.tail = existing_link.tail
        target_item.insert(list(target_item).index(existing_link), replacement_link)
        target_item.remove(existing_link)

    element_tree.register_namespace("sparkle", SPARKLE_NAMESPACE)
    _write_atomically(root, path)


def _write_atomically(root: element_tree.Element[str], path: Path) -> None:
    descriptor, temporary_path_string = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
    )
    temporary_path = Path(temporary_path_string)
    try:
        with os.fdopen(descriptor, "wb") as temporary_file:
            element_tree.ElementTree(root).write(
                temporary_file,
                encoding="utf-8",
                xml_declaration=True,
            )
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.replace(temporary_path, path)
    except BaseException:
        temporary_path.unlink(missing_ok=True)
        raise


def main(arguments: list[str]) -> int:
    if len(arguments) != 3:
        print(
            "usage: set-sparkle-release-notes-link.py "
            "appcast-path version release-notes-url",
            file=sys.stderr,
        )
        return 2

    try:
        set_release_notes_link(*arguments)
    except (OSError, ValueError, element_tree.ParseError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
