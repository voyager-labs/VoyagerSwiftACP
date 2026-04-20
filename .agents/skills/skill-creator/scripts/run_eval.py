#!/usr/bin/env python3
"""Run trigger evaluation for a skill description.

Tests whether a skill's description causes Claude or Codex to trigger
(read the skill) for a set of queries. Outputs results as JSON.
"""

import argparse
import json
import os
import re
import select
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

from scripts.llm_cli import claude_env, codex_model_arg
from scripts.utils import parse_skill_md


def find_project_root() -> Path:
    """Find the project root by walking up from cwd looking for CLI config dirs."""
    current = Path.cwd()
    for parent in [current, *current.parents]:
        if (parent / ".claude").is_dir() or (parent / ".codex").is_dir():
            return parent
    return current


def _make_eval_skill_id(skill_name: str, unique_id: str) -> str:
    """Return a filesystem-safe temporary skill identifier."""
    slug = re.sub(r"[^a-zA-Z0-9_-]+", "-", skill_name).strip("-").lower()
    if not slug:
        slug = "skill"
    return f"{slug}-skill-{unique_id}"


def _pick_codex_skills_dir(project_root: str) -> Path:
    """Choose a writable Codex skills directory for temporary eval skills."""
    candidates: list[Path] = []
    codex_home = os.environ.get("CODEX_HOME")
    if codex_home:
        candidates.append(Path(codex_home) / "skills")
    candidates.append(Path(project_root) / ".codex" / "skills")
    candidates.append(Path.home() / ".codex" / "skills")

    errors: list[str] = []
    for candidate in candidates:
        try:
            candidate.mkdir(parents=True, exist_ok=True)
            probe = candidate / f".eval-write-probe-{uuid.uuid4().hex[:8]}"
            probe.mkdir()
            probe.rmdir()
            return candidate
        except OSError as exc:
            errors.append(f"{candidate}: {exc}")

    raise RuntimeError(
        "Could not find a writable Codex skills directory:\n" + "\n".join(errors)
    )


def _run_single_query_claude(
    query: str,
    skill_name: str,
    skill_description: str,
    timeout: int,
    project_root: str,
    model: str | None,
) -> bool:
    """Run a single trigger query through Claude and detect skill usage."""
    unique_id = uuid.uuid4().hex[:8]
    clean_name = _make_eval_skill_id(skill_name, unique_id)
    project_commands_dir = Path(project_root) / ".claude" / "commands"
    command_file = project_commands_dir / f"{clean_name}.md"

    try:
        project_commands_dir.mkdir(parents=True, exist_ok=True)
        indented_desc = "\n  ".join(skill_description.split("\n"))
        command_content = (
            f"---\n"
            f"description: |\n"
            f"  {indented_desc}\n"
            f"---\n\n"
            f"# {skill_name}\n\n"
            f"This skill handles: {skill_description}\n"
        )
        command_file.write_text(command_content)

        cmd = [
            "claude",
            "-p", query,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
        ]
        if model:
            cmd.extend(["--model", model])

        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=project_root,
            env=claude_env(),
        )

        triggered = False
        start_time = time.time()
        buffer = ""
        pending_tool_name = None
        accumulated_json = ""

        try:
            while time.time() - start_time < timeout:
                if process.poll() is not None:
                    remaining = process.stdout.read()
                    if remaining:
                        buffer += remaining.decode("utf-8", errors="replace")
                    break

                ready, _, _ = select.select([process.stdout], [], [], 1.0)
                if not ready:
                    continue

                chunk = os.read(process.stdout.fileno(), 8192)
                if not chunk:
                    break
                buffer += chunk.decode("utf-8", errors="replace")

                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()
                    if not line:
                        continue

                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    if event.get("type") == "stream_event":
                        se = event.get("event", {})
                        se_type = se.get("type", "")

                        if se_type == "content_block_start":
                            cb = se.get("content_block", {})
                            if cb.get("type") == "tool_use":
                                tool_name = cb.get("name", "")
                                if tool_name in ("Skill", "Read"):
                                    pending_tool_name = tool_name
                                    accumulated_json = ""
                                else:
                                    return False

                        elif se_type == "content_block_delta" and pending_tool_name:
                            delta = se.get("delta", {})
                            if delta.get("type") == "input_json_delta":
                                accumulated_json += delta.get("partial_json", "")
                                if clean_name in accumulated_json:
                                    return True

                        elif se_type in ("content_block_stop", "message_stop"):
                            if pending_tool_name:
                                return clean_name in accumulated_json
                            if se_type == "message_stop":
                                return False

                    elif event.get("type") == "assistant":
                        message = event.get("message", {})
                        for content_item in message.get("content", []):
                            if content_item.get("type") != "tool_use":
                                continue
                            tool_name = content_item.get("name", "")
                            tool_input = content_item.get("input", {})
                            if tool_name == "Skill" and clean_name in tool_input.get("skill", ""):
                                triggered = True
                            elif tool_name == "Read" and clean_name in tool_input.get("file_path", ""):
                                triggered = True
                            return triggered

                    elif event.get("type") == "result":
                        return triggered

            process.wait(timeout=1)
            if process.returncode not in (0, None):
                stderr = process.stderr.read().decode("utf-8", errors="replace")
                raise RuntimeError(
                    f"claude -p exited {process.returncode}\nstderr: {stderr}"
                )
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

        return triggered
    finally:
        if command_file.exists():
            command_file.unlink()


