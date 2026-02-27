# Validation Commands

PR 본문에 검증 결과를 적을 때 사용하는 기본 명령 모음입니다.

## Backend (Python/FastAPI)

```bash
cd apps/backend
uv run pytest
uv run pyright
```

필요 시 추가:

```bash
cd apps/backend
uv run ruff check
```

## macOS (Voyager)

Dev 빌드 확인:

```bash
xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -configuration Debug build
```

Prod 빌드 확인:

```bash
xcodebuild -scheme Voyager-Prod -configuration Release -workspace apps/macos/Voyager/Voyager.xcodeproj/project.xcworkspace build
```

테스트(필요 시):

```bash
xcodebuild test -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev
```

## 기록 규칙

- 성공: `명령: pass` 형태로 기록
- 실패: `명령: 실패` + 원인(예: macro trust, signing/team/provisioning) + 후속 조치
- 환경 의존 실패는 "코드 문제"와 분리해서 명시
