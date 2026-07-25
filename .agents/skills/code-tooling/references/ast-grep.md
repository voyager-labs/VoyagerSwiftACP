# ast-grep — OMO Skill and `sg` CLI

OMO no longer exposes ast-grep as an MCP server. It provisions the native `sg` binary and ships the `ast-grep` skill, including a Python helper for validation, search, rewrite, and rule scans.

## Agent workflow

1. Load the `ast-grep` skill.
2. Use the base directory returned by the skill loader for its helper script.
3. Validate and search before rewriting.
4. Dry-run every rewrite before applying it.

```bash
# Search through the OMO skill helper
python3 <ast-grep-skill-base>/scripts/ast_grep_helper.py \
  search 'print($$$)' --lang swift apps/macos

# Dry-run rewrite
python3 <ast-grep-skill-base>/scripts/ast_grep_helper.py \
  replace 'print($MSG)' 'Logger.debug($MSG)' --lang swift apps/macos

# Apply only after reviewing the dry-run
python3 <ast-grep-skill-base>/scripts/ast_grep_helper.py \
  replace 'print($MSG)' 'Logger.debug($MSG)' --lang swift apps/macos --apply
```

Direct `sg` is appropriate when the helper does not expose a required option:

```bash
sg run -p 'func $NAME($$$) { $$$ }' --lang swift apps/macos
sg scan -r .ast-grep/rules/model/no-model-body-swiftui-view.yaml apps/macos
```

## Pattern rules

- Patterns are valid code, not regex.
- `$VAR` matches one AST node; `$$$` matches zero or more nodes.
- Single-quote shell patterns so `$VAR` is not expanded.
- Use `sg scan` and YAML rules for reusable or relational checks.
- Use text grep for comments, string contents, filenames, or regex-shaped searches.

## Project CI boundary

Voyager pins ast-grep in `mise.toml` for deterministic Lefthook and CI scans. That installation is intentionally separate from OMO's agent runtime provisioning. Do not replace the Lefthook command with an OMO cache path.

## Verification

After a rewrite, run the owning formatter/linter and the smallest relevant build or test. ast-grep proves structural matching, not compiler correctness.
