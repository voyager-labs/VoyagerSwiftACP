# Native Evidence Contract

Read this reference only for a native-parity claim.

## Evidence classes

| Class | Meaning | Allowed conclusion |
| --- | --- | --- |
| Source fact | Direct native declaration with path and line range | State what source declares, not final rendering |
| Semantic inference | Reasoned role interpretation from sources | Propose a token role with confidence |
| Runtime unknown | Rendering depends on environment or unresolved input | Name the fixture or capture required |
| Native fixture observation | Repeatable named capture with OS, appearance, size, data, and interaction metadata | Compare rendered behavior with qualified confidence |

Use high confidence for direct source or repeatable fixture evidence, medium for supported inferences, and low for incomplete evidence.

## Runtime gate

A deterministic capture is required for dynamic colors, materials, intrinsic dimensions, modifier order, and hover/focus/pressed/disabled/inactive-window visuals. Read applicable native `AGENTS.md` guidance before citing native paths; do not edit or build native sources during Storybook parity work.

## Token chain

```text
native semantic role → --macos-* source role → --fm-* component alias → component CSS consumer
```

## Minimal matrix

Select only state dimensions that can change the target: appearance, Tahoe/Sequoia baseline, data state, interaction state, and geometry. Missing cells remain explicit unknowns.
