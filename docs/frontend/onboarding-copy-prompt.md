# Onboarding Copy Prompt

너는 macOS 앱 Voyager의 온보딩 카피라이팅 전문가야.
다음 온보딩 맥락과 UI 제약을 이해하고, **온보딩 4단계(Welcome / Beta Access / Permissions / Complete)**에 들어갈 카피를 작성해줘.
목표는 **기능적 이유와 시스템 제약, 사용자가 해야 할 행동**을 정확하고 구체적으로 설명하는 것이다.
과장/마케팅 톤은 금지하며, 기술·운영 맥락을 명확히 전달해야 한다.

## 온보딩 맥락 (기술/흐름)

- 데이터 처리는 **로컬 우선**이며, 온보딩 안내에서는 “어떤 데이터가 로컬에서 처리되고 어떤 상태가 시스템 설정에 의해 결정되는지”를 명확히 설명해야 한다.
- 온보딩은 **완전 블로킹** 흐름: 스텝이 완료되어야 다음 스텝으로 이동 가능하며, 완료 시에만 파일 관리자 창으로 전환된다.
- 온보딩 진행 상태는 로컬에 저장되어 재실행 시 **마지막 유효 스텝**으로 재개된다.
- 인덱싱은 **백그라운드에서 계속 실행**되며, 완료/실패에 대한 별도의 완료 메시지 형식은 없다.
- Full Disk Access(FDA)는 **macOS TCC 제약**으로 인해 사용자가 System Settings에서 **직접 토글**해야 한다.
  - 앱은 FDA 목록에 **자동으로 자신을 추가하거나** 토글을 변경할 수 없다.
  - 사용자가 토글을 켠 뒤에도, 실제 권한 상태는 **OS가 즉시 반영**하며 앱이 임의로 변경할 수 없다.
- Files & Folders 권한은 **실제 파일 접근 시점**에 OS 프롬프트로 승인되며, “허용”을 통해 상태가 바뀐다.
  - 버튼을 눌렀을 때 **접근 시도 → OS 프롬프트**가 뜨는 흐름을 명시한다.
- Beta Access는 **이메일/토큰 입력 + 서버 검증**으로 활성화된다.
  - 검증 실패 시 재시도만 가능하며, 활성화 전에는 다음 단계로 진행할 수 없다.
  - 네트워크 오류/서버 오류로 실패할 수 있음을 안내하고, 그 경우 **재시도만 제공**됨을 명시한다.
- “Launch at Login”은 **선택 옵션**이며, 온보딩 진행/완료와 무관하다.

## UI 구조/제약

- 상단 인셋 바: Back / 중앙 도트 / 우측 CTA(Next (Enter) 또는 Check (Enter)/Retry (Enter) 또는 Start using Voyager)
- CTA 버튼은 상단 우측에 위치하며, Enter 단축키로 동작한다.
- 중앙 정렬 모드: Welcome, Complete (텍스트/버튼 중앙 정렬)
- 2열 모드: Beta Access, Permissions (좌: 요약, 우: 입력/카드)
- 본문 텍스트는 **행동/이유/제약**이 드러나야 하며, 모호한 표현은 금지한다.
- 모든 문구는 **현재 화면에서 사용자가 해야 할 행동**이 무엇인지 드러내야 한다(예: “System Settings에서 토글을 켜야 합니다”).

## 작성 대상 텍스트 슬롯

### A. 공통 요약(좌측 요약 영역 / 중앙 모드에선 상단 타이틀 아래)

- Step Title (예: “Welcome” / “Beta Access” / “Permissions” / “Complete”)
- Step Subtitle (한 문장, 80자 이내 영어)
  - 이유/제약/행동 중 최소 1개가 포함되어야 함

### B. Step 본문

1) Welcome (중앙 정렬)

- 3~4문장.
  - 온보딩이 블로킹이며 4단계로 진행된다는 사실
  - 로컬 처리 원칙(파일 데이터가 네트워크로 전송되지 않음)
  - 재실행 시 마지막 스텝에서 재개됨
  - 사용자가 각 단계에서 해야 할 행동(권한/검증)을 명시

2) Beta Access (우측 입력 영역 상단 안내)

- 이메일/토큰 입력 이유와 검증 흐름을 3~4문장으로 설명:
  - 서버 검증이 필수이며 활성화 전에는 Next가 비활성
  - 실패 유형(네트워크/서버/입력 오류)을 나열
  - 실패 시 재시도만 가능하다는 점 명시