def _run_single_query_codex(
    query: str,
    skill_name: str,
    skill_description: str,
    timeout: int,
    project_root: str,
    model: str | None,
) -> bool:
    """Run a single trigger query through Codex and detect skill usage."""
    unique_id = uuid.uuid4().hex[:8]
    clean_name = _make_eval_skill_id(skill_name, unique_id)
    trigger_marker = f"__TRIGGERED_{unique_id.upper()}__"
    skill_dir = _pick_codex_skills_dir(project_root) / clean_name
    skill_file = skill_dir / "SKILL.md"

    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".txt",
        prefix="codex-run-eval-",
        delete=False,
    ) as output_file:
        output_path = Path(output_file.name)

    try:
        skill_dir.mkdir(parents=True, exist_ok=True)
        indented_desc = "\n  ".join(skill_description.split("\n"))
        skill_content = (
            f"---\n"
            f"name: {clean_name}\n"
            f"description: |\n"
            f"  {indented_desc}\n"
            f"---\n\n"
            f"# {skill_name}\n\n"
            f"If you are reading this skill because it was selected for the current request, "
            f"include the exact token `{trigger_marker}` once in the first line of your final "
            f"response. If this skill is not selected, never mention that token.\n\n"
            f"This skill handles: {skill_description}\n"
        )
        skill_file.write_text(skill_content)

        cmd = [
            "codex",
            "exec",
            "-",
            "--ephemeral",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "--color",
            "never",
            "--output-last-message",
            str(output_path),
            *codex_model_arg(model),
        ]

        result = subprocess.run(
            cmd,
            input=query,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=project_root,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"codex exec exited {result.returncode}\n"
                f"stdout: {result.stdout}\n"
                f"stderr: {result.stderr}"
            )
        if not output_path.exists():
            raise RuntimeError("codex exec did not write an output message file")

        return trigger_marker in output_path.read_text()
    finally:
        output_path.unlink(missing_ok=True)
        shutil.rmtree(skill_dir, ignore_errors=True)


def run_single_query(
    query: str,
    skill_name: str,
    skill_description: str,
    timeout: int,
    project_root: str,
    model: str | None = None,
) -> bool:
    """Run a single query and return whether the skill was triggered."""
    errors: list[str] = []

    if shutil.which("claude"):
        try:
            return _run_single_query_claude(
                query,
                skill_name,
                skill_description,
                timeout,
                project_root,
                model,
            )
        except Exception as exc:
            errors.append(f"claude failed: {exc}")
    else:
        errors.append("claude failed: executable not found")

    if shutil.which("codex"):
        try:
            return _run_single_query_codex(
                query,
                skill_name,
                skill_description,
                timeout,
                project_root,
                model,
            )
        except Exception as exc:
            errors.append(f"codex failed: {exc}")
    else:
        errors.append("codex failed: executable not found")

    raise RuntimeError("No supported LLM CLI succeeded:\n" + "\n".join(errors))


