# codegraph_status

Returns index health, statistics, and sync status.

## Parameters

| Name          | Type   | Required | Default         | Constraints                              |
| ------------- | ------ | -------- | --------------- | ---------------------------------------- |
| `projectPath` | string | No       | current project | Path to an initialized CodeGraph project |

## Return Shape

```
## CodeGraph Status

- Files indexed: N
- Total nodes: N
- Total edges: N
- DB size: N MB
- Backend: sqlite
- Journal mode: wal

### Nodes by kind
- function: N
- method: N
- class: N
...

### Languages
- swift: N files
- python: N files
...

### Pending sync:
- filePath (modified)
- filePath (deleted)
```

## Behavior

- Returns comprehensive index statistics.
- Shows node/edge counts, database size, and storage backend.
- Breaks down nodes by kind (function, method, class, etc.).
- Breaks down files by language.
- Lists files pending sync (modified/deleted since last index).
- Emits its own worktree mismatch warning (not via the auto-banner system).

## Edge Cases

- **Stale index**: If many files are pending sync, the index may return outdated results. Run `mise run codegraph-reindex`.
- **Worktree mismatch**: If the MCP server is running from a different worktree than expected, a warning is shown.
- **No index**: Returns an error if `.codegraph/` doesn't exist.

## Voyager Examples

Check index health:

```
codegraph_status()
```

## Tips

- Run this first in any session that uses CodeGraph — verifies the index exists and is current.
- If "Pending sync" shows many files, the index is stale. Run `mise run codegraph-reindex` or wait for the file watcher to catch up.
- Use before and after `codegraph-reindex` to verify the reindex worked.
