# Voyager Dev Verification

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
