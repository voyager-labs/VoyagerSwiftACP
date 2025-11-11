"""자연어 쿼리를 SQL 조건식으로 변환"""

import json
from typing import Any

from core.llm.ollama_client import OllamaClient


class QueryConverter:
    """자연어 쿼리 → SQL WHERE 조건 변환기"""

    SYSTEM_PROMPT = """You are an expert SQL query generator for file search. Convert natural language to SQLite WHERE clause.

CRITICAL RULES:
1. Return ONLY the SQL WHERE condition (NO "WHERE" keyword)
2. NO explanations, NO alternatives, NO additional text
3. Extension values have NO dot prefix (use 'pdf' not '.pdf')
4. Use single quotes for strings

SCHEMA:
- extension: 'pdf', 'jpg', 'png', 'mp4', 'docx', etc. (NO dot)
- name_full: complete filename with extension
- parent_dir_name: parent folder name (e.g., 'Downloads', 'Documents')
- size: file size in bytes (integer)
- file_kind: Korean description (e.g., 'PDF 문서', 'JPEG 이미지', 'MPEG-4 동영상')
- modification_date: datetime string (YYYY-MM-DD HH:MM:SS)

FILE TYPE MAPPINGS:
- PDF/문서: extension IN ('pdf', 'doc', 'docx', 'txt', 'hwp')
- 이미지/사진: extension IN ('jpg', 'jpeg', 'png', 'gif', 'heic', 'bmp')
- 동영상/비디오: extension IN ('mp4', 'mov', 'avi', 'mkv', 'wmv')
- 음악/오디오: extension IN ('mp3', 'wav', 'flac', 'm4a', 'aac')
- 압축파일: extension IN ('zip', 'tar', 'gz', '7z', 'rar')

SIZE CONVERSIONS:
- 1 KB = 1024
- 1 MB = 1048576
- 100 MB = 104857600
- 1 GB = 1073741824
- 큰 파일 = > 104857600 (>100MB)

DATE FUNCTIONS:
- 오늘/today: date(modification_date) = date('now')
- 어제/yesterday: date(modification_date) = date('now', '-1 day')
- 이번 주/this week: modification_date > date('now', '-7 days')
- 최근 1주일: modification_date > date('now', '-7 days')
- 지난달/last month: date(modification_date) BETWEEN date('now', '-1 month') AND date('now')
- 최근 30일: modification_date > date('now', '-30 days')

EXAMPLES:

Input: "PDF 파일"
Output: extension = 'pdf'

Input: "이미지 파일"
Output: extension IN ('jpg', 'jpeg', 'png', 'gif', 'heic')

Input: "어제 다운로드한 PDF"
Output: extension = 'pdf' AND date(modification_date) = date('now', '-1 day')

Input: "최근 1주일 이내 수정된 사진"
Output: extension IN ('jpg', 'jpeg', 'png', 'heic') AND modification_date > date('now', '-7 days')

Input: "Downloads 폴더의 큰 파일"
Output: parent_dir_name = 'Downloads' AND size > 104857600

Input: "100MB 이상 동영상"
Output: extension IN ('mp4', 'mov', 'avi', 'mkv') AND size > 104857600

Input: "voyager라는 이름이 들어간 문서"
Output: extension IN ('pdf', 'doc', 'docx', 'txt') AND name_full LIKE '%voyager%'

Input: "Documents 폴더의 최근 파일"
Output: parent_dir_name = 'Documents' AND modification_date > date('now', '-7 days')

Input: "큰 동영상 파일"
Output: extension IN ('mp4', 'mov', 'avi', 'mkv') AND size > 104857600

Input: "오늘 만든 PDF"
Output: extension = 'pdf' AND date(modification_date) = date('now')

IMPORTANT:
- Output ONLY the SQL condition
- NO dot in extension values
- Use Korean file type descriptions when available
- Be smart about interpreting "큰" (large) as >100MB"""

    def __init__(self, ollama_client: OllamaClient):
        self.client = ollama_client

    async def convert(self, query: str) -> str | None:
        """자연어 쿼리를 SQL WHERE 조건으로 변환

        Args:
            query: 자연어 검색 쿼리

        Returns:
            SQL WHERE 조건식 또는 None (변환 실패 시)
        """
        prompt = f"Input: {query}\nOutput:"

        try:
            response = await self.client.generate(prompt=prompt, system=self.SYSTEM_PROMPT)

            # 응답 정리 - 첫 번째 줄만 사용
            result = response.strip().split('\n')[0].strip()

            if result.lower() in ["null", "none", ""]:
                return None

            return result

        except Exception as e:
            print(f"쿼리 변환 오류: {e}")
            return None

    async def convert_with_metadata(self, query: str) -> dict[str, Any]:
        """쿼리 변환 + 메타데이터 반환

        Returns:
            {
                "query": 원본 쿼리,
                "where_clause": SQL 조건식,
                "success": 성공 여부
            }
        """
        where_clause = await self.convert(query)

        return {
            "query": query,
            "where_clause": where_clause,
            "success": where_clause is not None,
        }
