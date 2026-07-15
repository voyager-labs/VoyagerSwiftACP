# Swift 6 Package Rules

Enforces Swift 6 strict concurrency rules for all SwiftPM packages. Every SwiftPM package uses `swift-tools-version:6.0`. Every type is `Sendable` or explicitly annotated.

## When to load

- Creating a new SwiftPM package
- Moving any type (struct, enum, class, protocol) into an existing SwiftPM package
- Adding a new file to a SwiftPM package
- Editing Package.swift (targets, dependencies, products)
- Fixing "stored property is not Sendable" or "closure is not @Sendable" compiler errors
- Deciding between making a type `Sendable` vs using `nonisolated(unsafe)`

## Mandatory rules

1. **New packages: `swift-tools-version:6.0`** — always. No exceptions.
2. **Every type in a package: `Sendable`** — either directly, via `@Sendable` closures, or with documented `nonisolated(unsafe)` and a filed follow-up.
3. **Build the package immediately** after adding or moving types. The app target may run in Swift 5 mode and will not catch strict concurrency errors.

## Checklist

### 1. Creating a new package

- [ ] Set `swift-tools-version:6.0` in Package.swift
- [ ] Define targets with clear names
- [ ] Add minimal dependencies only
- [ ] Build immediately: `swift build --package-path <path>`

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyPackage",
    targets: [
        .target(name: "MyPackage"),
        .testTarget(name: "MyPackageTests", dependencies: ["MyPackage"]),
    ]
)
```

### 2. Adding a new type to a package

Every type added to a package must be `Sendable`. No exceptions.

#### 2a. Value type (all Sendable properties)

```swift
public struct AppConfig: Sendable {
    public let name: String
    public let version: Int
}
```

- [ ] Add `: Sendable` to the type declaration
- [ ] All stored properties are `let` or Sendable types
- [ ] Build: `swift build --package-path <path>`

#### 2b. Type with a stored closure

```swift
public struct ActionHandler: Sendable {
    public let onEvent: @Sendable (Event) -> Void

    public init(onEvent: @escaping @Sendable (Event) -> Void) {
        self.onEvent = onEvent
    }
}
```

- [ ] `@Sendable` on the stored property
- [ ] `@Sendable` on the init parameter (both must match)
- [ ] `@escaping` comes before `@Sendable`
- [ ] Build

#### 2c. Enum with associated values

```swift
public enum LoadingState: Sendable {
    case idle
    case loading
    case loaded(Data)
    case failed(any Error & Sendable)
}
```

- [ ] `: Sendable` on the enum
- [ ] Every associated value type is Sendable
- [ ] Use `any Error & Sendable` for error payloads
- [ ] Build

#### 2d. Type with static properties

```swift
public struct FeatureFlags: Sendable {
    public static let enableNewUI = true
    public static let maxItems = 100
}
```

- [ ] `: Sendable` on the type
- [ ] No mutable `static var` — if needed, use an actor
- [ ] Build

#### 2e. Protocol

```swift
public protocol EventHandler: Sendable {
    func handle(_ event: Event) async
}
```

- [ ] `: Sendable` on the protocol
- [ ] All requirements are concurrency-safe
- [ ] Build

### 3. Moving a type from app target to package

Same rules as adding a new type. Extra steps:

1. Copy the type into the package
2. Make it `Sendable` (follow section 2)
3. Add `public` to the minimal required surface
4. Build the package
5. Delete the app-local copy
6. Build the consumer (app target)
7. Run consumer tests

The app target may not catch concurrency errors because it runs in Swift 5 mode. The package build will.

### 4. nonisolated(unsafe) — last resort only

When a type genuinely cannot be made Sendable right now:

```swift
public struct LegacyWrapper: Sendable {
    /// TEMPORARY: NSCache is not Sendable. Filed as ISSUE-XXX.
    nonisolated(unsafe) public let cache: NSCache<NSString, NSObject>
}
```

**Every `nonisolated(unsafe)` MUST have:**

- [ ] A code comment explaining why
- [ ] A filed follow-up issue to fix it
- [ ] Both are present before the PR can merge

This is debt. Not a solution.

### 5. @unchecked Sendable — documented safety invariant

When a type contains non-Sendable associated values from AppKit (e.g., `NSItemProvider`, `NSDraggingItem`) that are always used within a specific isolation domain:

- Add `@unchecked Sendable` to the type.
- Add a Korean comment documenting the safety invariant.
- Example: `// NSItemProvider가 Sendable을 준수하지 않아 @unchecked 필요. 드래그앤드롭은 @MainActor에서만 수행됨.`
- No follow-up issue required when the root cause is an AppKit framework limitation.
- File a follow-up issue only when the non-Sendable payload comes from code you control and could fix.

This differs from `nonisolated(unsafe)` which is for stored properties. `@unchecked Sendable` is for types where the non-Sendable payload is guaranteed safe by isolation domain.

### 6. Verification after any package change

After creating, editing, or adding files to a package:

```
1. swift build --package-path <path>     → package compiles
2. swift test --package-path <path>      → package tests pass (if tests exist)
3. Build consumer target (XcodeBuildMCP) → consumer links and imports the package
4. Test consumer target (XcodeBuildMCP)  → consumer tests pass
```

Each step must pass before moving to the next. For detailed integration-layer verification (consumer build/test, stale import detection, public surface checks), see `package-integration.md`.

## Decision flowchart

```
Code goes into a SwiftPM package
  |
  ├─ New package? → swift-tools-version:6.0
  |
  ├─ New type? → Make it Sendable
  |    ├─ All Sendable properties? → Add `: Sendable`. Done.
  |    ├─ Has closures? → `@Sendable` on property AND init param.
  |    ├─ Has non-Sendable deps? → Refactor, `@unchecked Sendable` + Korean comment (AppKit limitation), or `nonisolated(unsafe)` + follow-up.
  |    ├─ Has statics? → `: Sendable` on the type.
  |    └─ Protocol? → `: Sendable` on the protocol.
  |
  └─ Moving from app? → Same as new type + delete app-local copy + verify consumer build.
```

## Common mistakes

- **Creating a package with swift-tools-version < 6.0.** Always 6.0. No exceptions.
- **Forgetting @Sendable on closure init parameters.** The property gets the annotation, but the init parameter does not. Both need it.
- **Trusting the app target build.** It runs in Swift 5 mode and will not catch strict concurrency errors. Always build the package directly.
- **Using `nonisolated(unsafe)` without a follow-up.** Every use must have a code comment and a filed issue.
- **Using `@unchecked Sendable` without a safety invariant comment.** Every use must have a Korean comment explaining why the non-Sendable payload is safe. Example: AppKit types used only within `@MainActor` isolation.
- **Adding `Sendable` to types with mutable stored properties.** `Sendable` requires thread-safe immutability. Mutable properties need an actor or removal of `Sendable`.
