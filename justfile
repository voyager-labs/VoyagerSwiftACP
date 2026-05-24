# Voyager App — justfile
# 사용법: just -l (명령 목록)

# 기본 명령 (just 만 실행하면 setup)
default: setup

# 온보딩: clone 후 한 번 실행
setup: brew-install xcode hooks submodules

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

# hooks 재설치
reinstall-hooks:
    lefthook install --force
