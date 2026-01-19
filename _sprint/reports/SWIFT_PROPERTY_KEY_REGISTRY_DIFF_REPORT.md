# VOY-112 Swift ConditionMappingUtils vs property_key_registry.json 차이 분석

- 작성일: 2026-01-19
- 대상 파일:
  - apps/macos/Voyager/Voyager/Composer/Utils/ConditionMappingUtils.swift
  - apps/macos/Voyager/Shared/property_key_registry.json (shared/property_key_registry.json 동일)

## 요약
- 레지스트리 propertyKey 수: 26
- Swift propertyLabelToKey 수: 26
- Swift propertyKeyToCategory 수: 26
- propertyKey 커버리지 차이: 없음 (누락/초과 모두 0)
- 연산자 코드 차이: 없음
- SSOT 갭: ConditionMappingUtils가 레지스트리 label/category를 우선 사용 (로컬 매핑은 fallback)

## 변경 적용 사항
- property_key_registry.json에 label/category 필드 추가
- Swift 전용 operator(neq/empty/not_empty)를 supported_operators에 동기화
- ConditionMappingUtils가 레지스트리 label/category를 참조하도록 전환

## 상세 차이
### 1) propertyKey 커버리지
- 레지스트리에는 있으나 Swift 라벨 매핑에 없는 키: 없음
- 레지스트리에는 있으나 Swift 카테고리 매핑에 없는 키: 없음
- Swift 라벨 매핑에 있으나 레지스트리에 없는 키: 없음
- Swift 카테고리 매핑에 있으나 레지스트리에 없는 키: 없음

### 2) 연산자 코드
- 차이 없음

### 3) SSOT 관점에서의 분산
- 레지스트리에 label/category가 추가되어 Swift는 이를 우선 사용
- 로컬 매핑은 레지스트리 로딩 실패 시 fallback으로 유지됨

## 통합 매핑 스냅샷 (현재 상태)
| propertyKey | label | category | value_type | supported_operators | mapping |
| --- | --- | --- | --- | --- | --- |
| addedAt | Date added | System Metadata | date | eq, neq, gt, gte, lt, lte, between | db_field=added_date |
| audioBitRate | Audio bitrate | Audio | number | eq, neq, gt, gte, lt, lte | json_path=$.kMDItemAudioBitRate |
| audioChannelCount | Audio channels | Audio | number | eq, neq, in | json_path=$.kMDItemAudioChannelCount |
| audioSampleRate | Audio sample rate | Audio | number | eq, neq, gt, gte, lt, lte | json_path=$.kMDItemAudioSampleRate |
| colorSpace | Color space | Image | string | eq, neq, in, empty, not_empty | json_path=$.kMDItemColorSpace |
| contentCreatedAt | Content created | Content | date | eq, neq, gt, gte, lt, lte, between | db_field=content_creation_date |
| contentModifiedAt | Content modified | Content | date | eq, neq, gt, gte, lt, lte, between | db_field=content_modification_date |
| contentType | File type | System Metadata | string | eq, neq, contains, in, empty, not_empty | db_field=uniform_type_identifier |
| createdAt | Date created | System Metadata | date | eq, neq, gt, gte, lt, lte, between | db_field=creation_date |
| creator | Creator | Document | string | eq, neq, contains, empty, not_empty | json_path=$.kMDItemCreator |
| duration | Duration (sec) | Video | number | eq, neq, gt, gte, lt, lte, between | json_path=$.kMDItemDurationSeconds |
| extension | Extension | System Metadata | string | eq, neq, in, empty, not_empty | db_field=extension |
| hasAlphaChannel | Has alpha channel | Image | boolean | eq, neq | json_path=$.kMDItemHasAlphaChannel |
| isInvisible | Invisible | System Metadata | boolean | eq, neq | db_field=is_invisible |
| kind | File kind | System Metadata | string | eq, neq, contains, empty, not_empty | db_field=file_kind |
| lastUsedAt | Last used | System Metadata | date | eq, neq, gt, gte, lt, lte, between | db_field=last_used_date |
| latitude | Latitude | Location | number | eq, neq, gt, gte, lt, lte, between | json_path=$.kMDItemLatitude |
| longitude | Longitude | Location | number | eq, neq, gt, gte, lt, lte, between | json_path=$.kMDItemLongitude |
| modifiedAt | Date modified | System Metadata | date | eq, neq, gt, gte, lt, lte, between | db_field=modification_date |
| name | File name | System Metadata | string | eq, neq, contains, empty, not_empty | db_field=name_full |
| numberOfPages | Page count | Document | number | eq, neq, gt, gte, lt, lte, between | json_path=$.kMDItemNumberOfPages |
| pixelHeight | Pixel height | Image | number | eq, neq, gt, gte, lt, lte, between | json_path=$.kMDItemPixelHeight |
| pixelWidth | Pixel width | Image | number | eq, neq, gt, gte, lt, lte, between | json_path=$.kMDItemPixelWidth |
| size | File size | System Metadata | number | eq, neq, gt, gte, lt, lte, between | db_field=size |
| title | Title | Document | string | eq, neq, contains, empty, not_empty | json_path=$.kMDItemTitle |
| videoBitRate | Video bitrate | Video | number | eq, neq, gt, gte, lt, lte | json_path=$.kMDItemVideoBitRate |

## 동기화 필요 포인트
- 레지스트리와 Swift 모두 동일한 propertyKey 집합 유지 (현재 일치)
- UI 라벨/카테고리의 fallback 제거 여부 결정
- operator 정책 변경 시 Search DSL/백엔드 검증 규칙 동시 갱신 필요
