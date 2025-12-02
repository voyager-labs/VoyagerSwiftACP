"""방식 2 개선판: 동적 스키마 주입

범용적 개선사항:
1. 동적 스키마 주입 - 쿼리에 관련된 필드만 포함하여 토큰 절약 + 정확도 향상
2. SQL 직접 출력 - JSON 오버헤드 제거로 빠른 응답
"""

import re
from typing import Any

from core.llm.llm_provider import LLMProvider
from core.metadata.mditem_registry import get_indexed_attributes, get_json_attributes


class Method2EnhancedConverter:
    """방식 2 개선판: 동적 스키마 주입으로 정확도 향상"""

    # 키워드 → 관련 필드 매핑 (동적 스키마 주입용)
    KEYWORD_FIELD_MAP: dict[str, list[str]] = {
        # 크기 관련
        r"크기|용량|mb|gb|kb|byte|size|대용량|작은|큰": [
            "kMDItemFSSize",
        ],
        # 날짜 관련
        r"날짜|최근|어제|오늘|이번주|이번달|언제|일전|days?|weeks?|months?|년|월|일|오래": [
            "kMDItemFSContentChangeDate",
            "kMDItemFSCreationDate",
            "kMDItemDateAdded",
            "kMDItemLastUsedDate",
        ],
        # 다운로드 관련
        r"다운로드|download|받은|내려받": [
            "kMDItemDateAdded",
            "kMDItemWhereFroms",
        ],
        # 이미지 관련
        r"이미지|사진|jpg|jpeg|png|heic|gif|bmp|tiff|photo|image|그림|스크린샷": [
            "kMDItemPixelWidth",
            "kMDItemPixelHeight",
            "kMDItemHasAlphaChannel",
            "kMDItemColorSpace",
        ],
        # 해상도 관련
        r"해상도|1080|720|4k|hd|fhd|uhd|픽셀|pixel|고화질|resolution|p\b": [
            "kMDItemPixelWidth",
            "kMDItemPixelHeight",
        ],
        # 영상 관련
        r"영상|동영상|비디오|video|mp4|mov|avi|mkv|webm|m4v": [
            "kMDItemDurationSeconds",
            "kMDItemPixelWidth",
            "kMDItemPixelHeight",
            "kMDItemCodecs",
            "kMDItemVideoBitRate",
        ],
        # 재생시간 관련
        r"분|초|시간|길이|duration|재생|length|짧은|긴": [
            "kMDItemDurationSeconds",
        ],
        # 오디오 관련
        r"오디오|음악|music|mp3|wav|flac|aac|audio|노래|음원|비트레이트|bitrate": [
            "kMDItemDurationSeconds",
            "kMDItemAudioBitRate",
            "kMDItemAudioSampleRate",
            "kMDItemMusicalGenre",
            "kMDItemAlbum",
        ],
        # 문서 관련
        r"문서|pdf|doc|docx|ppt|pptx|xls|xlsx|hwp|document|페이지|page": [
            "kMDItemTitle",
            "kMDItemAuthors",
            "kMDItemNumberOfPages",
            "kMDItemCreator",
        ],
        # 확장자 관련
        r"확장자|extension|파일형식|format|타입|type": [
            "kMDItemContentType",
            "kMDItemKind",
        ],
        # 숨김 파일
        r"숨김|hidden|invisible|숨겨진": [
            "kMDItemFSInvisible",
        ],
        # 위치/GPS 관련
        r"위치|gps|latitude|longitude|경도|위도|지도|장소": [
            "kMDItemLatitude",
            "kMDItemLongitude",
            "kMDItemAltitude",
        ],
    }

    # 항상 포함할 기본 DB 필드
    BASE_DB_FIELDS = [
        "size",
        "extension",
        "modification_date",
        "added_date",
        "parent_dir_name",
        "file_kind",
    ]

    def __init__(self, llm_provider: LLMProvider):
        self.client = llm_provider
        self._all_indexed = get_indexed_attributes()
        self._all_json = get_json_attributes()

    def _detect_relevant_fields(self, query: str) -> tuple[list[str], list[str]]:
        """쿼리에서 관련 필드 감지

        Returns:
            (db_field_keys, json_field_keys)
        """
        query_lower = query.lower()
        relevant_keys: set[str] = set()

        for pattern, field_keys in self.KEYWORD_FIELD_MAP.items():
            if re.search(pattern, query_lower):
                relevant_keys.update(field_keys)

        # DB 필드와 JSON 필드 분리
        db_keys = [k for k in relevant_keys if k in self._all_indexed]
        json_keys = [k for k in relevant_keys if k in self._all_json]

        return db_keys, json_keys

    def _build_field_info(
        self, db_keys: list[str], json_keys: list[str]
    ) -> tuple[str, str]:
        """필드 정보 문자열 생성 (간결한 형식)"""
        # DB 필드 (한 줄로 간결하게)
        db_fields_info: list[str] = []
        for key, attr in self._all_indexed.items():
            if attr.db_field and (attr.db_field in self.BASE_DB_FIELDS or key in db_keys):
                db_fields_info.append(f"  {attr.db_field} ({attr.type.value})")

        # JSON 필드 (한 줄로 간결하게)
        json_fields_info: list[str] = []
        for key in json_keys:
            if key in self._all_json:
                attr = self._all_json[key]
                cast_type = "INTEGER" if attr.type.value in ("number", "boolean") else "TEXT"
                json_fields_info.append(f"  {key} → CAST(...'$.{key}') AS {cast_type})")

        db_section = "\n".join(db_fields_info) if db_fields_info else "  (없음)"
        json_section = "\n".join(json_fields_info) if json_fields_info else "  (없음)"

        return db_section, json_section

    def _build_system_prompt(self, db_section: str, json_section: str) -> str:
        """동적 시스템 프롬프트 생성 (최소화)"""
        return f"""SQL WHERE절 생성. 조건만 출력, 설명 금지.

[DB컬럼]
{db_section}

[JSON필드]
{json_section}

규칙: DB컬럼 직접사용, JSON은 CAST(json_extract(original_metadata,'$.필드') AS 타입)
크기: 1MB=1048576 | 날짜: date('now','-7 days') 따옴표X | 확장자: 점 없이 | 최대 3조건"""

    async def convert(self, query: str) -> str | None:
        """자연어 → SQL WHERE절"""
        result = await self.convert_with_metadata(query)
        return result.get("sql")

    async def convert_with_metadata(self, query: str) -> dict[str, Any]:
        """변환 + 메타데이터"""
        # 1. 관련 필드 감지
        db_keys, json_keys = self._detect_relevant_fields(query)

        # 2. 동적 프롬프트 생성
        db_section, json_section = self._build_field_info(db_keys, json_keys)
        system_prompt = self._build_system_prompt(db_section, json_section)

        metadata: dict[str, Any] = {
            "method": "llm_enhanced",
            "description": "동적 스키마 주입으로 정확도 향상",
            "query": query,
            "detected_db_fields": db_keys,
            "detected_json_fields": json_keys,
        }

        try:
            # 3. LLM 호출 (SQL 직접 출력)
            response = await self.client.generate(
                prompt=f"입력: {query}\n출력:",
                system=system_prompt,
            )

            sql = response.strip()

            # 에러 체크
            if sql.startswith("ERROR:"):
                metadata["sql"] = None
                metadata["success"] = False
                metadata["error"] = sql
            elif not sql or sql.lower() in ["null", "none", ""]:
                metadata["sql"] = None
                metadata["success"] = False
            else:
                metadata["sql"] = sql
                metadata["success"] = True

        except Exception as e:
            metadata["sql"] = None
            metadata["success"] = False
            metadata["error"] = str(e)

        return metadata
