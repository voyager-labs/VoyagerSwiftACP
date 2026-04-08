# Extract Audio Properties

## Metadata

| Field            | Value                                                                                                                                       |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Interaction ID   | EIX-010-extract_audio_properties                                                                                                            |
| Interaction Type | background                                                                                                                                  |
| Feature          | Extract Audio Properties                                                                                                                    |
| Category Key     | EIX                                                                                                                                         |
| Feature ID       | EIX-010                                                                                                                                     |
| Status           | 아이디어                                                                                                                                    |
| Summary          | 오디오 Entry에서 세션 타입(회의/인터뷰/발표 등)·길이·화자 수·핵심 키포인트·요약 등 오디오 관련 자동 프로퍼티를 추출해 Entry 프로퍼티로 저장 |
| Related Region   | -                                                                                                                                           |
| Menu             | -                                                                                                                                           |
| Shortcut         | -                                                                                                                                           |

## Preconditions

- <<AI>> 대상 Entry가 오디오·음성 계열 포맷으로 분류된 상태
- <<AI>> 오디오 프로퍼티 추출 파이프라인이 활성화된 상태
- <<AI>> 대상 Entry를 읽을 수 있는 권한이 확보된 상태

## Edge Cases

- <<AI>> 오디오 파일이 손상되었거나 디코딩이 실패하는 경우
- <<AI>> 길이가 매우 길어 전사·요약 단계를 분할 처리해야 하는 경우
- <<AI>> 언어 감지 실패 또는 다국어 혼합으로 요약 품질이 불안정한 경우

## Acceptance Criteria

- [ ] <<AI>> 대상 Entry가 오디오 포맷인 상태일 때, 시스템이 추출을 수행하면, 세션 타입·길이·화자
      수·키포인트·요약 등 자동 프로퍼티를 저장함.
- [ ] <<AI>> 추출이 완료된 상태일 때, 사용자가 해당 Entry를 조회하면, 추출된 프로퍼티를 검색·필터
      조건으로 활용할 수 있게 함.
- [ ] <<AI>> 추출이 실패한 상태일 때, 시스템이 실패를 기록하면, 실패 원인과 대상 Entry를 오류 상세로
      조회 가능하게 함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `92`
