# Design Foundation

설정(Settings) 표면의 공용 디자인 파운데이션 패키지입니다. `file-manager-illustration`이 소유하던 macOS 토큰/폰트를 공용으로 끌어올려, file-manager와 settings 표면이 동일한 시각 언어를 공유합니다.

## 1. Authority

디자인 권위는 네이티브 macOS `06_Shared/VoyagerShared`의 **VoyagerDS 미러**입니다. Storybook 패키지는 결정적 리뷰 번역일 뿐 런타임 증명이 아닙니다.

## 2. Multi-scope `:where()` 계약

`src/styles/macos-tokens.css`의 모든 토큰 규칙은 다음 세 스코프 속성 중 하나에만 적용되도록 스코프가 지정됩니다.

```css
:where(
  [data-design-foundation],
  [data-file-manager-illustration],
  [data-settings-illustration]
)
```

- **`data-design-foundation`** — 본 파운데이션 토큰의 기본 스코프.
- **`data-file-manager-illustration`** — file-manager 표면 하위 호환 스코프.
- **`data-settings-illustration`** — settings 표면 스코프.

`:where()`로 감싸므로 특이도가 0이 되어, 각 표면이 자체 스코프 규칙으로 토큰 소비를 자유롭게 재정의할 수 있습니다. 세 스코프 모두 동일한 토큰 값을 공유합니다.

## 3. Contents

| 파일                          | 역할                                                                                    |
| ----------------------------- | --------------------------------------------------------------------------------------- |
| `src/styles/macos-tokens.css` | `--macos-*` 시맨틱 토큰 (색상, spacing, radius, shadow, motion 등)                      |
| `src/styles/fonts.css`        | SF Pro Text 400/500/600/700, Display 400/500/600/700, Symbols `1 1000` 9개 `@font-face` |
| `symbolist`                   | SF Symbol / 폰트 렌더링 의존성                                                          |

## 4. Rules

- **모든 색상은 `--macos-*` 토큰만 사용** — 컴포넌트 레벨 원시 색상 금지.
- **모든 컴포넌트는 형제 `.stories.tsx`** — Storybook 카탈로그에서 리뷰 가능해야 함.
- 토큰 값/주석/순서는 `file-manager-illustration` 소스와 바이트 동일하게 유지(셀렉터 스코프만 변경).
- `src/index.ts`는 아직 생성하지 않음(추후 Wave에서 공용 진입점으로 추가).
