# VOY-119 Undo/Redo Entry Action - Brownfield Enhancement

## Epic Goal
Entries View에서 Entry 액션을 Undo/Redo 할 수 있도록 UndoManager 기반의 안전한 되돌리기/재적용을 제공하고, 기존 기능의 회귀 없이 동작하게 한다.

## Epic Description

**Existing System Context:**
- Current relevant functionality: File Manager Content Pane에서 Entry 액션(이름 변경, 이동, 복사/붙여넣기, 휴지통 이동/복원 등)을 수행함.
- Technology stack: macOS SwiftUI + TCA + AppKit.
- Integration points (초안, 확인 필요):
  - `FSItemsFeature` / `FSItemsOperationsFeature`: 파일 액션 상태/실행
  - `FSItemClient`: 파일 시스템 I/O
  - `ContentPaneView`: 키보드 처리(⌘Z/⇧⌘Z)
  - `EditMenuCommands`: Edit 메뉴 Undo/Redo 핸들링
  - `FileManagerFeature`: 탭 단위 상태 보관(Undo/Redo 스택 스코프)
  - `NSUndoManager` 소유/수명 범위: 탭 스코프 분리를 만족하는 위치를 결정 후 문서화

**Enhancement Details:**
- UndoManager API를 사용해 Entry 액션 Undo/Redo를 구현한다.
- 탭 세션 단위로 Undo/Redo 스택을 분리한다.
- 지원 액션: rename, move, duplicate, paste, create folder, move to trash, put back.
- 비지원 액션: delete immediately, compress, extract.
- 대상 아이템이 busy일 때만 Undo/Redo를 차단한다.
- 실패/부분 성공은 로컬 `ClientError`로 분류해 로그만 기록한다. (`docs/frontend/error-handling-propagation.md` 참고)
- 로컬 저널은 메모리 스택만 사용한다.

**Success Criteria:**
- Undo/Redo가 UndoManager 기반으로 동작한다.
- TCA 패턴을 엄격히 준수한다.
- 지원 액션에 대한 Undo/Redo가 정상 동작한다.
- 단위 테스트로 핵심 경로를 검증한다.

## Stories (2)

1) **Story 1: Entry 액션 레코드/UndoManager 등록**
   - Entry 액션 레코드 모델 정의(타입, 대상, before/after 경로).
   - 성공한 파일 작업에서 UndoManager 등록/스택 기록.
   - 탭 단위 상태 분리 및 Redo 스택 관리.

2) **Story 2: Undo/Redo 실행 + UI 연동 + 테스트**
   - Content Pane에서 ⌘Z/⇧⌘Z 처리.
   - Edit 메뉴 Undo/Redo 연결 및 enable/disable 처리.
   - busy 대상 가드 및 실패 로그.
   - Feature 단위 테스트 추가.

## Compatibility Requirements
- [ ] 기존 API/동작은 유지한다.
- [ ] DB/스토리지 스키마 변경 없음.
- [ ] UI 동작은 기존 패턴과 일관되게 유지한다.
- [ ] TCA 패턴을 엄격하게 준수한다.
- [ ] UndoManager API를 사용한다.
- [ ] 단위 테스트를 포함한다.

## Risk Mitigation
- **Primary Risk:** 잘못된 Undo/Redo로 인한 데이터 손상 또는 상태 불일치
- **Mitigation:** UndoManager 기반 등록, 대상 유효성 검사, busy 가드, 단위 테스트
- **Rollback Plan:** Undo/Redo 등록/실행을 비활성화하고 기존 파일 액션만 유지하도록 되돌린다
- **Note:** 리스크/롤백 상세는 개발 중 추가 검증 후 업데이트한다

## Definition of Done
- [ ] 모든 스토리 완료 및 수용 기준 충족
- [ ] 기존 기능 회귀 없음(수동/단위 테스트 확인)
- [ ] Undo/Redo 단위 테스트 통과
- [ ] 문서/메모 업데이트 완료

---

**Story Manager Handoff:**

"Please develop detailed user stories for this brownfield epic. Key considerations:

- This is an enhancement to an existing system running macOS SwiftUI + TCA + AppKit
- Integration points: FSItemsFeature, FSItemsOperationsFeature, FSItemClient, ContentPaneView, EditMenuCommands, FileManagerFeature (confirm if changes)
- Existing patterns to follow: strict TCA, current File Manager action flow
- Critical compatibility requirements: UndoManager API usage, no schema changes, minimal UI disruption
- Each story must include verification that existing functionality remains intact and unit tests for the feature

The epic should maintain system integrity while delivering Undo/Redo for entry actions."
