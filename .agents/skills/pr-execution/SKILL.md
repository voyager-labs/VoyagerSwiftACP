---
name: pr-execution
description: Linear 이슈 기반으로 PR 제목/본문/검증/체크리스트를 일관된 형식으로 작성·갱신하는 워크플로우입니다. "PR 만들어줘", "PR 본문 업데이트", "커밋 추가됐으니 PR 반영" 같은 요청에서 사용합니다.
compatibility: opencode
metadata:
  workflow: pr
  output: pr-body
---

# Pr Execution

## Overview

이 스킬은 현재 브랜치 변경 이력, 검증 결과, Linear 이슈 문맥을 모아서 PR 본문을 촘촘하게 작성/갱신합니다.
특히 "기존 PR에 새 커밋이 추가된 상황"에서 커밋 목록과 모듈별 변경 설명을 동기화하는 데 최적화되어 있습니다.

## Workflow

PR 작업은 아래 순서로 진행합니다.

1) 컨텍스트 수집
- 현재 브랜치 기준 커밋 범위를 확인합니다.
  - `git log --oneline origin/develop..HEAD`
  - `git diff --name-status origin/develop...HEAD`
- 현재 PR 상태를 확인합니다.
  - `gh pr view <PR_NUMBER> --json title,body,commits,baseRefName,headRefName`
- PR 본문의 커밋 목록/모듈 설명이 실제 커밋 범위와 일치하는지 확인합니다.

2) 제목 형식 강제
- PR 제목은 반드시 아래 형식을 따릅니다.
  - `[<Linear Issue ids...>] {PR 요약 주제}`
- 예시:
  - `[VOY-164] macOS 런타임의 로컬 백엔드 결합 제거 및 Helper/XPC 구조 정리`

3) 본문 작성/갱신
- 본문은 `references/pr-body-template-ko.md`의 섹션 순서를 유지합니다.
- 커밋이 추가되면 반드시 다음을 동기화합니다.
  - "변경 범위(커밋 단위)" 목록
  - "어디가 어떻게 바뀌었는지" 모듈별 상세
  - 검증 결과(테스트/타입체크/빌드 상태)
- 모듈 설명은 파일 경로를 포함해 구체적으로 작성합니다.

4) 검증 명령 반영
- 실제 수행한 검증만 PR 본문에 기록합니다.
- 기본 검증 세트는 `references/validation-commands.md`를 따릅니다.
- 실패가 있으면 "원인 + 범위 + 후속 액션"을 명시합니다.

5) 품질 게이트
- 아래 조건을 만족할 때만 PR 본문 업데이트를 완료합니다.
  - PR의 실제 커밋 목록과 본문 커밋 목록이 동일함
  - 제목 형식이 `[Issue] Summary` 규칙을 만족함
  - 모듈별 변경 설명에 누락된 핵심 변경(추가/삭제/이행)이 없음
  - 검증 섹션이 최신 실행 결과를 반영함

## Linear 연계 규칙

- 본문 상단에서 Linear 링크를 명시합니다.
  - `- Linear 이슈: https://linear.app/.../VOY-XXX/...`
- 커밋/모듈 설명은 Linear 원문을 복붙하지 않고, "실제 변경된 코드" 기준으로 작성합니다.
- Linear 요구사항과 실제 diff가 다르면, "이번 PR에서 반영된 범위"와 "후속 트랙"을 분리해 적습니다.

## 커밋 추가 시 갱신 규칙

기존 PR 이후 새 커밋이 들어오면 반드시 아래를 수행합니다.

1) 새 커밋 식별
- `git log --oneline origin/develop..HEAD`로 현재 범위를 추출
- PR 본문 "변경 범위(커밋 단위)"와 비교

2) 영향 분석
- 각 새 커밋에 대해 파일 목록을 확인
  - `git show --name-status --pretty=format:'COMMIT %h %s' <new-commit>`
- 기능 변경/문서 변경/인프라 변경을 구분

3) 본문 반영
- 커밋 목록에 새 커밋 추가
- 모듈별 섹션에 변경 내용과 의도 반영
- 검증 섹션 재실행/재기록

## 출력 형식

- 최종 결과는 "실제 PR 본문"으로 바로 적용 가능한 한국어 markdown이어야 합니다.
- 구현 세부를 빠뜨리지 않되, 모듈 단위로 정렬합니다.
- 표를 강제하지 않습니다. (요청 시만 사용)

## References

- PR 본문 템플릿: `references/pr-body-template-ko.md`
- 검증 명령/기록 규칙: `references/validation-commands.md`

## Resources

This skill includes example resource directories that demonstrate how to organize different types of bundled resources:

### scripts/
Executable code (Python/Bash/etc.) that can be run directly to perform specific operations.

**Examples from other skills:**
- PDF skill: `fill_fillable_fields.py`, `extract_form_field_info.py` - utilities for PDF manipulation
- DOCX skill: `document.py`, `utilities.py` - Python modules for document processing

**Appropriate for:** Python scripts, shell scripts, or any executable code that performs automation, data processing, or specific operations.

**Note:** Scripts may be executed without loading into context, but can still be read by Claude for patching or environment adjustments.

### references/
Documentation and reference material intended to be loaded into context to inform Claude's process and thinking.

**Examples from other skills:**
- Product management: `communication.md`, `context_building.md` - detailed workflow guides
- BigQuery: API reference documentation and query examples
- Finance: Schema documentation, company policies

**Appropriate for:** In-depth documentation, API references, database schemas, comprehensive guides, or any detailed information that Claude should reference while working.

### assets/
Files not intended to be loaded into context, but rather used within the output Claude produces.

**Examples from other skills:**
- Brand styling: PowerPoint template files (.pptx), logo files
- Frontend builder: HTML/React boilerplate project directories
- Typography: Font files (.ttf, .woff2)

**Appropriate for:** Templates, boilerplate code, document templates, images, icons, fonts, or any files meant to be copied or used in the final output.

---

**Any unneeded directories can be deleted.** Not every skill requires all three types of resources.
