---
description: "CodeGraph MCP 사이드카 사용 가이드 — 호출 흐름, 영향 범위, 심볼 탐색 질의 방법."
alwaysApply: true
---

# CodeGraph 사용 가이드

## 개요

CodeGraph는 tree-sitter 기반 코드 인텔리전스 도구로, 에이전트가 호출 흐름, 영향 범위, 심볼 탐색을 MCP 쿼리로 수행할 수 있게 한다.

선택적 MCP 사이드카다. 설치하지 않아도 기본 작업에 영향이 없다.

- 설치: `just setup` 또는 `npm install` (package.json devDependency)
- 실행: `npx codegraph` (node_modules/.bin에서 실행)
- 편의 명령: `just codegraph-status`, `just codegraph-init`, `just codegraph-reindex`

## 언제 CodeGraph를 쓰는가

SourceKit-LSP와 CodeGraph는 보완 관계다. 둘 다 쓸 수 있는 작업도 있지만, 각자 명확한 강점이 있다.

| 상황                         | SourceKit-LSP      | CodeGraph            |
| ---------------------------- | ------------------ | -------------------- |
| 정의 이동 / 참조 찾기        | O (에디터에서)     | X                    |
| 코드 완성                    | O                  | X                    |
| "이 함수를 호출하는 모든 곳" | 느림 (에디터 세션) | O (callers)          |
| "A에서 B까지 호출 경로"      | 불가               | O (trace)            |
| "이 변경의 영향 범위"        | 제한적             | O (impact)           |
| "이 모듈 구조가 어떻게 돼?"  | 불가               | O (explore/context)  |
| FastAPI 라우트 인식          | X                  | O                    |
| Swift 타입 정확도            | O (컴파일러 수준)  | ~ (tree-sitter 수준) |

## MCP 도구 목록

| 도구                | 설명                            |
| ------------------- | ------------------------------- |
| `codegraph_search`  | 심볼/파일 이름 검색             |
| `codegraph_context` | 특정 심볼의 주변 컨텍스트 반환  |
| `codegraph_trace`   | A에서 B까지 호출 경로 추적      |
| `codegraph_callers` | 특정 심볼을 호출하는 모든 위치  |
| `codegraph_callees` | 특정 심볜이 호출하는 모든 대상  |
| `codegraph_impact`  | 특정 심볼 변경의 영향 범위 분석 |
| `codegraph_explore` | 모듈/패키지 구조 탐색           |
| `codegraph_node`    | 특정 노드의 상세 정보           |
| `codegraph_files`   | 인덱싱된 파일 목록              |
| `codegraph_status`  | 인덱스 상태 확인                |

## Voyager 특화 쿼리 예시

### TCA 리듀서 호출 체인

"이 리듀서의 Action이 어디서 호출되나?"

```
codegraph_callers("ComposerSaveReducer.Action")
```

### FastAPI 라우트 추적

"이 엔드포인트의 핸들러 체인은?"

```
codegraph_trace("search_router", "collection_search")
```

### 패키지 의존 분석

"이 패키지를 사용하는 다른 패키지는?"

```
codegraph_impact("VoyagerFeaturesComposer")
```

### 크로스 언어 추적

"Swift에서 Python 백엔드 API 호출 경로"

```
codegraph_trace("SearchGateway", "search_router")
```

## 제한사항

- ObjC 브리지 헤더는 부분적 지원
- 1MB 이상 파일은 인덱싱 제외
- tree-sitter 기반으로 컴파일러 수준 타입 추론 불가 (제네릭 복잡도 등)
- 인덱스는 수동 갱신 (`just codegraph-reindex`)
- Swift macro 속성은 추적 불가

## 유지 관리

- 인덱스 재구축: `just codegraph-reindex`
- 인덱스 삭제: `just codegraph-clean`
- 재초기화: `just codegraph-clean && just codegraph-init`
- 인덱스 위치: `.codegraph/` (gitignored)
