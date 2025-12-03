"""방식 2: LLM 전담 (LLM이 모든 것 처리)

LLM이 레지스트리를 참조하여
자연어 분석 + SQL 생성을 모두 수행합니다.
"""

from typing import Any

from pydantic import BaseModel, Field

from core.llm.llm_provider import LLMProvider
from core.metadata.mditem_registry import get_indexed_attributes, get_json_attributes


class SQLConditions(BaseModel):
    """SQL WHERE절 조건 출력 스키마"""

    conditions: str = Field(description="SQL WHERE 조건절 (최대 4개, WHERE 키워드 제외)")
    error: str | None = Field(None, description="에러 메시지 (조건 4개 초과 시)")


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

🚨 절대 규칙 (반드시 지켜야 함):
1. WHERE 키워드 없이 조건만 출력
2. 조건은 최대 4개까지만
3. 조건 4개 초과 시: "ERROR: 조건이 4개를 초과합니다" 출력
4. 반드시 아래에 있는 속성만 사용
5. ⚠️ 없는 필드는 절대 사용하지 마세요! (name, filename 등 없음)
6. ⚠️ date() 함수는 절대 따옴표로 감싸지 마세요!
7. ⚠️ 설명, 주석, 부가 설명을 절대 추가하지 마세요! SQL 조건만 출력!

=== 추가 DB 컬럼 (중요!) ===

  - name_full (STRING) - 파일 이름 (확장자 포함)
    검색어: 파일명, 이름
    예시: name_full LIKE '%report%'
    ⚠️ 'name' 컬럼은 없습니다! 반드시 'name_full' 사용!

  - parent_dir_name (STRING) - 현재 파일이 있는 폴더 이름
    검색어: 폴더, 디렉토리, 위치
    예시: parent_dir_name = 'Downloads'
    예시: parent_dir_name IN ('Downloads', 'Documents')
    ⚠️ 폴더 위치 검색은 반드시 parent_dir_name 사용!
    ⚠️ kMDItemWhereFroms는 다운로드 URL 출처이므로 폴더 검색에 사용하지 마세요!

  - extension (STRING) - 파일 확장자 (점 없이)
    예시: extension = 'pdf'
    예시: extension IN ('jpg', 'jpeg', 'png')

=== DB 컬럼 - 빠른 검색 ===

{chr(10).join(db_fields_info)}

=== JSON 필드 - 느린 검색 ===

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

5. 날짜 함수 (⚠️ 절대 쿼팅하지 마세요):
   ✅ 올바름: modification_date > date('now', '-7 days')
   ❌ 틀림: modification_date > 'date('now', '-7 days')'

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

8. "다운로드" 관련 (⚠️ 중요):
   - kMDItemDownloadedDate는 존재하지 않습니다!
   - ✅ 대신 added_date를 사용하세요
   - 예: added_date > date('now', '-1 day')

=== 올바른 예시 ===

입력: "10MB 이상 PDF 파일"
출력: size > 10485760 AND extension = 'pdf'

입력: "어제 다운로드한 파일"
출력: added_date > date('now', '-1 day')

입력: "최근 7일 1080p 이상 영상"
출력: modification_date > date('now', '-7 days') AND CAST(json_extract(original_metadata, '$.kMDItemPixelHeight') AS INTEGER) >= 1080 AND extension IN ('mp4', 'mov', 'avi')

입력: "Downloads 폴더의 이미지"
출력: parent_dir_name = 'Downloads' AND extension IN ('jpg', 'jpeg', 'png', 'heic')

입력: "Downloads 또는 Documents 폴더의 파일"
출력: parent_dir_name IN ('Downloads', 'Documents')

입력: "파일명에 report가 포함된 PDF"
출력: name_full LIKE '%report%' AND extension = 'pdf'

입력: "파일명에 공백이 있는 PDF"
출력: name_full LIKE '% %' AND extension = 'pdf'

입력: "암호화된 PDF"
출력: extension = 'pdf' AND CAST(json_extract(original_metadata, '$.kMDItemSecurityMethod') AS TEXT) IS NOT NULL

입력: "4K, 10분, MP4, 최근 7일, 10MB" (5개 조건)
출력: ERROR: 조건이 4개를 초과합니다

=== 잘못된 예시 (이렇게 하지 마세요!) ===

❌ 틀림: name LIKE '%report%'
   이유: 'name' 컬럼은 존재하지 않음
   ✅ 올바름: name_full LIKE '%report%'

❌ 틀림: kMDItemWhereFroms LIKE '%Downloads%'
   이유: kMDItemWhereFroms는 다운로드 URL 출처이며, 폴더 위치가 아님
   ✅ 올바름: parent_dir_name = 'Downloads'

❌ 틀림: kMDItemDownloadedDate > date('now', '-1 day')
   이유: kMDItemDownloadedDate는 존재하지 않음
   ✅ 올바름: added_date > date('now', '-1 day')

❌ 틀림: modification_date > 'date('now', '-7 days')'
   이유: date() 함수를 쿼팅하면 안 됨
   ✅ 올바름: modification_date > date('now', '-7 days')

❌ 틀림: extension = 'pdf'
         이 조건은 PDF 파일을 검색합니다.
   이유: 설명 추가하면 안 됨
   ✅ 올바름: extension = 'pdf'

출력 형식: SQL 조건만! 설명 없이!"""

    async def convert(self, query: str) -> str | None:
        """자연어 → SQL WHERE절"""
        try:
            result = await self.client.generate_structured(
                prompt=f"입력: {query}\n출력:",
                schema=SQLConditions,
                system=self.system_prompt,
            )

            # 에러 체크
            if result.error:
                print(f"[방식 2] {result.error}")
                return None

            sql = result.conditions.strip()

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
