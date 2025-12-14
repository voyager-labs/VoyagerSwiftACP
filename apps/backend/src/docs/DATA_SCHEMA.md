# 파일 메타데이터 스키마

Voyager가 수집하는 파일 메타데이터의 전체 구조입니다.

---

## DB 스키마

### 테이블: `file_entries`

총 **24개 필드** + 2개 JSON 필드 = **26개 컬럼**

---

## 1. 경로 정보 (Path Identity)

파일의 위치와 이름 관련 정보

| 필드명 | 타입 | 인덱스 | 설명 | 예시 |
|--------|------|--------|------|------|
| `id` | INTEGER | PRIMARY | 고유 ID | 1540 |
| `path` | VARCHAR | UNIQUE | 파일 절대 경로 | `/Users/name/Downloads/file.pdf` |
| `dir_path` | VARCHAR | INDEX | 디렉토리 절대 경로 | `/Users/name/Downloads` |
| `name_full` | VARCHAR | INDEX | 파일명 (확장자 포함) | `file.pdf` |
| `name_stem` | VARCHAR | INDEX | 파일명 (확장자 제외) | `file` |
| `extension` | VARCHAR | INDEX | 확장자 | `.pdf` |
| `parent_dir_name` | VARCHAR | INDEX | 부모 디렉토리명 | `Downloads` |
| `depth_from_home` | INTEGER | - | 홈 디렉토리 기준 깊이 | 2 |
| `relative_path_from_home` | VARCHAR | - | 홈 기준 상대 경로 | `Downloads/file.pdf` |

**AI 검색 활용:**
- 파일명 검색 (`name_full`, `name_stem`)
- 확장자 필터링 (`extension`)
- 폴더별 검색 (`parent_dir_name`, `dir_path`)
- 경로 깊이 필터링 (`depth_from_home`)

---

## 2. 파일 속성 (File Properties)

파일의 물리적 속성과 타입 정보

| 필드명 | 타입 | 인덱스 | 설명 | 예시 |
|--------|------|--------|------|------|
| `size` | INTEGER | INDEX | 파일 크기 (바이트) | 7899210 |
| `dev_id` | INTEGER | UNIQUE* | 디바이스 ID | 16777234 |
| `inode` | INTEGER | UNIQUE* | inode 번호 | 12345678 |
| `owner_uid` | INTEGER | - | 소유자 사용자 ID | 501 |
| `owner_gid` | INTEGER | - | 소유자 그룹 ID | 20 |
| `uniform_type_identifier` | VARCHAR | INDEX | UTI (macOS 타입) | `public.jpeg` |
| `file_kind` | VARCHAR | INDEX | 파일 종류 (한글) | `JPEG 이미지` |
| `is_invisible` | BOOLEAN | INDEX | 숨김 파일 여부 | false |

*UNIQUE 제약조건: `(dev_id, inode)` 조합

**AI 검색 활용:**
- 파일 크기 범위 검색 (`size`)
- 파일 타입 분류 (`uniform_type_identifier`, `file_kind`)
- 숨김 파일 제외 (`is_invisible`)

---

## 3. 시간 정보 (Timestamps)

파일 생성/수정/사용 시간

| 필드명 | 타입 | 인덱스 | 설명 | 예시 |
|--------|------|--------|------|------|
| `creation_date` | DATETIME | - | 파일 시스템 생성 시간 | `2025-09-30T17:50:46` |
| `modification_date` | DATETIME | - | 파일 시스템 수정 시간 | `2025-09-30T17:50:47` |
| `content_creation_date` | DATETIME | - | 콘텐츠 생성 시간 | `2025-09-30T17:50:46` |
| `content_modification_date` | DATETIME | - | 콘텐츠 수정 시간 | `2025-09-30T17:50:47` |
| `added_date` | DATETIME | - | 파일 추가된 시간 | `2025-09-30T17:50:47` |
| `last_used_date` | DATETIME | - | 마지막 사용 시간 (nullable) | `2025-10-15T09:23:11` |
| `birthtime` | DATETIME | - | OS 생성 시간 (nullable) | `2025-09-30T17:50:46` |

**시간 구분:**
- `creation_date` / `modification_date`: 파일 시스템 레벨 시간
- `content_creation_date` / `content_modification_date`: 실제 콘텐츠 시간 (예: 사진 촬영 시간)
- `added_date`: macOS Spotlight 기준 추가 시간
- `last_used_date`: 마지막 열람/실행 시간

