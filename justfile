# Voyager App — justfile
# 사용법: just -l (명령 목록)

# 기본 명령 (just 만 실행하면 setup)
default: setup

# 온보딩: clone 후 한 번 실행
setup: brew-install xcode hooks submodules npm-install

# Homebrew 의존성 설치
brew-install:
    brew bundle

# .xcode-version 기준 Xcode 설치 및 선택
xcode:
    bash scripts/xcodes.sh

# Git hooks 설치 (Lefthook)
hooks:
    lefthook install

# Submodule 초기화
submodules:
    git submodule update --init --recursive

# npm 의존성 설치 (codegraph 등)
npm-install:
    npm install

# SourceKit-LSP용 buildServer.json 생성
lsp:
    python3 scripts/dev/setup_sourcekit_lsp.py

# SourceKit-LSP 컨텍스트 선택 (예: just lsp-context -- --path apps/macos/Voyager/VoyagerHelper)
lsp-context *ARGS:
    python3 scripts/dev/lsp_context.py {{ARGS}}

# macOS 변경 범위 기반 검증 계획/실행 (예: just macos-checks -- --changed --run)
macos-checks *ARGS:
    python3 scripts/dev/macos_checks.py {{ARGS}}

# macOS 개발 앱 빌드 (worktree 내부 DerivedData 사용)
macos-build:
    xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -configuration Debug -derivedDataPath build/dev/DerivedData -clonedSourcePackagesDirPath build/dev/SourcePackages -skipPackagePluginValidation -skipMacroValidation build

# macOS 개발 앱 테스트 (worktree 내부 DerivedData 사용)
macos-test:
    xcodebuild test -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -configuration Debug -derivedDataPath build/dev/DerivedData -clonedSourcePackagesDirPath build/dev/SourcePackages -skipPackagePluginValidation -skipMacroValidation

# Xcode 툴체인의 Swift 버전 확인 (swiftly PATH 우회)
swift-version:
    python3 scripts/dev/check_swift_version.py

# hooks 재설치
reinstall-hooks:
    lefthook install --force

# CodeGraph 인덱스 초기화 (최초 1회)
codegraph-init:
    npx codegraph init -i

# CodeGraph MCP 서버 실행
codegraph-serve:
    npx codegraph serve --mcp

# CodeGraph 인덱스 재구축
codegraph-reindex:
    npx codegraph index

# CodeGraph 인덱스/캐시 삭제
codegraph-clean:
    rm -rf .codegraph

# CodeGraph 인덱스 상태 확인
codegraph-status:
    npx codegraph status
