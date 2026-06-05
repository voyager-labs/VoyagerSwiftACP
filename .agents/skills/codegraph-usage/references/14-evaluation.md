# Evaluation Framework (Go/No-Go)

## Contents

- [Evaluation Angles](#evaluation-angles)
- [Go/No-Go Criteria](#go-no-go-criteria)
- [Measurement Record Template](#measurement-record-template)
- [If No-Go](#if-no-go)

A structured framework for deciding whether CodeGraph provides enough value to keep as a permanent part of the Voyager development toolchain. Run this evaluation after at least 2 weeks of real usage across multiple development tasks.

## Evaluation Angles

Seven angles to measure. Each angle has a target threshold and a verdict category.

### 1. Exploration Speed

**Target:** 30%+ time reduction for understanding new modules.

**How to measure:** Pick 3 modules you have not worked on before. Time yourself (or the agent) understanding the module structure with CodeGraph vs. without (using grep, file reading, LSP alone). Compare the total tool calls and wall-clock time.

### 2. Call Flow Accuracy

**Target:** 80%+ accuracy on known TCA reducer call paths.

**How to measure:** Select 5 TCA reducer call chains you already know from prior work. Run `codegraph_callers` and `codegraph_trace` on each. Count how many return the correct full call chain. Accuracy = correct results / total queries.

### 3. Impact Analysis Coverage

**Target:** 0 misses vs. `macos_checks`, under 20% over-inclusion.

**How to measure:** Run `codegraph_impact` on 5 recently changed symbols. Compare the affected symbol list against what `macos_checks.py` reports as affected targets. Count misses (symbols in checks but not in CodeGraph) and over-inclusions (symbols in CodeGraph but not in checks).

### 4. Cross-Language Tracing

**Target:** 50%+ success on Swift-to-Python boundary queries.

**How to measure:** Pick 5 known Swift-to-Python API call paths (frontend service → backend route). Run `codegraph_trace` on each. Count how many correctly trace across the language boundary. Cross-language tracing relies on URL path string matching, so partial matches (correct path, wrong hop count) still count as success.

### 5. Agent Workflow Improvement

**Target:** 40%+ reduction in exploration tool calls.

**How to measure:** Compare the number of exploration tool calls (grep, read, glob, LSP find-references) in agent sessions with CodeGraph available vs. sessions without. Measure across at least 5 comparable tasks.

### 6. Maintenance Cost

**Target:** Cost must not exceed benefit.

**How to measure:** Track time spent on:

- Index corruption incidents and re-indexing.
- MCP server crashes or connection issues.
- Updating CodeGraph configuration when the repo structure changes.
- Keeping the lefthook post-checkout hook working.

If maintenance time exceeds the time saved by having CodeGraph, this is a failed angle.

### 7. Token Savings

**Target:** 50%+ token reduction for exploration tasks.

**How to measure:** Compare the total token count for exploration phases of agent sessions with and without CodeGraph. The hypothesis is that a single `codegraph_callers` or `codegraph_trace` call replaces multiple grep/read/glob cycles, reducing both input and output tokens.

## Go/No-Go Criteria

### Go (Keep CodeGraph)

- 4 or more angles rated **Improved**.
- Maintenance cost is acceptable (does not dominate the benefit).
- No conflicts with existing tools (SourceKit-LSP, macos_checks, build systems).

### No-Go (Remove CodeGraph)

- 3 or fewer angles rated **Improved**.
- Maintenance cost exceeds the benefit.
- Conflicts detected with existing tooling (e.g., CodeGraph results mislead agents into skipping real verification).

## Measurement Record Template

Copy this template for each angle you evaluate. Fill in the measured values, calculate the improvement rate, and record the verdict.

```
### [Angle Name] -- [Measurement Date]

- Before: [measured value]
- After: [measured value]
- Improvement rate: [X%]
- Verdict: [Improved / No change / Degraded]
- Notes: [additional observations, edge cases, anomalies]
```

### Example Filled Record

```
### Exploration Speed -- 2025-06-15

- Before: 12 tool calls, 8 minutes to understand ComposerSaveReducer module
- After: 4 tool calls, 3 minutes with codegraph_explore + codegraph_context
- Improvement rate: 62.5% reduction in tool calls, 62.5% reduction in time
- Verdict: Improved
- Notes: Most of the savings came from not needing to read 5 separate files to find the module entry points.
```

## If No-Go

Follow the removal procedure in `references/15-removal.md`.
