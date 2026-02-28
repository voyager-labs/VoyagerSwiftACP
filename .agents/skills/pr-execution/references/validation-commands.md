# Validation Commands

Base commands used when recording verification results in the PR body.

## Backend (Python/FastAPI)

```bash
cd apps/backend
uv run pytest
uv run pyright
```

If needed:

```bash
cd apps/backend
uv run ruff check
```

## macOS (Voyager)

Verify Dev build:

```bash
xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -configuration Debug build
```

Verify Prod build:

```bash
xcodebuild -scheme Voyager-Prod -configuration Release -workspace apps/macos/Voyager/Voyager.xcodeproj/project.xcworkspace build
```

Tests (If needed):

```bash
xcodebuild test -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -skip-testing:VoyagerUITests
```

## Recording Rules

- Success: Record as `{command}: pass`.
- Failure: Record as `{command}: fail` + cause (e.g., macro trust, signing) + follow-up action.
- Distinguish environment-dependent failures from "code issues".
