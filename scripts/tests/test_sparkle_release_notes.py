from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as element_tree
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MUTATOR_SCRIPT = REPO_ROOT / "scripts/ci/set-sparkle-release-notes-link.py"
APPCAST_SCRIPT = REPO_ROOT / "scripts/ci/generate-sparkle-appcast.sh"
SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SHORT_VERSION_TAG = f"{{{SPARKLE_NAMESPACE}}}shortVersionString"
RELEASE_NOTES_TAG = f"{{{SPARKLE_NAMESPACE}}}releaseNotesLink"
FULL_RELEASE_NOTES_TAG = f"{{{SPARKLE_NAMESPACE}}}fullReleaseNotesLink"
VERSION = "0.8.4"
RELEASE_NOTES_URL = f"https://voyager.fm/api/changelog/{VERSION}/sparkle"


def appcast_xml(target_release_notes: str = "") -> bytes:
    return f"""<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<rss xmlns:sparkle=\"{SPARKLE_NAMESPACE}\" version=\"2.0\">
  <channel>
    <item>
      <title>Older release</title>
      <sparkle:shortVersionString>0.8.3</sparkle:shortVersionString>
      <sparkle:releaseNotesLink xml:lang=\"ko\">https://voyager.fm/changelog/0.8.3</sparkle:releaseNotesLink>
      <enclosure url=\"https://stale.invalid/Voyager-0.8.3.zip\" sparkle:edSignature=\"older-signature\" sparkle:version=\"803\" />
    </item>
    <item>
      <title>Current release</title>
      <sparkle:shortVersionString>{VERSION}</sparkle:shortVersionString>
      {target_release_notes}
      <sparkle:fullReleaseNotesLink>https://voyager.fm/changelog/{VERSION}</sparkle:fullReleaseNotesLink>
      <metadata><sparkle:releaseNotesLink keep=\"yes\">nested link</sparkle:releaseNotesLink></metadata>
      <enclosure url=\"https://stale.invalid/Voyager-{VERSION}.zip\" sparkle:edSignature=\"target-signature\" sparkle:version=\"804\" />
    </item>
    <item>
      <title>Future release</title>
      <sparkle:shortVersionString>0.8.5</sparkle:shortVersionString>
      <enclosure url=\"https://stale.invalid/Voyager-0.8.5.zip\" sparkle:edSignature=\"future-signature\" sparkle:version=\"805\" />
    </item>
  </channel>
</rss>
""".encode("utf-8")


def direct_items(root: element_tree.Element) -> list[element_tree.Element]:
    channel = root.find("channel")
    assert channel is not None
    return channel.findall("item")


def item_for_version(root: element_tree.Element, version: str) -> element_tree.Element:
    matches = [
        item
        for item in direct_items(root)
        if item.findtext(SHORT_VERSION_TAG) == version
    ]
    assert len(matches) == 1
    return matches[0]


def direct_release_notes(item: element_tree.Element) -> list[element_tree.Element]:
    return [child for child in item if child.tag == RELEASE_NOTES_TAG]


def write_executable(path: Path, content: str) -> None:
    _ = path.write_text(content, encoding="utf-8")
    _ = path.chmod(0o755)


