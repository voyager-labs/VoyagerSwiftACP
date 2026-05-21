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

# Settings: full test suite
test-settings:
    swift test --package-path apps/macos/Packages/02_Pages/Settings

# Settings: SET-001 focused (SettingsWindow)
test-set001:
    swift test --package-path apps/macos/Packages/02_Pages/Settings --filter SET001SettingsWindowFeatureTests

# Settings: SET-002 focused (GeneralSettings)
test-set002:
    swift test --package-path apps/macos/Packages/02_Pages/Settings --filter SET002GeneralSettingsFeatureTests

# Settings: SET-003 focused (AppearanceSettings)
test-set003:
    swift test --package-path apps/macos/Packages/02_Pages/Settings --filter SET003AppearanceSettingsFeatureTests

# Build SettingsHost
build-settings-host:
    xcodebuild -project apps/macos/Hosts/SettingsHost/SettingsHost.xcodeproj -scheme SettingsHost-Dev -configuration Debug -derivedDataPath .sisyphus/derivedData/settingshost build

# Smoke test SettingsHost (reset mode)
smoke-settings-host-reset: build-settings-host
    SETTINGS_HOST_SMOKE=1 SETTINGS_HOST_RESET_PROGRESS=1 .sisyphus/derivedData/settingshost/Build/Products/Debug/SettingsHost.app/Contents/MacOS/SettingsHost

# Smoke test SettingsHost (non-reset mode)
smoke-settings-host-non-reset: build-settings-host
    SETTINGS_HOST_SMOKE=1 SETTINGS_HOST_RESET_PROGRESS=0 .sisyphus/derivedData/settingshost/Build/Products/Debug/SettingsHost.app/Contents/MacOS/SettingsHost