- 상태 카드(Active/Not Active)에 대응되는 안내 문장 2문장
  - Active: “검증 완료, 다음 단계 진행 가능” 명확히
  - Not Active: “입력/검증 필요, 진행 불가” 명확히

3) Permissions (카드 문구)

- FDA 카드: **왜 필요한지 + 왜 수동으로 설정해야 하는지** 3~4문장
  - System Settings 위치를 문장으로 명시
  - 앱이 자동으로 토글/추가할 수 없음을 분명히
  - 사용자가 토글을 켠 후에만 Next가 활성화됨을 명시
- Files & Folders 카드: **권한이 언제/어떻게 부여되는지** 2~3문장
  - 버튼 클릭 시 특정 폴더 접근 시도
  - OS 프롬프트에서 Allow를 눌러야 함
- Launch at Login 카드: **선택 옵션이며 온보딩 진행과 무관함** 1~2문장
- Indexing Preset 요약: **인덱싱이 백그라운드에서 계속됨**을 포함해 2~3문장
  - 완료 메시지가 없음을 명시
  - 프리셋은 읽기 전용 요약임을 명시

4) Complete (중앙 정렬)

- 완료 메시지 2~3문장
  - 모든 스텝 완료됨을 명시
  - “Start using Voyager” 클릭 시 파일 관리자 창으로 전환됨을 명시
  - 실패 시 Retry가 제공됨을 명시

## 톤 가이드

- **차분한 안내/절차 안내 톤**: 사용자가 해야 할 행동과 그 이유를 명확히 안내
- **기술 용어 최소화**: 필요 시에만 사용하되, 쉬운 말로 풀어서 설명
- 과장/마케팅/감탄 금지
- 문장은 짧게 유지하되, 필요한 정보는 생략하지 않는다
- “왜 필요한지/무엇을 해야 하는지/어디에서 해야 하는지”가 문장에 포함되어야 한다
- 전부 영어로 작성

## 출력 형식

아래 포맷으로 작성:

```
[Welcome]
Title:
Subtitle:
Body:

[Beta Access]
Title:
Subtitle:
Body (Intro):
Body (Status):

[Permissions]
Title:
Subtitle:
Body (FDA):
Body (Files & Folders):
Body (Launch at Login):
Body (Indexing preset summary):

[Complete]
Title:
Subtitle:
Body:
```

## Sample Output (Current Copy)

```
[Welcome]
Title: Welcome
Subtitle: This setup is required before you can open Voyager's file manager.
Body:
Voyager runs a four-step setup. You can move forward only after each step is complete.
Your files stay on your Mac; nothing is uploaded during onboarding.
If you quit and reopen Voyager, it resumes at the last saved step.

[Beta Access]
Title: Beta Access
Subtitle: Validate your invite with email and token before you can continue.
Body (Intro):
Enter the email and token from your invite.
Click Check to verify with the server. Until verification succeeds, Next stays disabled.
Verification can fail due to input errors, expired tokens, or network/server issues.
If it fails, correct the input and Retry/Check.

Body (Status):
Active:
Your invite is verified and beta access is enabled. You can proceed.

Not Active:
Beta access isn't active yet. Enter both your email and token, then click Check.

[Permissions]
Title: Permissions
Subtitle: Enable macOS permissions so Voyager can index locally.
Body (FDA):
Full Disk Access is required. Enable it in System Settings to continue.
Enable it manually in System Settings > Privacy & Security > Full Disk Access. Voyager cannot add itself or change this toggle.
Next unlocks after macOS reports Full Disk Access as granted.

Body (Files & Folders):
Click Grant Access to request access to Desktop, Documents, and Downloads.
macOS will show a permission prompt at that moment. Choose Allow to grant access.
You can allow access later in System Settings.

Body (Launch at Login):
Launch at Login is optional and does not affect onboarding completion.

Body (Indexing preset summary):
Indexing runs in the background and continues after onboarding.
You will not see a single "indexing complete" message.
This is a read-only summary of what will be included and excluded.

[Complete]
Title: Complete
Subtitle: All steps are complete. Start Voyager to open your first window.
Body:
Setup is finished and Voyager is ready to use.
Click Start using Voyager to open your first file manager window.
If it fails, you'll see Retry to try again.
```
