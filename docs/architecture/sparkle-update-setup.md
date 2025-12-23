# Sparkle 자동 업데이트 설정 가이드

이 문서는 Voyager 앱에 Sparkle 자동 업데이트 기능을 추가하는 방법을 설명합니다.

## 개요

[Sparkle](https://sparkle-project.org/)은 macOS 앱에서 가장 널리 사용되는 자동 업데이트 프레임워크입니다.

## 설정 단계

### 1. Sparkle SPM 패키지 추가

Xcode에서:
1. File → Add Package Dependencies
2. URL: `https://github.com/sparkle-project/Sparkle`
3. Version: `2.x` (최신 버전 선택)
4. Voyager 타겟에 `Sparkle` 프레임워크 추가

### 2. Info.plist 설정

Voyager 앱의 Info.plist에 다음 키 추가:

```xml
<key>SUFeedURL</key>
<string>https://your-server.com/appcast.xml</string>

<key>SUPublicEDKey</key>
<string>YOUR_PUBLIC_ED_KEY</string>
```

### 3. AppDelegate에 Sparkle 통합

`AppDelegate.swift`에 추가:

```swift
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    private var updaterController: SPUStandardUpdaterController!
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 기존 코드...
        
        // Sparkle 업데이터 초기화
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
}
```

### 4. 메뉴에 "Check for Updates" 추가

```swift
import Sparkle

struct AppMenu: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    
    init(updater: SPUUpdater) {
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }
    
    var body: some View {
        Button("Check for Updates...") {
            checkForUpdatesViewModel.updater.checkForUpdates()
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    let updater: SPUUpdater
    
    init(updater: SPUUpdater) {
        self.updater = updater
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}
```

### 5. EdDSA 키 생성

Sparkle은 EdDSA 서명을 사용합니다:

```bash
# Sparkle 도구 다운로드 후
./bin/generate_keys

# 출력된 public key를 Info.plist의 SUPublicEDKey에 저장
# private key는 안전하게 보관 (CI secrets 등)
```

### 6. Appcast.xml 생성

릴리스마다 appcast.xml 업데이트가 필요합니다:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Voyager Updates</title>
    <item>
      <title>Version 1.0.1</title>
      <sparkle:version>1.0.1</sparkle:version>
      <sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
      <description><![CDATA[
        <h2>What's New</h2>
        <ul>
          <li>Bug fixes and improvements</li>
        </ul>
      ]]></description>
      <pubDate>Mon, 01 Jan 2025 00:00:00 +0000</pubDate>
      <enclosure
        url="https://your-server.com/releases/Voyager-1.0.1.dmg"
        sparkle:edSignature="YOUR_ED_SIGNATURE"
        length="12345678"
        type="application/octet-stream"
      />
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    </item>
  </channel>
</rss>
```

### 7. GitHub Actions에서 자동화

릴리스 시 appcast.xml 자동 업데이트:

```yaml
- name: Sign update with Sparkle
  run: |
    ./bin/sign_update "Voyager-${{ steps.version.outputs.version }}.dmg" \
      --ed-key-file "${{ secrets.SPARKLE_PRIVATE_KEY }}"

- name: Update appcast.xml
  run: |
    ./bin/generate_appcast ./releases/
```

## Entitlements 설정

Sparkle 사용 시 필요한 entitlements:

```xml
<!-- 네트워크 액세스 (업데이트 체크) -->
<key>com.apple.security.network.client</key>
<true/>
```

## 보안 고려사항

1. **Private Key 보호**: EdDSA private key는 절대 커밋하지 않음
2. **HTTPS 필수**: appcast.xml과 DMG는 HTTPS로 제공
3. **코드 서명**: DMG와 앱 모두 코드 서명 필수

## 참고 자료

- [Sparkle Documentation](https://sparkle-project.org/documentation/)
- [Sparkle GitHub](https://github.com/sparkle-project/Sparkle)
- [EdDSA Signatures](https://sparkle-project.org/documentation/eddsa-migration/)

