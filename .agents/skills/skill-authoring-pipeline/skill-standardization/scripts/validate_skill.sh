#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  validate_skill.sh path/to/skill-directory
  validate_skill.sh --all path/to/skills-directory
USAGE
}

validate_one() {
  local skill_dir="$1"
  local skill_file="$skill_dir/SKILL.md"
  local errors=0
  local warnings=0

  echo "Validating: $skill_file"

  if [[ ! -f "$skill_file" ]]; then
    echo "[FAIL] SKILL.md missing"
    return 1
  fi

  local name
  name=$(awk '/^name:/ { sub(/^name:[[:space:]]*/, ""); gsub(/^"|"$/, ""); print; exit }' "$skill_file")
  if [[ -z "$name" ]]; then
    echo "[FAIL] required field: name missing"
    errors=$((errors + 1))
  elif [[ ! "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ || ${#name} -gt 64 ]]; then
    echo "[FAIL] name format invalid: $name"
    errors=$((errors + 1))
  else
    echo "[PASS] name format valid: $name"
  fi

  local dir_name
  dir_name=$(basename "$skill_dir")
  if [[ -n "$name" && "$name" != "$dir_name" ]]; then
    echo "[FAIL] name/directory mismatch: name='$name' dir='$dir_name'"
    errors=$((errors + 1))
  else
    echo "[PASS] name matches directory"
  fi

  local description
  description=$(awk '/^description:/ { sub(/^description:[[:space:]]*/, ""); gsub(/^"|"$/, ""); print; exit }' "$skill_file")
  if [[ -z "$description" ]]; then
    echo "[FAIL] required field: description missing or multiline unsupported by this quick validator"
    errors=$((errors + 1))
  elif [[ ${#description} -gt 1024 ]]; then
    echo "[FAIL] description too long: ${#description} chars"
    errors=$((errors + 1))
  else
    echo "[PASS] description length OK: ${#description} chars"
  fi

  if grep -q '^allowed-tools:[[:space:]]*\[' "$skill_file"; then
    echo "[WARN] allowed-tools should be space-delimited scalar, not YAML list"
    warnings=$((warnings + 1))
  fi

  local line_count
  line_count=$(wc -l < "$skill_file" | tr -d ' ')
  if [[ "$line_count" -gt 500 ]]; then
    echo "[WARN] SKILL.md is over 500 lines: $line_count"
    warnings=$((warnings + 1))
  else
    echo "[PASS] SKILL.md length OK: $line_count lines"
  fi

  if ! grep -Eq '^## (Instructions|Workflow|Process|Steps)' "$skill_file"; then
    echo "[WARN] recommended workflow/instructions section not found"
    warnings=$((warnings + 1))
  fi

  echo "Result: $errors error(s), $warnings warning(s)"
  [[ "$errors" -eq 0 ]]
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

if [[ "${1:-}" == "--all" ]]; then
  root="${2:-}"
  if [[ -z "$root" || ! -d "$root" ]]; then
    usage
    exit 2
  fi
  status=0
  for dir in "$root"/*; do
    [[ -d "$dir" ]] || continue
    validate_one "$dir" || status=1
    echo
  done
  exit "$status"
fi

validate_one "$1"