**AI 검색 활용:**
- 최근 수정 파일 (`modification_date`)
- 최근 사용 파일 (`last_used_date`)
- 날짜 범위 검색 (모든 날짜 필드)

---

## 4. JSON 원본 데이터

전체 메타데이터 보존 (SQLite JSON 컬럼)

| 필드명 | 타입 | 출처 | 설명 |
|--------|------|------|------|
| `original_stat` | JSON | `os.stat()` | 파일 시스템 물리적 정보 (모든 OS 공통) |
| `original_metadata` | JSON | macOS Spotlight | 파일 콘텐츠 의미적 정보 (macOS 전용) |

### 차이점 비교

| 구분 | `original_stat` | `original_metadata` |
|------|----------------|-------------------|
| **출처** | Python `os.stat()` | macOS `osxmetadata` |
| **범위** | 모든 OS 공통 | macOS 전용 |
| **정보 유형** | 파일 시스템 (물리적) | 파일 콘텐츠 (의미적) |
| **예시** | 크기, 권한, inode, 블록 수 | 이미지 해상도, 문서 제목, EXIF |
| **AI 활용** | 제한적 | 매우 유용 |

### `original_stat` 구조 예시 (파일 시스템)
```json
{
  "st_size": 7899210,          // 파일 크기 (바이트)
  "st_mode": 33188,            // 파일 권한 (0o100644)
  "st_ino": 12345678,          // inode 번호
  "st_dev": 16777234,          // 디바이스 ID
  "st_nlink": 1,               // 하드링크 개수
  "st_uid": 501,               // 소유자 UID
  "st_gid": 20,                // 그룹 GID
  "st_atime": 1729012345.123,  // 접근 시간 (Unix timestamp)
  "st_mtime": 1729012346.456,  // 수정 시간
  "st_ctime": 1729012346.789,  // 상태 변경 시간
  "st_birthtime": 1729012346.012, // 생성 시간 (macOS)
  "st_blksize": 4096,          // 블록 크기
  "st_blocks": 8,              // 할당된 블록 수
  "st_flags": 0,               // BSD 파일 플래그
  "st_gen": 0                  // 파일 세대 번호
}
```

**저장 이유:**
- 나중에 필요한 정보 추가 시 DB 스키마 변경 없이 사용 가능
- 블록 크기, 하드링크 등 현재 안 쓰는 정보 보존

### `original_metadata` 구조 예시 (macOS Spotlight)
```json
{
  // === 기본 정보 ===
  "kMDItemContentType": "public.jpeg",
  "kMDItemKind": "JPEG 이미지",
  "kMDItemFSSize": 7899210,

  // === 날짜 정보 (Spotlight 기준) ===
  "kMDItemFSCreationDate": "2025-09-30 17:50:46",
  "kMDItemFSContentChangeDate": "2025-09-30 17:50:47",
  "kMDItemContentCreationDate": "2025-09-30 17:50:46",
  "kMDItemContentModificationDate": "2025-09-30 17:50:47",
  "kMDItemDateAdded": "2025-09-30 17:50:47",
  "kMDItemLastUsedDate": "2025-10-15 09:23:11",

  // === 이미지 전용 메타데이터 ===
  "kMDItemPixelHeight": 3024,
  "kMDItemPixelWidth": 4032,
  "kMDItemColorSpace": "RGB",
  "kMDItemExposureTimeSeconds": 0.001,
  "kMDItemFNumber": 1.8,
  "kMDItemISOSpeed": 100,

  // === 문서 전용 메타데이터 ===
  "kMDItemAuthors": ["John Doe"],
  "kMDItemNumberOfPages": 42,
  "kMDItemTitle": "My Document",

  // === 미디어 전용 메타데이터 ===
  "kMDItemDurationSeconds": 180.5,
  "kMDItemCodecs": ["H.264", "AAC"],

  // === 다운로드 정보 ===
  "kMDItemWhereFroms": ["https://example.com/file.jpg"],
  "kMDItemDownloadedDate": "2025-10-15 09:20:00",

  // === Finder 태그 ===
  "kMDItemFinderTags": ["중요", "작업", "빨강"]
}
```

**저장 이유:**
- **파일 타입별로 다른 메타데이터** 보존 (이미지/문서/미디어)
- **AI 검색에 매우 유용**: 이미지 해상도, 문서 제목, 다운로드 출처 등
- **향후 확장**: DB 스키마 변경 없이 새로운 메타데이터 활용 가능
- **컨텍스트 정보**: 파일의 출처, 용도, 관계 정보 제공

---

