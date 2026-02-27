---
name: commit-message
description: Staged changes 기준으로 repo 컨벤션에 맞는 커밋 메시지 1개를 작성합니다.
compatibility: opencode
metadata:
    workflow: git
    output: commit-message
---

이 스킬은 "현재 staged(index) 변경"을 기준으로, repo 컨벤션/언어에 맞는 커밋 메시지를 정확히 1개 작성하기 위한 워크플로우입니다.

## 목표

- staged 변경만을 근거로 커밋 메시지 1개 생성
- repo 컨벤션(Conventional Commits/스코프/언어/구두점 등) 준수
- 변경의 "무엇"보다 "왜"가 드러나도록(필요 시) 짧은 본문으로 보강
- 시크릿/개인정보/키가 메시지에 포함되지 않도록 방지

## Hard rules

- 사실(ground truth)은 staged 변경만 사용합니다. unstaged 변경은 절대 언급하지 않습니다.
- 매 호출마다 최신 index 상태를 기준으로 staged 컨텍스트를 다시 수집합니다(이전 실행 결과 재사용 금지).
- 출력은 "커밋 메시지 텍스트"만. 설명/헤더/코드펜스/부연을 출력하지 않습니다.
- 출력/응답 형식은 반드시 `references/output-template.md`, `references/response-template.md`를 따릅니다.
- staged 파일이 2개 이상이면, subject는 반드시 "모든 staged 변경을 포괄"해야 합니다(한 파일만 설명하는 subject 금지).
- staged 변경이 여러 그룹이면, subject는 공유되는 의도를 대표해야 하며, 본문(허용되는 경우)에서 나머지 그룹을 짧게 커버합니다.
- staged 파일이 비어있으면 메시지를 지어내지 말고, "staged changes 없음"을 알려서 사용자가 stage 하도록 유도합니다.
- 본문을 작성할 때는 반드시 `- `로 시작하는 개조식 불릿만 사용합니다.

## 워크플로우

1) staged 컨텍스트 수집(항상 최신 index 기준)

```bash
python3 .agents/skills/commit-message/scripts/collect_staged_context.py
```

2) 출력된 컨텍스트만 근거로 커밋 메시지 1개를 작성

- 컨벤션 우선순위: 커밋 컨벤션 문서/commitlint/템플릿 > 최근 커밋 스타일 > 언어
- scope는 staged 파일 경로에서 추론하되, 애매하면 생략
- subject는 staged 변경 전체를 1줄로 포괄(여러 그룹이면 body로 보강)
- body는 허용되는 경우에만 추가하고, `- ` 불릿으로 "왜/영향/리스크" 중심으로 짧게

## Bundled Resources

이 스킬은 SKILL.md만으로 끝내지 않고, staged 컨텍스트 수집을 위한 스크립트를 함께 제공합니다.

- `scripts/collect_staged_context.py`
    - branch/이슈키 힌트, staged 파일/통계/요약, 패치(head+tail), 컨벤션 문서, 최근 커밋 스타일을 한 번에 출력
    - 실행(레포 루트 기준)

```bash
python3 .agents/skills/commit-message/scripts/collect_staged_context.py
```

패치가 너무 길어서 출력이 부담되면(컨텍스트 초과 위험), 라인 수를 줄입니다.

```bash
python3 .agents/skills/commit-message/scripts/collect_staged_context.py \
  --head-lines 600 \
  --tail-lines 600
```

- `references/output-template.md`
    - 커밋 메시지 출력 포맷 템플릿(subject/body)
    - 헤더-본문 이중 줄바꿈(빈 줄 2줄) 규칙 포함

- `references/response-template.md`
    - staged 비어 있음 등 예외 응답 템플릿

## 출력 형식(중요)

- 기본 출력/응답은 템플릿 파일을 우선 적용합니다.
- `references/output-template.md`: 정상 출력 템플릿
- `references/response-template.md`: 예외 응답 템플릿

## 금지

- API 키/토큰/개인정보 등 민감 정보가 메시지에 포함되면 안 됨
- 커밋 메시지로 구현 상세를 과도하게 나열하지 않음(핵심만)
