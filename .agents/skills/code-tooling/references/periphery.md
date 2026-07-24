# Periphery — Unused Code Detection

Periphery scans the project to find declarations that are never used: functions, types, properties, protocols, and more.

## When to Use

- Detect unused functions, types, properties, protocols
- Clean up dead code before releases
- Verify that newly added code is actually referenced
- Audit codebase health

## CLI Usage

Periphery is installed via mise. All commands use `mise exec --` prefix.

```bash
# Full project scan
mise exec -- periphery scan

# Scan specific targets only
mise exec -- periphery scan --targets Voyager

# Scan with specific schemes
mise exec -- periphery scan --schemes Voyager-Dev

# JSON output for programmatic processing
mise exec -- periphery scan --format json
```

## Configuration

Project configuration is in `.periphery.yml` at the repo root:

```yaml
# .periphery.yml
project: apps/macos/Voyager/Voyager.xcodeproj
schemes:
    - Voyager-Dev
    - Voyager-Prod
targets:
    - Voyager
    - VoyagerHelper
```

## Workflow Patterns

### Pattern: Pre-release cleanup

```bash
1. mise exec -- periphery scan > periphery-results.txt
2. Review results, categorize by severity
3. Remove confirmed unused code
4. mise run macos-build  # verify nothing breaks
5. mise run macos-test   # verify tests still pass
```

### Pattern: Verify new code is referenced

```bash
1. After adding new types/functions
2. mise exec -- periphery scan --targets <target>
3. Check if new declarations appear as unused
4. Add references or remove dead declarations
```

## Tips

- Periphery builds the project internally, so it requires a valid Xcode project setup
- Scan time depends on project size — use `--targets` to scope down
- Results may include false positives for runtime-referenced code (reflection, SwiftUI previews)
- Run periodically, not on every commit

## Relationship to Other Tools

- Use **CodeGraph** `codegraph_explore` to understand callers and impact before removing code Periphery flags
- Use the repository's `mise run macos-build` and `mise run macos-test` tasks after removing unused code
