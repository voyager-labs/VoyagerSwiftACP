# XcodeBuildMCP — Build, Test, Diagnostics

XcodeBuildMCP provides structured access to Xcode builds, tests, and simulator management via MCP. It is preferred only when its exposed operation supports the required simulator scope. The executor matrix in `../SKILL.md` selects SwiftPM, repository `mise`, or an explicit stop for other scopes; do not call raw `xcodebuild` as an agent substitute.

## When to Use

- Check if code compiles (after changes)
- Run tests to verify behavior
- Get compile errors and warnings (replaces LSP diagnostics)
- Launch app on simulator
- Take UI snapshots for verification
- Manage build session defaults (scheme, simulator, configuration)

## Session Management

Always check defaults before the first build in a session:

```yaml
# Check current defaults
XcodeBuildMCP_session_show_defaults()

# Set defaults for an actual simulator-capable scheme
XcodeBuildMCP_session_set_defaults(
  projectPath: "<simulator-project>.xcodeproj",
  scheme: "<simulator-capable-scheme>",
  simulatorName: "iPhone"
)

# Set defaults with full parameters
XcodeBuildMCP_session_set_defaults(
  projectPath: "<simulator-project>.xcodeproj",
  scheme: "<simulator-capable-scheme>",
  simulatorName: "iPhone",
  configuration: "Debug",
  derivedDataPath: ".build",
  bundleId: "<simulator-app-bundle-id>"
)

# Named profiles for multi-configuration workflows
XcodeBuildMCP_session_set_defaults(
  scheme: "<simulator-capable-release-scheme>",
  configuration: "Release",
  profile: "release",
  createIfNotExists: true,
  persist: true
)

# Switch between profiles
XcodeBuildMCP_session_use_defaults_profile(profile: "release", persist: true)

# Clear defaults (all or specific keys)
XcodeBuildMCP_session_clear_defaults(keys: ["scheme", "configuration"])
XcodeBuildMCP_session_clear_defaults(all: true)

# List available schemes
XcodeBuildMCP_list_schemes(workspacePath: "apps/macos/Voyager/Voyager.xcworkspace")

# List simulators
XcodeBuildMCP_list_sims()
XcodeBuildMCP_list_sims(enabled: true)
```

## Project Discovery

```yaml
# Scan for Xcode projects and workspaces
XcodeBuildMCP_discover_projs(workspaceRoot: "/path/to/project")

# Scan with depth limit
XcodeBuildMCP_discover_projs(workspaceRoot: ".", maxDepth: 3)
```

## Build Operations

```yaml
# Compile only (no launch)
XcodeBuildMCP_build_sim()

# Compile + install + launch on simulator
XcodeBuildMCP_build_run_sim()

# Additional build arguments
XcodeBuildMCP_build_sim(extraArgs: ["-configuration", "Debug"])

# Build and run with launch arguments
XcodeBuildMCP_build_run_sim(launchArgs: ["--debug-flag"])

# Clean build products
XcodeBuildMCP_clean()
XcodeBuildMCP_clean(platform: "macOS", extraArgs: ["-workspace", "path/to.xcworkspace"])

# Show build settings
XcodeBuildMCP_show_build_settings()
```

## App Lifecycle

Separate build and launch steps for more control:

```yaml
# Get the built .app path (after building)
XcodeBuildMCP_get_sim_app_path(platform: "iOS Simulator")

# Extract bundle ID from .app
XcodeBuildMCP_get_app_bundle_id(appPath: "/path/to/App.app")

# Install .app on simulator
XcodeBuildMCP_install_app_sim(appPath: "/path/to/App.app")

# Launch app with arguments and environment variables
XcodeBuildMCP_launch_app_sim(
  launchArgs: ["--debug-flag"],
  env: {"LOG_LEVEL": "verbose"}
)

# Stop running app
XcodeBuildMCP_stop_app_sim()
```

## Test Operations

```yaml
# Run tests on simulator
XcodeBuildMCP_test_sim()

# Run with additional arguments
XcodeBuildMCP_test_sim(extraArgs: ["-only-testing:VoyagerTests/FileManagerTests"])

# Show test progress
XcodeBuildMCP_test_sim(progress: true)

# Pass environment variables to test runner
XcodeBuildMCP_test_sim(testRunnerEnv: {"TEST_MODE": "integration"})
```

## Simulator Management

```yaml
# Boot simulator
XcodeBuildMCP_boot_sim()

# Open Simulator.app
XcodeBuildMCP_open_sim()

# Take screenshot (returns file path or base64)
XcodeBuildMCP_screenshot()
XcodeBuildMCP_screenshot(returnFormat: "base64")

# Take UI snapshot (accessibility tree with element refs)
XcodeBuildMCP_snapshot_ui()

# UI snapshot with change detection (skip if screen unchanged)
XcodeBuildMCP_snapshot_ui(sinceScreenHash: "abc123")

# Stop running app
XcodeBuildMCP_stop_app_sim()

# Record video
XcodeBuildMCP_record_sim_video(start: true, outputFile: "/tmp/recording.mp4")
XcodeBuildMCP_record_sim_video(start: true, outputFile: "/tmp/rec.mp4", fps: 60)
XcodeBuildMCP_record_sim_video(stop: true)
```

## Coverage

```yaml
# Get coverage report
XcodeBuildMCP_get_coverage_report(xcresultPath: "path/to.xcresult")

# Per-target coverage
XcodeBuildMCP_get_coverage_report(xcresultPath: "path/to.xcresult", target: "Voyager")

# Per-file coverage breakdown
XcodeBuildMCP_get_coverage_report(xcresultPath: "path/to.xcresult", showFiles: true)

# Get file-level coverage
XcodeBuildMCP_get_file_coverage(xcresultPath: "path/to.xcresult", file: "FileManagerReducer.swift")

# File-level uncovered line ranges
XcodeBuildMCP_get_file_coverage(xcresultPath: "path/to.xcresult", file: "Reducer.swift", showLines: true)
```

## Workflow Patterns

### Pattern: Verify changes compile

```yaml
1. XcodeBuildMCP_session_show_defaults()   # verify project/scheme
2. XcodeBuildMCP_build_sim()               # compile check
3. Fix any compile errors
4. XcodeBuildMCP_build_sim()               # re-verify
```

### Pattern: Full verification cycle

```yaml
1. XcodeBuildMCP_session_show_defaults()
2. XcodeBuildMCP_build_sim()               # compile
3. XcodeBuildMCP_test_sim()                # run tests
4. XcodeBuildMCP_get_coverage_report(...)   # check coverage (optional)
```

### Pattern: UI verification

```yaml
1. XcodeBuildMCP_build_run_sim()           # build + launch
2. XcodeBuildMCP_snapshot_ui()             # capture UI state
3. XcodeBuildMCP_screenshot()              # take screenshot
4. XcodeBuildMCP_stop_app_sim()            # cleanup
```

## Troubleshooting

- **"No scheme configured"**: Run `session_set_defaults()` with workspace and scheme
- **"Simulator not found"**: Run `list_sims()` to see available simulators
- **Build fails with "project not found"**: Verify `workspacePath` or `projectPath` is correct
- **Tests timeout**: Use `progress: true` to see real-time test output

## Relationship to Other Tools

- Use **CodeGraph** to understand what to change before building
- Use **ast-grep** for pattern-based rewrites, then build to verify
- Use **Periphery** to find unused code (separate from build)
- Repository `mise` tasks already format their own macOS Xcode output; use them only when the capability matrix selects a macOS scheme outcome.
