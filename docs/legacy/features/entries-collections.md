# 엔트리/컬렉션

## 개요

Voyager의 탐색/검색 UI는 크게 두 개념 위에 올라갑니다.

- Entry: 파일/폴더 1개를 나타내는 "아이템(메타데이터)" 단위
- Collection: 검색 컨텍스트(query + scopes + conditions)를 묶어 재사용/저장하는 단위

즉, 사용자는 "폴더를 탐색"하거나 "검색(컬렉션) 결과를 탐색"하는데,
둘 다 화면에서는 결국 "엔트리 목록"으로 렌더링됩니다.

관련 코드

- `apps/macos/Voyager/Voyager/05_Entities/Entry/Reducer/EntriesFeature.swift`
- `apps/macos/Voyager/Voyager/05_Entities/Entry/Reducer/EntriesOperationsFeature.swift`
- `apps/macos/Voyager/Voyager/05_Entities/Collection/Model/CollectionContext.swift`
- `apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`

---

## 1) Entry(파일 아이템)

Entry는 다음 성격을 가집니다.

- 파일 시스템의 "현재 상태"를 표현(이름/경로/크기/날짜/종류 등)
- 인덱싱(Helper)이 수집한 메타데이터 기반으로 검색 결과를 구성
- UI 상호작용(선택/미리보기/드래그/드롭/컨텍스트 메뉴)을 지원

### 1.1 EntriesFeature 역할

`EntriesFeature`는 파일 목록과 선택 상태를 관리합니다.

주요 책임

- 현재 경로의 아이템 로드/리로드
- 선택(단일/다중/범위), 스크롤 포커스
- 정렬/그룹핑 및 그룹 접기
- 파일 시스템 변경 감시(리로드 트리거)
- 파일 작업 요청을 `EntriesOperationsFeature`로 위임

관련 코드

- `apps/macos/Voyager/Voyager/05_Entities/Entry/Reducer/EntriesFeature.swift`

### 1.2 파일 작업(Operations)

파일 작업은 `EntriesOperationsFeature`가 담당합니다.

- Open/QuickLook/Info/Share/Reveal
- New Folder/Rename
- Copy/Cut/Paste/Duplicate
- Trash/Delete/Put Back/Empty Trash
- Compress/Extract
- Tags 변경

작업 상태는 파일별로 추적되어 중복 실행/Undo 충돌을 줄입니다.

관련 코드

- `apps/macos/Voyager/Voyager/05_Entities/Entry/Reducer/EntriesOperationsFeature.swift`

---

## 2) Collection(검색 컨텍스트)

Collection은 "검색 쿼리 + 스코프 + 조건"을 하나의 컨텍스트로 묶는 모델입니다.

- `CollectionContext`: `{ query, scopes, conditions }`

### 2.1 왜 Collection이 필요한가

- 사용자는 동일한 검색을 반복합니다(예: "다운로드 폴더에서 최근 큰 PDF")
- 매번 조건을 다시 만들기보다 "컬렉션"으로 저장하면 재사용이 쉬워집니다.
- 검색은 필터/정렬/레이아웃까지 포함할 때 "상태"의 성격이 강합니다.

관련 코드

- `apps/macos/Voyager/Voyager/05_Entities/Collection/Model/CollectionContext.swift`

---

## 3) 컬렉션 파일(.voycoll)

컬렉션은 파일로 저장할 수 있습니다.

### 3.1 포맷

- 확장자: `.voycoll`
- 내부 저장: "패키지(디렉터리)"로 저장하여 Finder에서 컬렉션 파일처럼 보이게 함
  - 패키지 내부 payload 파일명: `collection.plist`
- payload 인코딩: `PropertyListEncoder`의 `.binary` 포맷
- 레거시 호환: 과거에 단일 파일로 저장된 `.voycoll`도 읽기 가능

관련 코드

- `apps/macos/Voyager/Voyager/05_Entities/Collection/Api/CollectionFileClient.swift`

### 3.2 저장되는 데이터

파일에는 단순 검색 컨텍스트뿐 아니라 "표시 상태"도 함께 저장됩니다.

- query/scopes/conditions
- 정렬 키/정렬 순서
- 보기 레이아웃(list/grid 등)
- 앱 버전/생성 시각/갱신 시각

관련 코드

- `apps/macos/Voyager/Voyager/05_Entities/Collection/Model/VoyagerCollectionFile.swift`

조건 인코딩 주의

- 파일 내 JSON key는 `operator`를 사용합니다.
  - 모델 필드는 `operatorCode`지만 CodingKeys에서 `operator`로 매핑됩니다.

---

## 4) 저장 UX(어디서, 어떻게 Save가 트리거되는가)

컬렉션 저장은 `CollectionFeature`가 담당합니다.

- 저장 요청은 FileManager에서 발생
- 저장 시점에 "검색/필터 로딩 중"이면 저장을 막아, 불완전 상태 저장을 방지
- "현재 컬렉션"이 비어 있으면(쿼리/스코프/조건이 모두 없음) 저장을 막고 안내

저장 경로 선택

- SavePanel의 초기 디렉터리 우선순위
  1) scopes가 1개인 경우 그 scope 디렉터리
  2) 마지막 저장 디렉터리(`SettingsKeys.lastCollectionSaveDirectory`)
  3) 홈 디렉터리

관련 코드

- `apps/macos/Voyager/Voyager/02_Pages/FileManager/Reducer/FileManagerFeature.swift`
- `apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
- `apps/macos/Voyager/Voyager/05_Entities/Settings/Config/SettingsKeys.swift`

---

## QA 체크리스트

- 일반 폴더 탐색에서 엔트리 목록이 정상 로드/리로드되는가
- 파일 작업(복사/이동/삭제 등)이 중복 실행/충돌 없이 동작하는가
- 컬렉션 모드에서 검색 결과가 표시되고, 모드를 끄면 일반 목록으로 복귀하는가
- `.voycoll` 저장 시 패키지 디렉터리로 생성되고 `collection.plist`가 들어있는가
- 레거시(단일 파일) `.voycoll`도 열 수 있는가
- SavePanel 기본 디렉터리 우선순위가 기대대로 동작하는가
