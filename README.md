# Voyager 문서 SSOT

이 레포지토리는 Voyager의 기획/문서 자료를 위한 단일 SSOT(Single Source of Truth)로 운영합니다.
변경은 GitHub PR 기반으로 진행하여 리뷰, diff, 변경 이력(blame)을 남기는 것을 기본으로 합니다.

## 시작하기

- 제품 기획/문서 진입점: `01_PRODUCT_THESIS/index.md`
- 페르소나: `02_USER_PERSONA/index.md`
- 정보 구조(IA) 테이블: `03_INFORMATION_ARCHITECTURE/`
- 기능 인벤토리: `04_FEATURE_INVENTORY/`
- 기능 스펙: `05_FEATURE_SPECS/`
- 유즈케이스: `06_USE_CASES/index.md`

## 운영 규칙

운영 규칙과 포맷 규칙은 `META/README.md`에 모읍니다.

## 다른 레포에서 이 문서를 subtree로 포함하기

이 레포를 다른 개발 레포(예: 앱 레포)에서 하위 폴더로 그대로 포함하려면 `git subtree`를 사용합니다.
서브모듈과 달리, 일반 `git clone`만으로도 문서 파일이 실제로 포함되어 검색/에이전트 처리에 유리합니다.

### 최초 1회 추가

```bash
# 예시: 개발 레포의 docs/voyager-docs/ 경로로 포함
git subtree add --prefix=docs/voyager-docs <DOCS_REPO_URL> main --squash
```

원격을 등록해두면 업데이트가 편합니다.

```bash
git remote add voyager-docs <DOCS_REPO_URL>
git fetch voyager-docs
git subtree add --prefix=docs/voyager-docs voyager-docs main --squash
```

### 업데이트(문서 레포에서 변경된 내용을 가져오기)

```bash
git subtree pull --prefix=docs/voyager-docs <DOCS_REPO_URL> main --squash

# 또는 remote 등록을 해둔 경우
git subtree pull --prefix=docs/voyager-docs voyager-docs main --squash
```

### (옵션) 변경을 문서 레포로 다시 밀어넣기

가능은 하지만, 충돌/운영비를 줄이려면 **문서 레포에서만 수정하고** 개발 레포에서는 pull만 하는(one-way) 운영을 권장합니다.

```bash
git subtree push --prefix=docs/voyager-docs <DOCS_REPO_URL> main
```

### 운영 팁

- `--squash`를 쓰면 개발 레포 히스토리가 문서 커밋으로 과도하게 오염되는 것을 줄일 수 있습니다.
- subtree로 포함된 경로(`docs/voyager-docs/`)는 개발 레포에서 직접 수정하지 않는 규칙을 두는 것이 안전합니다.
- 새로 클론한 환경에서는 `git remote add ...`로 등록한 리모트가 자동으로 생기지 않을 수 있습니다(필요 시 다시 추가).

### 다운스트림 업데이트 PR 자동 생성(GitHub Actions)

이 레포에는 다운스트림(서브트리 소비자) 레포로 업데이트 PR을 자동 생성하는 워크플로가 포함되어 있습니다.

- 워크플로 파일: `.github/workflows/sync-subtree-prs.yml`
- 대상 레포 설정: `.github/downstreams.json`

`downstreams.json`에서 `enabled: true`인 항목만 처리합니다.

```json
{
  "defaults": {
    "base_branch": "main",
    "upstream_branch": "main"
  },
  "downstreams": [
    {
      "enabled": true,
      "repository": "voyager-labs/your-downstream-repo",
      "prefix": "docs/voyager-docs",
      "base_branch": "main",
      "upstream_branch": "main"
    }
  ]
}
```

필수 시크릿:

- `DOWNSTREAM_SYNC_TOKEN`: 다운스트림 레포에 push/PR 생성 권한이 있는 토큰
  - 권장 권한: `contents:write`, `pull-requests:write`

동작 방식:

1. 이 레포 `main`에 push(또는 수동 실행) 시 워크플로 실행
2. 각 다운스트림에서 `git subtree pull --prefix=<prefix> ... --squash` 수행
3. 변경이 있으면 브랜치를 push하고 PR을 생성/업데이트

주의:

- 대상 다운스트림은 해당 `prefix`에 대해 최초 `git subtree add`가 이미 완료되어 있어야 합니다.
- `enabled: true`로 켜기 전, `repository`와 `prefix`가 정확한지 먼저 검증하세요.

## 어디에 무엇을 둘지

- 제품 기획/문서: 이 레포에서 관리합니다.
- 구현 상세(깊은 기술 문서, 런북, 코드 레벨 의사결정): 각 개발 레포에서 관리하고, 필요할 때 여기에서 링크로 참조합니다.

## 다음 작업(추천)

- 최상위 인덱스(예: `INDEX.md`)를 추가해 탐색 UX를 고정합니다.
