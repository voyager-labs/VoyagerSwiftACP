# codegraph_files

Lists indexed files with optional filtering, grouping, and depth control.

## Parameters

| Name              | Type    | Required | Default         | Constraints                              |
| ----------------- | ------- | -------- | --------------- | ---------------------------------------- |
| `path`            | string  | No       | —               | Filter to files under this path prefix   |
| `pattern`         | string  | No       | —               | Glob-like pattern filter                 |
| `format`          | string  | No       | `tree`          | One of: `tree`, `flat`, `grouped`        |
| `includeMetadata` | boolean | No       | true            | Include language + symbol count per file |
| `maxDepth`        | number  | No       | —               | Clamped to 1–20                          |
| `projectPath`     | string  | No       | current project | Path to an initialized CodeGraph project |

## Return Shape

Depends on `format`:

**tree**: Indented directory tree with file entries showing language and symbol count.
**flat**: Simple list of all file paths.
**grouped**: Files grouped by language (Swift, Python, TypeScript, YAML, etc.).

## Behavior

- Lists all files in the CodeGraph index.
- `path` is normalized (strips `./`, leading `/`, Windows `\`) before matching.
- `pattern` uses custom glob-to-regex conversion for filtering.
- `format=tree`: Shows directory hierarchy.
- `format=flat`: Shows simple path list.
- `format=grouped`: Groups by detected language.
- `includeMetadata=true`: Each file shows language and symbol count.

## Edge Cases

- **No matching files**: Returns empty result for the given path/pattern.
- **All files**: Omit both `path` and `pattern` to list everything.
- **Path normalization**: `./src`, `/src`, `src` all treated equivalently.

## Voyager Examples

List all Swift files:

```
codegraph_files(format: "grouped", includeMetadata: true)
```

List files in a specific package:

```
codegraph_files(path: "apps/macos/Packages/VoyagerFeaturesComposer", format: "flat")
```

Count indexed files by language:

```
codegraph_files(format: "grouped", includeMetadata: false)
```

## Tips

- Use `format: "grouped"` to quickly see what languages are indexed.
- Use `path` filtering to scope to a specific package or directory.
- Combine with `codegraph_status` to understand index health before querying.
