import tempfile
import unittest
from pathlib import Path

from scripts.run_shadow_corpus import evaluate_version


class ShadowCorpusTests(unittest.TestCase):
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