class SparkleReleaseNotesMutatorContractTests(unittest.TestCase):
    def run_mutator(self, appcast_path: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "python3",
                str(MUTATOR_SCRIPT),
                str(appcast_path),
                VERSION,
                RELEASE_NOTES_URL,
            ],
            cwd=REPO_ROOT,
            env=os.environ | {"PATH": os.environ["PATH"]},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def assert_managed_link(self, appcast_path: Path) -> element_tree.Element:
        root = element_tree.parse(appcast_path).getroot()
        target_item = item_for_version(root, VERSION)
        managed_links = direct_release_notes(target_item)
        self.assertEqual(len(managed_links), 1)
        self.assertEqual(managed_links[0].text, RELEASE_NOTES_URL)
        self.assertEqual(managed_links[0].attrib, {})
        return root

    def test_cli_mutates_a_temporary_v084_copy_without_changing_unrelated_metadata(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            template_path = root / "template.xml"
            appcast_path = root / "appcast.xml"
            _ = template_path.write_bytes(appcast_xml())
            _ = appcast_path.write_bytes(template_path.read_bytes())
            original_root = element_tree.parse(template_path).getroot()
            original_old_item = element_tree.tostring(direct_items(original_root)[0])
            original_target_enclosure = item_for_version(original_root, VERSION).find(
                "enclosure"
            )
            assert original_target_enclosure is not None

            result = self.run_mutator(appcast_path)

            self.assertEqual(result.returncode, 0, result.stderr)
            root_element = self.assert_managed_link(appcast_path)
            self.assertEqual(
                element_tree.tostring(direct_items(root_element)[0]),
                original_old_item,
            )
            target_item = item_for_version(root_element, VERSION)
            target_enclosure = target_item.find("enclosure")
            self.assertIsNotNone(target_enclosure)
            assert target_enclosure is not None
            self.assertEqual(target_enclosure.attrib, original_target_enclosure.attrib)
            self.assertEqual(target_item.findtext(SHORT_VERSION_TAG), VERSION)
            self.assertEqual(
                target_item.findtext(FULL_RELEASE_NOTES_TAG),
                f"https://voyager.fm/changelog/{VERSION}",
            )
            nested_link = target_item.find(f"metadata/{RELEASE_NOTES_TAG}")
            self.assertIsNotNone(nested_link)
            assert nested_link is not None
            self.assertEqual(nested_link.text, "nested link")
            self.assertEqual(nested_link.attrib, {"keep": "yes"})

    def test_cli_retains_an_exact_singleton_release_notes_link(self) -> None:
        direct_link = (
            f"<sparkle:releaseNotesLink>{RELEASE_NOTES_URL}</sparkle:releaseNotesLink>"
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            appcast_path = Path(temporary_directory) / "appcast.xml"
            _ = appcast_path.write_bytes(appcast_xml(direct_link))

            result = self.run_mutator(appcast_path)

            self.assertEqual(result.returncode, 0, result.stderr)
            _ = self.assert_managed_link(appcast_path)

    def test_cli_canonicalizes_attributes_on_an_exact_singleton_link(self) -> None:
        direct_link = (
            f'<sparkle:releaseNotesLink xml:lang="ko" source="legacy">'
            f"{RELEASE_NOTES_URL}"
            "</sparkle:releaseNotesLink>"
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            appcast_path = Path(temporary_directory) / "appcast.xml"
            _ = appcast_path.write_bytes(appcast_xml(direct_link))

            result = self.run_mutator(appcast_path)

            self.assertEqual(result.returncode, 0, result.stderr)
            _ = self.assert_managed_link(appcast_path)

    def test_cli_replaces_a_different_singleton_release_notes_link(self) -> None:
        direct_link = (
            '<sparkle:releaseNotesLink xml:lang="ko" source="legacy">'
            "https://voyager.fm/changelog/legacy"
            "</sparkle:releaseNotesLink>"
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            appcast_path = Path(temporary_directory) / "appcast.xml"
            _ = appcast_path.write_bytes(appcast_xml(direct_link))

            result = self.run_mutator(appcast_path)

            self.assertEqual(result.returncode, 0, result.stderr)
            _ = self.assert_managed_link(appcast_path)

    def test_cli_rejects_invalid_xml_or_ambiguous_targets_without_writing(self) -> None:
        duplicate_links = (
            "<sparkle:releaseNotesLink>one</sparkle:releaseNotesLink>"
            "<sparkle:releaseNotesLink>two</sparkle:releaseNotesLink>"
        )
        multiple_targets = appcast_xml().replace(
            b"<sparkle:shortVersionString>0.8.5</sparkle:shortVersionString>",
            f"<sparkle:shortVersionString>{VERSION}</sparkle:shortVersionString>".encode(
                "utf-8"
            ),
        )
        missing_target = appcast_xml().replace(
            f"<sparkle:shortVersionString>{VERSION}</sparkle:shortVersionString>".encode(
                "utf-8"
            ),
            b"<sparkle:shortVersionString>0.8.6</sparkle:shortVersionString>",
        )
        fixtures = {
            "zero_matching_items": missing_target,
            "multiple_matching_items": multiple_targets,
            "malformed_xml": b"<rss><channel><item>",
            "duplicate_direct_release_notes_links": appcast_xml(duplicate_links),
        }

        for name, original_bytes in fixtures.items():
            with (
                self.subTest(name=name),
                tempfile.TemporaryDirectory() as temporary_directory,
            ):
                appcast_path = Path(temporary_directory) / "appcast.xml"
                _ = appcast_path.write_bytes(original_bytes)

                result = self.run_mutator(appcast_path)

                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(appcast_path.read_bytes(), original_bytes)


class SparkleAppcastShellContractTests(unittest.TestCase):
    def make_environment(
        self,
        root: Path,
        *,
        curl_mode: str = "success",
        curl_status: str = "200",
        curl_content_type: str = "Text/HTML; charset=utf-8",
        curl_body: str = "release notes",
        fail_mutator: bool = False,
    ) -> tuple[dict[str, str], dict[str, Path]]:
        fake_bin = root / "bin"
        fake_bin.mkdir()
        sparkle_bin = root / "sparkle"
        sparkle_bin.mkdir()
        temporary_body_directory = root / "temporary-bodies"
        temporary_body_directory.mkdir()
        curl_calls = root / "curl-calls.txt"
        generate_calls = root / "generate-calls.txt"
        python_calls = root / "python-calls.txt"
        build_directory = root / "build"
        build_directory.mkdir()
        _ = (build_directory / f"Voyager-{VERSION}.zip").write_bytes(b"zip")

        write_executable(
            fake_bin / "curl",
            """#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$CURL_CALLS"
if [[ "$CURL_MODE" == "transport" ]]; then
  exit 22
fi
if [[ "$CURL_MODE" == "timeout" ]]; then
  exit 28
fi
body_path=""
write_out=""
while (( $# )); do
  case "$1" in
    -o|--output)
      body_path="$2"
      shift 2
      ;;
    -w|--write-out)
      write_out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
if [[ -n "$body_path" ]]; then
  printf '%s' "$CURL_BODY" > "$body_path"
fi
write_out="${write_out//\\%\\{http_code\\}/$CURL_STATUS}"
write_out="${write_out//\\%\\{content_type\\}/$CURL_CONTENT_TYPE}"
printf '%b' "$write_out"
""",
        )
        write_executable(
            sparkle_bin / "generate_appcast",
            """#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$GENERATE_CALLS"
for work_directory in "$@"; do :; done
printf '%s' "$APPCAST_XML" > "$work_directory/appcast.xml"
""",
        )
        if fail_mutator:
            write_executable(
                fake_bin / "python3",
                """#!/usr/bin/env bash
set -eu
if [[ "$1" == "$MUTATOR_SCRIPT_PATH" ]]; then
  printf '%s\\n' "$*" >> "$PYTHON_CALLS"
  exit 97
fi
exec "$REAL_PYTHON" "$@"
""",
            )

        environment = os.environ | {
            "APPCAST_XML": appcast_xml().decode("utf-8"),
            "BUILD_DIR": str(build_directory),
            "CURL_BODY": curl_body,
            "CURL_CALLS": str(curl_calls),
            "CURL_CONTENT_TYPE": curl_content_type,
            "CURL_MODE": curl_mode,
            "CURL_STATUS": curl_status,
            "DOWNLOADS_BASE_URL": "https://downloads.example/releases/",
            "GENERATE_CALLS": str(generate_calls),
            "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
            "PYTHON_CALLS": str(python_calls),
            "REAL_PYTHON": sys.executable,
            "SPARKLE_BIN": str(sparkle_bin),
            "SPARKLE_PRIVATE_KEY": "test-private-key",
            "TMPDIR": str(temporary_body_directory),
            "VERSION": VERSION,
        }
        return environment, {
            "appcast": build_directory / "appcast.xml",
            "curl_calls": curl_calls,
            "generate_calls": generate_calls,
            "python_calls": python_calls,
            "temporary_body_directory": temporary_body_directory,
            "work_directory": build_directory / ".sparkle",
        }

    def run_appcast_script(
        self, environment: dict[str, str]
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(APPCAST_SCRIPT)],
            cwd=REPO_ROOT,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def calls(self, path: Path) -> list[str]:
        if not path.exists():
            return []
        return path.read_text(encoding="utf-8").splitlines()

    def test_gate_uses_the_canonical_release_notes_url_once_with_timeouts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            environment, paths = self.make_environment(Path(temporary_directory))

            result = self.run_appcast_script(environment)

            self.assertEqual(result.returncode, 0, result.stderr)
            curl_calls = self.calls(paths["curl_calls"])
            self.assertEqual(len(curl_calls), 1)
            self.assertIn(RELEASE_NOTES_URL, curl_calls[0])
            self.assertIn("--connect-timeout 10", curl_calls[0])
            self.assertIn("--max-time 30", curl_calls[0])
            self.assertEqual(list(paths["temporary_body_directory"].iterdir()), [])

    def test_gate_rejects_invalid_endpoints_before_generation_and_cleans_up(
        self,
    ) -> None:
        cases = {
            "transport_failure": {"curl_mode": "transport"},
            "request_timeout": {"curl_mode": "timeout"},
            "non_200_status": {"curl_status": "404"},
            "missing_content_type": {"curl_content_type": ""},
            "non_html_content_type": {"curl_content_type": "application/json"},
            "empty_body": {"curl_body": ""},
        }
        for name, options in cases.items():
            with (
                self.subTest(name=name),
                tempfile.TemporaryDirectory() as temporary_directory,
            ):
                environment, paths = self.make_environment(
                    Path(temporary_directory),
                    curl_mode=options.get("curl_mode", "success"),
                    curl_status=options.get("curl_status", "200"),
                    curl_content_type=options.get(
                        "curl_content_type", "Text/HTML; charset=utf-8"
                    ),
                    curl_body=options.get("curl_body", "release notes"),
                )

                result = self.run_appcast_script(environment)

                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(self.calls(paths["curl_calls"])), 1)
                self.assertEqual(self.calls(paths["generate_calls"]), [])
                self.assertFalse(paths["appcast"].exists())
                self.assertFalse(paths["work_directory"].exists())
                self.assertEqual(list(paths["temporary_body_directory"].iterdir()), [])

    def test_successful_generation_rewrites_then_mutates_the_temporary_appcast(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            environment, paths = self.make_environment(Path(temporary_directory))

            result = self.run_appcast_script(environment)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(self.calls(paths["curl_calls"])), 1)
            self.assertEqual(len(self.calls(paths["generate_calls"])), 1)
            root = element_tree.parse(paths["appcast"]).getroot()
            target_item = item_for_version(root, VERSION)
            managed_links = direct_release_notes(target_item)
            self.assertEqual(len(managed_links), 1)
            self.assertEqual(managed_links[0].text, RELEASE_NOTES_URL)
            self.assertEqual(managed_links[0].attrib, {})
            enclosure = target_item.find("enclosure")
            self.assertIsNotNone(enclosure)
            assert enclosure is not None
            self.assertEqual(
                enclosure.attrib["url"],
                "https://downloads.example/releases/releases/versions/0.8.4/Voyager-0.8.4.zip",
            )
            self.assertEqual(
                enclosure.attrib[f"{{{SPARKLE_NAMESPACE}}}edSignature"],
                "target-signature",
            )
            self.assertEqual(enclosure.attrib[f"{{{SPARKLE_NAMESPACE}}}version"], "804")
            self.assertFalse(paths["work_directory"].exists())
            self.assertEqual(list(paths["temporary_body_directory"].iterdir()), [])

    def test_failed_mutator_does_not_publish_a_partial_appcast(self) -> None:
        original_appcast = b"original appcast remains published\n"
        with tempfile.TemporaryDirectory() as temporary_directory:
            environment, paths = self.make_environment(
                Path(temporary_directory), fail_mutator=True
            )
            environment["MUTATOR_SCRIPT_PATH"] = str(MUTATOR_SCRIPT)
            _ = paths["appcast"].write_bytes(original_appcast)

            result = self.run_appcast_script(environment)

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(paths["appcast"].read_bytes(), original_appcast)
            self.assertEqual(len(self.calls(paths["curl_calls"])), 1)
            self.assertEqual(len(self.calls(paths["generate_calls"])), 1)
            self.assertEqual(len(self.calls(paths["python_calls"])), 1)
            self.assertFalse(paths["work_directory"].exists())


if __name__ == "__main__":
    _ = unittest.main()
