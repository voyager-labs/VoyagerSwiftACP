import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from scripts.run_shadow_corpus import evaluate_version


ROOT = Path(__file__).resolve().parents[2]


class ShadowCorpusTests(unittest.TestCase):
    def test_checked_in_corpus_is_complete_and_runnable(self) -> None:
        corpus_path = ROOT / "scripts/evals/shadow-corpus.json"
        corpus = json.loads(corpus_path.read_text(encoding="utf-8"))
        cases = corpus["cases"]

        self.assertNotEqual(corpus["fixed_settings"]["baseline_ref"], "HEAD")
        baseline = subprocess.run(
            [
                "git",
                "cat-file",
                "-e",
                f"{corpus['fixed_settings']['baseline_ref']}^{{commit}}",
            ],
            cwd=ROOT,
            check=False,
        )
        self.assertEqual(baseline.returncode, 0)
        self.assertEqual(
            {case["id"] for case in cases},
            {f"E{number:02d}" for number in range(1, 19)},
        )
        for case in cases:
            for signal in ("constraints", "tool_choice", "stop_or_escalation"):
                self.assertTrue(case["rubric"][signal], f"{case['id']} {signal}")

        with tempfile.TemporaryDirectory() as directory:
            output_path = Path(directory) / "shadow.json"
            completed = subprocess.run(
                [
                    sys.executable,
                    "scripts/run_shadow_corpus.py",
                    "--output",
                    str(output_path),
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            evidence = json.loads(output_path.read_text(encoding="utf-8"))

        self.assertTrue(
            any(
                result["source_snapshots"]["v1"] != result["source_snapshots"]["v2"]
                for result in evidence["results"]
            )
        )

    def test_required_content_absence_fails_the_matching_signal(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "owners" / "contract.md"
            path.parent.mkdir()
            path.write_text(
                "explicit user request\ncommit requires explicit user request\n"
            )
            case = {
                "rubric": {
                    "constraints": [
                        {
                            "path": "owners/contract.md",
                            "contains": "explicit user request",
                        }
                    ],
                    "tool_choice": [
                        {"path": "owners/contract.md", "path_exists": True}
                    ],
                    "stop_or_escalation": [
                        {
                            "path": "owners/contract.md",
                            "contains": "commit requires explicit user request",
                        }
                    ],
                }
            }

            passing = evaluate_version(root, case, "v2", "HEAD", [])
            failing = evaluate_version(
                root,
                case,
                "v2",
                "HEAD",
                [
                    {
                        "path": "owners/contract.md",
                        "operation": "replace",
                        "from": "explicit user request",
                        "to": "",
                        "count": 2,
                    }
                ],
            )

            self.assertTrue(passing["pass"])
            self.assertFalse(failing["pass"])
            self.assertFalse(failing["signals"]["constraints"]["pass"])
            self.assertFalse(failing["signals"]["stop_or_escalation"]["pass"])


if __name__ == "__main__":
    unittest.main()
