# Removal Procedure

> **Only follow this when the user explicitly requests CodeGraph removal.**

If the evaluation result is No-Go, or the user requests removal, follow these steps in order:

## Steps

1. **Delete the index:**

    ```
    mise run codegraph-clean
    ```

2. **Remove the MCP entry** from `opencode.json`:
   Delete the `codegraph` entry in the `mcpServers` section.

3. **Remove mise.toml tasks:**
   Delete the `codegraph-*` tasks from `mise.toml`.

4. **Remove the lefthook hook:**
   Delete the `codegraph` entry under `post-checkout` in `lefthook.yml`.

5. **Delete the skill directory:**

    ```
    rm -rf .agents/skills/codegraph-usage/
    ```

## Verification

After completing the steps above, verify no CodeGraph references remain:

```
rg -n "CodeGraph|codegraph" . --glob '!.codegraph' --glob '!node_modules'
```

Resolve any remaining matches before considering removal complete.

## Notes

- `opencode.json` is a user-managed local file — confirm with the user before modifying.