## API 응답 형식

### \`GET /api/files/\` (목록 조회)

간단한 8개 필드 반환

\`\`\`json
{
  "count": 100,
  "offset": 0,
  "limit": 100,
  "items": [
    {
      "id": 1540,
      "path": "/Users/tacowasabii/Downloads/IMG_0964.JPG",
      "name": "IMG_0964.JPG",
      "size": 7899210,
      "extension": ".jpg",
      "file_kind": "JPEG 이미지",
      "creation_date": "2025-09-30T17:50:46",
      "modification_date": "2025-09-30T17:50:47"
    }
  ]
}
\`\`\`

### \`GET /api/files/{id}\` (상세 조회)

전체 20개 필드 반환 (JSON 필드 제외)

\`\`\`json
{
  "id": 1540,
  "path": "/Users/tacowasabii/Downloads/IMG_0964.JPG",
  "dir_path": "/Users/tacowasabii/Downloads",
  "name_full": "IMG_0964.JPG",
  "name_stem": "IMG_0964",
  "extension": ".jpg",
  "parent_dir_name": "Downloads",
  "depth_from_home": 2,
  "relative_path_from_home": "Downloads/IMG_0964.JPG",
  "size": 7899210,
  "uniform_type_identifier": "public.jpeg",
  "file_kind": "JPEG 이미지",
  "is_invisible": false,
  "creation_date": "2025-09-30T17:50:46",
  "modification_date": "2025-09-30T17:50:47",
  "content_creation_date": "2025-09-30T17:50:46",
  "content_modification_date": "2025-09-30T17:50:47",
  "added_date": "2025-09-30T17:50:47",
  "last_used_date": "2025-10-15T09:23:11",
  "owner_uid": 501,
  "owner_gid": 20
}
\`\`\`

### \`GET /api/files/stats\` (통계)

\`\`\`json
{
  "total_files": 1540,
  "total_size_bytes": 5678901234,
  "total_size_mb": 5416.32,
  "extension_stats": [
    {"extension": ".jpg", "count": 456},
    {"extension": ".pdf", "count": 345},
    {"extension": ".png", "count": 234}
  ]
}
\`\`\`

### \`GET /api/files/search?q=keyword\` (검색)

\`\`\`json
{
  "query": "IMG",
  "count": 50,
  "items": [
    {
      "id": 1540,
      "path": "/Users/tacowasabii/Downloads/IMG_0964.JPG",
      "name": "IMG_0964.JPG",
      "size": 7899210,
      "extension": ".jpg",
      "modification_date": "2025-09-30T17:50:47"
    }
  ]
}
\`\`\`

---

## 데이터 소스

### 1. Python \`os.stat()\`
- 파일 시스템 기본 정보
- 크기, inode, 권한, 타임스탬프

### 2. macOS Spotlight (\`osxmetadata\`)
- macOS 전용 메타데이터
- UTI, 파일 종류, 추가 날짜, 마지막 사용 날짜
- 이미지/문서/미디어 특화 정보

### 3. Python \`pathlib.Path\`
- 경로 파싱
- 파일명, 확장자, 디렉토리 구조

---

## AI 검색 활용 시나리오

### 1. 자연어 검색
\`\`\`
"최근 1주일 이내 수정된 PDF 파일"
→ extension = ".pdf" AND modification_date > (now - 7 days)
\`\`\`

### 2. 복합 조건
\`\`\`
"Downloads 폴더의 큰 이미지 파일"
→ parent_dir_name = "Downloads"
   AND extension IN (".jpg", ".png")
   AND size > 5MB
\`\`\`

### 3. 사용 패턴 분석
\`\`\`
"오랫동안 안 쓴 큰 파일들"
→ size > 100MB AND last_used_date < (now - 6 months)
\`\`\`

### 4. 중복 파일 탐지
\`\`\`
"같은 이름, 다른 위치"
→ GROUP BY name_full, size
\`\`\`

---

## 향후 확장 계획

### 추가 가능한 메타데이터

1. **벡터 임베딩**
   - 파일명 임베딩
   - 경로 임베딩
   - 의미론적 검색

2. **콘텐츠 분석**
   - 이미지 OCR 텍스트
   - PDF 텍스트 추출
   - 미디어 썸네일

3. **사용자 메타데이터**
   - 즐겨찾기
   - 태그
   - 메모

4. **관계 데이터**
   - 같은 프로젝트 파일 그룹
   - 연관 파일 링크

---

**버전**: 0.2.0
**최종 수정**: 2025-10-29
