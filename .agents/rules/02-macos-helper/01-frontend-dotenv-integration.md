---
globs: apps/macos/**/*.swift
description: 'Swift-dotenv integration patterns and environment management'
---

# Swift-dotenv Integration

## Environment loading patterns

- **Repository root detection**: Infer project root from bundle path
- **Dotenv configuration**: Use `Dotenv.configure(atPath: rootEnv.path, overwrite: true)`
- **Values access**: Access via `Dotenv.values` dictionary
- **Runtime merge**: Combine `.env` values with secure sources (Keychain, CI secrets) immediately before launching helper processes; do not persist the merged output.

## Implementation example

```swift
import SwiftDotenv

private func loadEnvConfig() {
    envRootURL = inferRootFromBundle(start: Bundle.main.bundleURL)
    if let root = envRootURL {
        let rootEnv = root.appendingPathComponent(".env")
        try? Dotenv.configure(atPath: rootEnv.path, overwrite: true)
        envVars = Dotenv.values
    }
}
```

## Path resolution

- **Absolute paths**: Use as-is (`/path/to/file`)
- **Relative paths**: Resolve from project root (`logs/voyager.log` → `{root}/logs/voyager.log`)
- **Variable substitution**: Handle `$(SRCROOT)` and similar build-time variables

## Integration with existing systems

- **Backend launcher**: Use VoyagerHelper's `Environment.swift` + `ProcessRunner.swift` for dotenv-based backend management
  - `Environment` 구조체가 dotenv 로딩과 설정 캡슐화 담당
  - `ProcessRunner`는 `Environment` 의존성 주입으로 설정 접근
  - Python 프로세스에는 최소 환경 변수만 주입 (`APP_ENV`, `BACKEND_MODE`, `PATH`)
  - Python 백엔드가 `APP_ENV` 기반으로 `.env.{app_env}` 파일을 자체 로드
- **Logging**: Resolve log file paths relative to project root
- **Environment management**: Single source of truth via `.env` file
- **Keychain merge**: (선택) 필요 시 Keychain 기반 시크릿 로딩을 추가하되, 디스크/로그에 쓰지 않고 프로세스 환경으로만 주입합니다.

References
- Implementation: [Environment.swift](mdc:apps/macos/Voyager/VoyagerHelper/Infrastructure/Environment.swift)
- Overview: [00-frontend-overview.md](/.agents/rules/01-macos-voyager/00-frontend-overview.md)