def run_eval(
    eval_set: list[dict],
    skill_name: str,
    description: str,
    num_workers: int,
    timeout: int,
    project_root: Path,
    runs_per_query: int = 1,
    trigger_threshold: float = 0.5,
    model: str | None = None,
) -> dict:
    """Run the full eval set and return results."""
    results = []
    query_triggers: dict[str, list[bool]] = {}
    query_items: dict[str, dict] = {}

    def record_result(item: dict, triggered: bool):
        query = item["query"]
        query_items[query] = item
        if query not in query_triggers:
            query_triggers[query] = []
        query_triggers[query].append(triggered)

    def execute_sequential():
        for item in eval_set:
            for _ in range(runs_per_query):
                try:
                    triggered = run_single_query(
                        item["query"],
                        skill_name,
                        description,
                        timeout,
                        str(project_root),
                        model,
                    )
                except Exception as e:
                    print(f"Warning: query failed: {e}", file=sys.stderr)
                    triggered = False
                record_result(item, triggered)

    if num_workers <= 1:
        execute_sequential()
    else:
        try:
            with ProcessPoolExecutor(max_workers=num_workers) as executor:
                future_to_info = {}
                for item in eval_set:
                    for run_idx in range(runs_per_query):
                        future = executor.submit(
                            run_single_query,
                            item["query"],
                            skill_name,
                            description,
                            timeout,
                            str(project_root),
                            model,
                        )
                        future_to_info[future] = (item, run_idx)

                for future in as_completed(future_to_info):
                    item, _ = future_to_info[future]
                    try:
                        triggered = future.result()
                    except Exception as e:
                        print(f"Warning: query failed: {e}", file=sys.stderr)
                        triggered = False
                    record_result(item, triggered)
        except (OSError, PermissionError) as e:
            print(
                f"Warning: parallel eval unavailable, falling back to sequential execution: {e}",
                file=sys.stderr,
            )
            execute_sequential()

    for query, triggers in query_triggers.items():
        item = query_items[query]
        trigger_rate = sum(triggers) / len(triggers)
        should_trigger = item["should_trigger"]
        if should_trigger:
            did_pass = trigger_rate >= trigger_threshold
        else:
            did_pass = trigger_rate < trigger_threshold
        results.append({
            "query": query,
            "should_trigger": should_trigger,
            "trigger_rate": trigger_rate,
            "triggers": sum(triggers),
            "runs": len(triggers),
            "pass": did_pass,
        })

    passed = sum(1 for r in results if r["pass"])
    total = len(results)

    return {
        "skill_name": skill_name,
        "description": description,
        "results": results,
        "summary": {
            "total": total,
            "passed": passed,
            "failed": total - passed,
        },
    }


def main():
    parser = argparse.ArgumentParser(description="Run trigger evaluation for a skill description")
    parser.add_argument("--eval-set", required=True, help="Path to eval set JSON file")
    parser.add_argument("--skill-path", required=True, help="Path to skill directory")
    parser.add_argument("--description", default=None, help="Override description to test")
    parser.add_argument("--num-workers", type=int, default=10, help="Number of parallel workers")
    parser.add_argument("--timeout", type=int, default=30, help="Timeout per query in seconds")
    parser.add_argument("--runs-per-query", type=int, default=3, help="Number of runs per query")
    parser.add_argument("--trigger-threshold", type=float, default=0.5, help="Trigger rate threshold")
    parser.add_argument("--model", default=None, help="Model to use for Claude/Codex when compatible")
    parser.add_argument("--verbose", action="store_true", help="Print progress to stderr")
    args = parser.parse_args()

    eval_set = json.loads(Path(args.eval_set).read_text())
    skill_path = Path(args.skill_path)

    if not (skill_path / "SKILL.md").exists():
        print(f"Error: No SKILL.md found at {skill_path}", file=sys.stderr)
        sys.exit(1)

    name, original_description, content = parse_skill_md(skill_path)
    description = args.description or original_description
    project_root = find_project_root()

    if args.verbose:
        print(f"Evaluating: {description}", file=sys.stderr)

    output = run_eval(
        eval_set=eval_set,
        skill_name=name,
        description=description,
        num_workers=args.num_workers,
        timeout=args.timeout,
        project_root=project_root,
        runs_per_query=args.runs_per_query,
        trigger_threshold=args.trigger_threshold,
        model=args.model,
    )

    if args.verbose:
        summary = output["summary"]
        print(f"Results: {summary['passed']}/{summary['total']} passed", file=sys.stderr)
        for r in output["results"]:
            status = "PASS" if r["pass"] else "FAIL"
            rate_str = f"{r['triggers']}/{r['runs']}"
            print(f"  [{status}] rate={rate_str} expected={r['should_trigger']}: {r['query'][:70]}", file=sys.stderr)

    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
