"""방식 2: LLM 전담 (LLM이 모든 것 처리)

LLM이 레지스트리를 참조하여
자연어 분석 + SQL 생성을 모두 수행합니다.
"""

from typing import Any

from core.llm.llm_provider import LLMProvider
from core.metadata.mditem_registry import get_indexed_attributes, get_json_attributes


class LLMOnlyQueryConverter:
    """방식 2: LLM이 모든 것 담당"""

    def __init__(self, llm_provider: LLMProvider):
        self.client = llm_provider
        self.system_prompt = self._build_system_prompt()

    def _build_system_prompt(self) -> str:
        """LLM 프롬프트 생성 (SQL 직접 생성) - 전체 레지스트리 포함"""
        indexed = get_indexed_attributes()
        json_attrs = get_json_attributes()

        # DB 컬럼 정보 (10개 전체)
        db_fields_info = []
        for key, attr in indexed.items():
            if attr.db_field:
                aliases = ", ".join(attr.search_aliases[:3])
                examples_str = str(attr.examples[0])
                type_upper = attr.type.value.upper()
                db_fields_info.append(
                    f"  - {attr.db_field} ({type_upper}) - {attr.description}\n"
                    f"    검색어: {aliases}\n"
                    f"    예시: {attr.db_field} = {repr(examples_str) if attr.type.value == 'string' else examples_str}"
                )

        # JSON 필드 정보 (30개 전체)
        json_fields_info = []
        for key, attr in json_attrs.items():
            aliases = ", ".join(attr.search_aliases[:3])
            type_upper = attr.type.value.upper()

            # CAST 타입 결정
            if attr.type.value == "number":
                cast_type = "INTEGER"
            elif attr.type.value == "string":
                cast_type = "TEXT"
            elif attr.type.value == "boolean":
                cast_type = "INTEGER"
            elif attr.type.value == "date":
                cast_type = "TEXT"
            else:
                cast_type = "TEXT"

            json_fields_info.append(
                f"  - {key} ({type_upper}) - {attr.description}\n"
                f"    검색어: {aliases}\n"
                f"    사용법: CAST(json_extract(original_metadata, '$.{key}') AS {cast_type}) [연산자] [값]"
            )

        return f"""당신은 파일 검색을 위한 SQL 생성 전문가입니다.
자연어를 SQLite WHERE절로 변환하세요.

중요 규칙:
1. WHERE 키워드 없이 조건만 출력
2. 조건은 최대 3개까지만
3. 조건 3개 초과 시: "ERROR: 조건이 3개를 초과합니다" 출력
4. 반드시 아래 레지스트리에 있는 속성만 사용 (총 40개)

=== DB 컬럼 - 빠른 검색 (10개) ===

{chr(10).join(db_fields_info)}

=== JSON 필드 - 느린 검색 (30개) ===

{chr(10).join(json_fields_info)}

=== SQL 생성 규칙 ===

1. DB 컬럼은 직접 사용:
   예: size > 10485760
   예: extension = 'pdf'
   예: modification_date > date('now', '-7 days')

2. JSON 필드는 json_extract + CAST:
   - 숫자: CAST(json_extract(original_metadata, '$.kMDItemPixelHeight') AS INTEGER) >= 1080
   - 문자열: CAST(json_extract(original_metadata, '$.kMDItemTitle') AS TEXT) LIKE '%report%'
   - Boolean: CAST(json_extract(original_metadata, '$.kMDItemHasAlphaChannel') AS INTEGER) = 1

3. 문자열 값은 작은따옴표:
   예: extension = 'pdf'
   예: file_kind = 'PDF 문서'

4. 확장자는 점(.) 없이:
   예: extension = 'pdf' (O)
   예: extension = '.pdf' (X)

5. 날짜 함수:
   - 오늘: date('now')
   - 어제: date('now', '-1 day')
   - 최근 7일: date('now', '-7 days')
   - 최근 30일: date('now', '-30 days')

6. 크기 변환:
   - 1 KB = 1024
   - 1 MB = 1048576
   - 10 MB = 10485760
   - 100 MB = 104857600
   - 1 GB = 1073741824

7. 복수 값은 IN:
   예: extension IN ('jpg', 'jpeg', 'png', 'heic')

=== 예시 ===

입력: "10MB 이상 PDF 파일"
분석: 2개 조건 (크기, 확장자)
출력: size > 10485760 AND extension = 'pdf'

입력: "최근 7일 1080p 이상 영상"
분석: 3개 조건 (날짜, 해상도, 확장자)
출력: modification_date > date('now', '-7 days') AND CAST(json_extract(original_metadata, '$.kMDItemPixelHeight') AS INTEGER) >= 1080 AND extension IN ('mp4', 'mov', 'avi')

입력: "클래식 음악 44.1kHz"
분석: 2개 조건 (장르, 샘플레이트)
출력: CAST(json_extract(original_metadata, '$.kMDItemMusicalGenre') AS TEXT) = 'Classical' AND CAST(json_extract(original_metadata, '$.kMDItemAudioSampleRate') AS INTEGER) = 44100

입력: "투명도 있는 PNG 이미지"
분석: 2개 조건 (알파채널, 확장자)
출력: CAST(json_extract(original_metadata, '$.kMDItemHasAlphaChannel') AS INTEGER) = 1 AND extension = 'png'

입력: "10분 이상 비디오"
분석: 2개 조건 (재생시간, 확장자)
출력: CAST(json_extract(original_metadata, '$.kMDItemDurationSeconds') AS INTEGER) >= 600 AND extension IN ('mp4', 'mov', 'avi')

입력: "4K, 10분, MP4, 최근 7일, 10MB" (5개 조건)
분석: 5개 조건 - 초과!
출력: ERROR: 조건이 3개를 초과합니다

입력: "Downloads 폴더의 이미지"
분석: 2개 조건 (경로, 확장자)
출력: parent_dir_name = 'Downloads' AND extension IN ('jpg', 'jpeg', 'png', 'heic')

조건만 출력하고 설명은 하지 마세요!"""

    async def convert(self, query: str) -> str | None:
        """자연어 → SQL WHERE절"""
        try:
            response = await self.client.generate(
                prompt=f"입력: {query}\n출력:", system=self.system_prompt
            )

            sql = response.strip()

            # 에러 체크
            if sql.startswith("ERROR:"):
                print(f"[방식 2] {sql}")
                return None

            if not sql or sql.lower() in ["null", "none", ""]:
                return None

            return sql

        except Exception as e:
            print(f"[방식 2] 변환 실패: {e}")
            return None

    async def convert_with_metadata(self, query: str) -> dict[str, Any]:
        """변환 + 메타데이터"""
        sql = await self.convert(query)

        return {
            "method": "llm_only",
            "description": "LLM이 레지스트리 참조하여 직접 SQL 생성",
            "query": query,
            "sql": sql,
            "success": sql is not None,
            "steps": ["1. LLM이 레지스트리 참조", "2. LLM이 직접 SQL 생성"],
            "registry_coverage": "40개 전체 속성 (DB 10개 + JSON 30개)",
        }
