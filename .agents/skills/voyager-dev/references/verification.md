# Voyager Dev Verification

## Task-shape expectations

- `scaffold`
  - Verify the new files land in the correct FSD layer.
  - Verify `State`, `Action`, and reducer entry points match the selected module shape.
- `decompose`
  - Verify ownership boundaries are clearer after the split.
  - Verify moved logic still routes through the parent feature and preserves cancellation ownership.
- `observation-refactor`
  - Verify target views no longer own external/system observation.
  - Verify reducers own `startObserving...` / `stopObserving...` lifecycle plus `.cancellable` / `.cancel`.
  - Verify a semantic internal action receives the routed signal.
- `reuse-guard`
  - Verify the chosen abstraction reuse decision is recorded and that duplicate structures were avoided.

## Focused verification (preferred first)

```bash
xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj -only-testing:VoyagerTests/<TargetTests>
```

## Full verification

```bash
xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj
```

## Optional pre-check

```bash
xcodebuild -list -project apps/macos/Voyager/Voyager.xcodeproj
```

Use focused tests first, then expand to full suite when changing shared reducers or cross-feature dependencies.

## Search-based checks

- Use `grep` or `ast-grep` when architecture changes need a mechanical proof point.
- For observation refactors, search the touched `Ui/*.swift` files for `.onReceive(` and `NotificationCenter.default.publisher`.
- For decomposition or model splits, search for stale type names, dead extension files, or bypassed reducer routes.

## Layer checks

- Apply the layer-specific review checklist from `macos-architecture-shape.md`.
- When needed, use search-based proof for known failure modes such as widget-owned `Api/`, reverse imports, or page-specific logic leaking downward.

## FSD checks

- Apply `macos-architecture-shape.md` and `public-boundary-spec.md` when layer choice, slice boundary, or segment naming changed.

## Boundary and test checks

- When slice-boundary changes are involved, apply `public-boundary-spec.md` checks.
- When reducer or integration tests change, apply `testing-playbook.md` checks.
