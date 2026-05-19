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

# Onboarding package tests (ONB-001 + ONB-003)
test-onboarding:
    swift test --package-path apps/macos/Packages/02_Pages/Onboarding

# ONB-001 focused tests
test-onb001:
    swift test --package-path apps/macos/Packages/02_Pages/Onboarding --filter ONB001RunUserOnboardingFeatureTests

# ONB-003 focused tests
test-onb003:
    swift test --package-path apps/macos/Packages/02_Pages/Onboarding --filter ONB003ConfigureRequiredPermissionsFeatureTests

# BetaAccess package tests (ONB-002)
test-beta-access:
    swift test --package-path apps/macos/Packages/04_Features/BetaAccess

# Build OnboardingHost
build-onboarding-host:
    xcodebuild -project apps/macos/Hosts/OnboardingHost/OnboardingHost.xcodeproj -scheme OnboardingHost-Dev -configuration Debug -derivedDataPath .sisyphus/derivedData/onboardinghost build

# Smoke test OnboardingHost (reset mode)
smoke-onboarding-host-reset: build-onboarding-host
    ONBOARDING_HOST_SMOKE=1 ONBOARDING_HOST_RESET_PROGRESS=1 .sisyphus/derivedData/onboardinghost/Build/Products/Debug/OnboardingHost.app/Contents/MacOS/OnboardingHost

# Smoke test OnboardingHost (non-reset mode)
smoke-onboarding-host-no-reset: build-onboarding-host
    ONBOARDING_HOST_SMOKE=1 ONBOARDING_HOST_RESET_PROGRESS=0 .sisyphus/derivedData/onboardinghost/Build/Products/Debug/OnboardingHost.app/Contents/MacOS/OnboardingHost
