# VOY-112 Phase 0 — 시스템 프로퍼티 명명 정리

## 배경
- `shared/system_property_registry.json`의 `$kind` 값이 `mditem_registry`로 되어 있어 파일명/용어와 불일치했다.
- 앱/백엔드에서 사용하는 용어가 섞여 있어(시스템 프로퍼티 vs mditem) 가독성과 유지보수성이 떨어졌다.

## 목표
- 시스템 프로퍼티 레지스트리 명칭을 일관되게 `system_property`로 정리한다.
- Apple 공식 키(`kMDItem*`)는 그대로 유지한다.

## 상세 태스크
1) 레지스트리 메타 정리
   - `shared/system_property_registry.json`의 `$kind` 값을 `system_property_registry`로 변경
2) 백엔드 기대값 갱신
   - 레지스트리 구조 테스트의 `$kind` 기대값 정합화
3) macOS 앱 명칭 통일
   - `MDItemProperty`/`MDItemPropertyClient` → `SystemProperty`/`SystemPropertyClient`

## 산출물
- `shared/system_property_registry.json`
- `apps/backend/tests/test_system_property_registry.py`
- `apps/macos/Voyager/Voyager/Composer/Models/SystemProperty.swift`
- `apps/macos/Voyager/Voyager/Composer/Clients/SystemPropertyClient.swift`
- `apps/macos/Voyager/Voyager/Composer/Features/ConditionPropertyPickerFeature.swift`
- `apps/macos/Voyager/Voyager/Composer/Views/ConditionPropertyPickerView.swift`
- `apps/macos/Voyager/Voyager/Composer/Features/ComposerFeature.swift`
- `apps/macos/Voyager/Voyager/Composer/Utils/ConditionPropertyIconUtils.swift`

## 사이드이펙트 고려
- `$kind` 값 변경으로 레지스트리 검증 테스트가 실패할 수 있으므로 테스트 기대값을 함께 갱신해야 한다.
- kMDItem 계열 키는 Apple 정의에 맞추어 유지하며, 명칭 변경 대상이 아니다.

## 검증
- `cd apps/backend && uv run ruff format tests/test_system_property_registry.py`
- `cd apps/backend && uv run pytest tests/test_system_property_registry.py`
- `swiftformat --config apps/macos/Voyager/.swiftformat apps/macos/Voyager/Voyager`

## 커밋 분리
- `chore(shared): align system property registry kind`
- `test(backend): update registry kind expectation`
- `feat(macos): rename system property types`

## 롤백
- `$kind` 값을 `mditem_registry`로 되돌린다.
- 백엔드 테스트 기대값을 원복한다.
- 앱 타입/클라이언트 명칭을 `MDItemProperty` 계열로 복구한다.
