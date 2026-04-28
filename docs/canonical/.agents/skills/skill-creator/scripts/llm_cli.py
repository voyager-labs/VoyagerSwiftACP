#!/usr/bin/env python3
"""Helpers for calling Claude/Codex CLIs with shared fallback behavior."""

import os
import shutil
import subprocess
import tempfile
from pathlib import Path


def claude_env() -> dict[str, str]:
    """Remove the nested-Claude guard env var for subprocess CLI usage."""
    return {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}


def codex_model_arg(model: str | None) -> list[str]:
    """Return a Codex-compatible model flag when the requested model looks safe.

    These scripts historically accepted Claude model names. Passing those
    straight through to Codex would fail, so only forward model names that
    already resemble OpenAI/Codex identifiers.
    """
    if not model:
        return []

    lowered = model.lower()
    codex_like_prefixes = (
        "gpt-",
        "o1",
        "o3",
        "o4",
        "codex",
    )
    if lowered.startswith(codex_like_prefixes):
        return ["--model", model]
    return []


def call_claude_text(prompt: str, model: str | None, timeout: int = 300) -> str:
    """Run `claude -p` with the prompt on stdin and return the text response."""
    cmd = ["claude", "-p", "--output-format", "text"]
    if model:
        cmd.extend(["--model", model])

    result = subprocess.run(
        cmd,
        input=prompt,
        capture_output=True,
        text=True,
        env=claude_env(),
        timeout=timeout,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"claude -p exited {result.returncode}\nstderr: {result.stderr}"
        )
    return result.stdout


def call_codex_text(
    prompt: str,
    model: str | None,
    timeout: int = 300,
    cwd: str | Path | None = None,
) -> str:
    """Run `codex exec` with the prompt on stdin and return the last message."""
    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".txt",
        prefix="codex-llm-cli-",
        delete=False,
    ) as output_file:
        output_path = Path(output_file.name)

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

    try:
        result = subprocess.run(
            cmd,
            input=prompt,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=cwd,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"codex exec exited {result.returncode}\n"
                f"stdout: {result.stdout}\n"
                f"stderr: {result.stderr}"
            )
        if not output_path.exists():
            raise RuntimeError("codex exec did not write an output message file")
        return output_path.read_text().strip()
    finally:
        output_path.unlink(missing_ok=True)


def call_text_with_fallback(
    prompt: str,
    model: str | None,
    timeout: int = 300,
    cwd: str | Path | None = None,
) -> str:
    """Call Claude first, then fall back to Codex if needed."""
    errors: list[str] = []

    if shutil.which("claude"):
        try:
            return call_claude_text(prompt, model, timeout=timeout)
        except Exception as exc:
            errors.append(f"claude failed: {exc}")
    else:
        errors.append("claude failed: executable not found")

    if shutil.which("codex"):
        try:
            return call_codex_text(prompt, model, timeout=timeout, cwd=cwd)
        except Exception as exc:
            errors.append(f"codex failed: {exc}")
    else:
        errors.append("codex failed: executable not found")

    raise RuntimeError("No supported LLM CLI succeeded:\n" + "\n".join(errors))
