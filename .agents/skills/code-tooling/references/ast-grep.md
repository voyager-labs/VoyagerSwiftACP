# ast-grep — AST-Based Code Search & Rewrite

ast-grep performs AST-aware pattern matching and replacement. Unlike text grep, it understands code structure — matching `func $NAME($$$)` finds function declarations regardless of formatting, whitespace, or parameter count.

## When to Use

- Search for code patterns (function declarations, class definitions, API usage)
- Batch rewrite code across files (rename, migrate patterns)
- Validate code structure (enforce conventions, find anti-patterns)
- Fallback when CodeGraph can't find a pattern (e.g., TCA composition syntax, string literals)

## Meta-Variables

| Variable | Matches            | Example                                                     |
| -------- | ------------------ | ----------------------------------------------------------- |
| `$NAME`  | Single AST node    | `func $NAME()` matches `func hello()` — `$NAME` = `hello`   |
| `$$$`    | Zero or more nodes | `func $NAME($$$)` matches any function regardless of params |

## MCP Tools

### Pattern Search

```yaml
# Basic pattern search
ast_grep_search(pattern: "func $NAME($$$)", lang: "swift")

# Search with file path filter
ast_grep_search(pattern: "@Reducer\nstruct $NAME", lang: "swift", paths: ["apps/macos"])

# Search with glob filter
ast_grep_search(pattern: "func $NAME($$$)", lang: "swift", globs: ["**/Reducer/*.swift"])

# Search with context lines around matches
ast_grep_search(pattern: "func $NAME($$$)", lang: "swift", context: 3)

# Search across project (CLI-like)
ast-grep_find_code(project_folder: "/path/to/project", pattern: "@Reducer")
```

### Pattern Replace

```yaml
# Dry-run replace (default) — previews changes without applying
ast_grep_replace(
  pattern: "print($MSG)",
  rewrite: 'Logger.debug($MSG)',
  lang: "swift",
  dryRun: true
)

# Apply replace scoped to specific paths
ast_grep_replace(
  pattern: "print($MSG)",
  rewrite: 'Logger.debug($MSG)',
  lang: "swift",
  paths: ["apps/macos"],
  dryRun: false
)

# Apply replace with glob filter
ast_grep_replace(
  pattern: "oldAPI($$$)",
  rewrite: "newAPI($$$)",
  lang: "swift",
  globs: ["**/Api/*.swift"],
  dryRun: false
)
```

### YAML Rule-Based Search

For complex conditions (inside/has, multiple patterns):

```yaml
ast-grep_find_code_by_rule(yaml: "id: x\nlanguage: swift\nrule: {pattern: '@Reducer\nstruct $NAME', has: {pattern: 'Scope'}}")
```

### Test Rule

Test a YAML rule against sample code before running it project-wide:

```yaml
# Test a rule against sample code
ast-grep_test_match_code_rule(
  code: "let x: String! = nil",
  yaml: "id: no-implicit-unwrap\nlanguage: swift\nrule: {pattern: '$TYPE!'}"
)
```

Use this to verify rule syntax and match behavior before using `find_code_by_rule`.

### Debug Pattern Structure

```yaml
# Inspect how ast-grep parses your code
ast-grep_dump_syntax_tree(code: "let x = 5", language: "swift", format: "pattern")
```

## Pattern Examples (Swift/TCA)

This project uses TCA 1.0+ with the `@Reducer` macro. Reducers are declared as `@Reducer struct` not `struct: Reducer`.

```yaml
# Find all TCA reducers (@Reducer macro — this project's pattern)
ast_grep_search(pattern: "@Reducer\nstruct $NAME", lang: "swift")

# Find all TCA reducers (multi-line match)
ast_grep_search(pattern: "@Reducer
struct $NAME {", lang: "swift")

# Find TCA Scope usage
ast_grep_search(pattern: "Scope(state: \\.$STATE, action: \\.$ACTION) { $$$ }", lang: "swift")

# Find .copy() calls (potential mutation points)
ast_grep_search(pattern: "$EXPR.copy()", lang: "swift")

# Find all @Dependency property wrappers
ast_grep_search(pattern: "@Dependency(\\.$NAME) var $VAR", lang: "swift")

# Find print() debugging statements
ast_grep_search(pattern: "print($$$)", lang: "swift")

# Find Effect<Action> return types
ast_grep_search(pattern: "Effect<$ACTION>", lang: "swift")

# Find Reduce closures
ast_grep_search(pattern: "Reduce { $STATE, $ACTION in $$$ }", lang: "swift")

# Find .forEach composition
ast_grep_search(pattern: ".forEach(\\.$KEY, action: \\.$ACTION) { $$$ }", lang: "swift")

# Find ifLet composition
ast_grep_search(pattern: ".ifLet(\\.$STATE, action: \\.$ACTION) { $$$ }", lang: "swift")
```

## Relational Rules

ast-grep supports relational rules (`inside`, `has`, `not`, `follows`) for complex queries. When using relational rules, add `stopBy: end` to ensure complete traversal:

```yaml
# Find @Reducer structs that contain Scope usage
ast-grep_find_code_by_rule(yaml: "id: scoped-reducers\nlanguage: swift\nrule:\n  pattern: '@Reducer\nstruct $NAME'\n  has:\n    pattern: 'Scope'\n    stopBy: end")
```

## Custom Rules

Project-specific rules live in `ast-grep-rules/` (configured in `sgconfig.yml`).

Rule file format:

```yaml
# ast-grep-rules/no-force-unwrap.yaml
id: no-force-unwrap
language: swift
rule:
    pattern: $EXPR!
message: "Avoid force unwrap — use guard let or if let instead"
severity: warning
```

## Workflow Patterns

### Pattern: Batch migrate API usage

```yaml
1. ast_grep_search(pattern: "oldAPI($$$)", lang: "swift")  # find all usages
2. ast_grep_replace(pattern: "oldAPI($$$)", rewrite: "newAPI($$$)", ...)  # dry-run
3. Review dry-run output
4. ast_grep_replace(..., dryRun: false)  # apply
5. XcodeBuildMCP_build_sim()  # verify compilation
```

### Pattern: Code audit / convention check

```yaml
1. Write YAML rules in ast-grep-rules/
2. ast-grep_find_code_by_rule(yaml: "id: x\nlanguage: swift\nrule: ...")
3. Review matches and fix violations
```

## Limitations

- Patterns must be valid AST nodes — cannot match arbitrary text
- Use `ast-grep_dump_syntax_tree` when a pattern doesn't match as expected
- For simple string search, use `grep` tool instead

## Relationship to Other Tools

- Use **CodeGraph** first for symbol-level queries (definitions, references)
- Use ast-grep when CodeGraph can't match structural patterns
- Use **XcodeBuildMCP** to verify ast-grep rewrites compile correctly
