# RTK & xcbeautify — Token Optimization

## RTK — Command Output Compression

RTK is an OpenCode plugin that automatically compresses command output to save tokens. It hooks into `tool.execute.before` and filters output from common commands like `ls`, `git status`, `git log`, etc.

### When It Activates

Automatically. No manual invocation needed. RTK runs as an OpenCode plugin configured in `opencode.json`.

### What It Compresses

| Command      | Typical savings |
| ------------ | --------------- |
| `ls`         | ~78%            |
| `git status` | ~62%            |
| `git log`    | ~6%             |

### Setup

Already configured via `scripts/setup.sh`:

```bash
mise exec -- rtk init -g --opencode
```

This installs the RTK plugin to `~/.config/opencode/plugins/rtk.ts`.

## xcbeautify — Build Output Formatting

xcbeautify formats Xcode build output for readability. Pipe build output through it when running builds outside XcodeBuildMCP.

### When to Use

- Formatting build output for readability
- Reducing build log noise in CI

### Usage

```bash
# Pipe any build command through xcbeautify
some-build-command 2>&1 | mise exec -- xcbeautify

# With specific formatting
some-build-command 2>&1 | mise exec -- xcbeautify --renderer github-actions
```

### Tips

- Not needed when using XcodeBuildMCP (handles formatting internally)
- Useful for `mise` tasks or CI scripts that call build commands directly
