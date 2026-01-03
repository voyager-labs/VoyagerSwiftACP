"""macOS MDItem 속성 레지스트리

Apple Developer Documentation 기반:
https://developer.apple.com/documentation/coreservices/file_metadata/mditem/common_metadata_attribute_keys
"""

from dataclasses import dataclass
from enum import Enum
from typing import Any


class MDItemType(Enum):
    """MDItem 속성 타입"""

    STRING = "string"
    NUMBER = "number"
    DATE = "date"
    BOOLEAN = "boolean"
    ARRAY = "array"


@dataclass
class MDItemAttribute:
    """MDItem 속성 정의

    Attributes:
        key: MDItem 키 (예: kMDItemContentType)
        db_field: 전용 DB 컬럼명 (None이면 JSON 쿼리 사용)
        type: 데이터 타입
        description: 속성 설명
        examples: 예시 값들
        search_aliases: 자연어 검색 시 사용 가능한 별칭들
        category: 속성 카테고리 (파일시스템/콘텐츠/미디어 등)
    """

    key: str
    db_field: str | None
    type: MDItemType
    description: str
    examples: list[Any]
    search_aliases: list[str]
    category: str = "general"


@dataclass
class PropertyKeyMapping:
    """Search API용 propertyKey 매핑

    Attributes:
        property_key: API에서 사용하는 키 (예: "size", "contentType")
        db_field: DB 컬럼명 (None이면 JSON 쿼리)
        json_path: JSON 추출 경로 (예: "$.kMDItemPixelHeight")
        value_type: 값 타입 (검증/변환용)
        supported_operators: 지원하는 연산자 목록
    """

    property_key: str
    db_field: str | None
    json_path: str | None
    value_type: MDItemType
    supported_operators: list[str]


# Apple MDItem 속성 레지스트리
MDITEM_REGISTRY: dict[str, MDItemAttribute] = {
    # ============================================
    # 파일 시스템 속성 (File System Attributes)
    # ============================================
    "kMDItemContentType": MDItemAttribute(
        key="kMDItemContentType",
        db_field="uniform_type_identifier",
        type=MDItemType.STRING,
        description="Uniform Type Identifier (UTI)",
        examples=["public.pdf", "public.jpeg", "com.apple.application", "public.mpeg-4"],
        search_aliases=["파일타입", "file type", "uti", "mime"],
        category="filesystem",
    ),
    "kMDItemKind": MDItemAttribute(
        key="kMDItemKind",
        db_field="file_kind",
        type=MDItemType.STRING,
        description="파일 종류 (로컬라이즈된 설명)",
        examples=["PDF 문서", "JPEG 이미지", "MPEG-4 동영상", "응용 프로그램"],
        search_aliases=["종류", "kind", "type", "파일종류"],
        category="filesystem",
    ),
    "kMDItemFSSize": MDItemAttribute(
        key="kMDItemFSSize",
        db_field="size",
        type=MDItemType.NUMBER,
        description="파일 크기 (bytes)",
        examples=[1024, 1048576, 104857600, 1073741824],
        search_aliases=["크기", "size", "용량", "파일크기"],
        category="filesystem",
    ),
    "kMDItemFSInvisible": MDItemAttribute(
        key="kMDItemFSInvisible",
        db_field="is_invisible",
        type=MDItemType.BOOLEAN,
        description="숨김 파일 여부",
        examples=[True, False],
        search_aliases=["숨김", "hidden", "invisible"],
        category="filesystem",
    ),
    "kMDItemFSCreationDate": MDItemAttribute(
        key="kMDItemFSCreationDate",
        db_field="creation_date",
        type=MDItemType.DATE,
        description="파일 생성 시간",
        examples=["2025-01-01 12:00:00"],
        search_aliases=["생성일", "creation date", "만든날"],
        category="filesystem",
    ),
    "kMDItemFSContentChangeDate": MDItemAttribute(
        key="kMDItemFSContentChangeDate",
        db_field="modification_date",
        type=MDItemType.DATE,
        description="파일 수정 시간",
        examples=["2025-01-01 12:00:00"],
        search_aliases=["수정일", "modification date", "변경일"],
        category="filesystem",
    ),
    "kMDItemDateAdded": MDItemAttribute(
        key="kMDItemDateAdded",
        db_field="added_date",
        type=MDItemType.DATE,
        description="파일 추가 시간 (다운로드/복사된 시간)",
        examples=["2025-01-01 12:00:00"],
        search_aliases=["추가일", "added date", "다운로드일"],
        category="filesystem",
    ),
    "kMDItemLastUsedDate": MDItemAttribute(
        key="kMDItemLastUsedDate",
        db_field="last_used_date",
        type=MDItemType.DATE,
        description="파일 마지막 실행/사용 시간",
        examples=["2025-01-01 12:00:00"],
        search_aliases=["마지막사용", "last used", "실행일"],
        category="filesystem",
    ),
    # ============================================
    # 이미지 속성 (Image Attributes)
    # ============================================
    "kMDItemPixelHeight": MDItemAttribute(
        key="kMDItemPixelHeight",
        db_field=None,
        type=MDItemType.NUMBER,
        description="이미지/비디오 높이 (pixels)",
        examples=[1080, 1920, 2160, 4096],
        search_aliases=["높이", "height", "세로", "해상도"],
        category="image",
    ),
    "kMDItemPixelWidth": MDItemAttribute(
        key="kMDItemPixelWidth",
        db_field=None,
        type=MDItemType.NUMBER,
        description="이미지/비디오 너비 (pixels)",
        examples=[1920, 3840, 7680],
        search_aliases=["너비", "width", "가로", "해상도"],
        category="image",
    ),
    "kMDItemPixelCount": MDItemAttribute(
        key="kMDItemPixelCount",
        db_field=None,
        type=MDItemType.NUMBER,
        description="총 픽셀 수",
        examples=[2073600, 8294400, 33177600],
        search_aliases=["픽셀수", "pixel count", "해상도"],
        category="image",
    ),
    "kMDItemColorSpace": MDItemAttribute(
        key="kMDItemColorSpace",
        db_field=None,
        type=MDItemType.STRING,
        description="색공간 (RGB, CMYK 등)",
        examples=["RGB", "CMYK", "Gray"],
        search_aliases=["색공간", "color space", "컬러"],
        category="image",
    ),
    "kMDItemBitsPerSample": MDItemAttribute(
        key="kMDItemBitsPerSample",
        db_field=None,
        type=MDItemType.NUMBER,
        description="샘플당 비트 수",
        examples=[8, 16, 32],
        search_aliases=["비트심도", "bit depth", "color depth"],
        category="image",
    ),
    "kMDItemOrientation": MDItemAttribute(
        key="kMDItemOrientation",
        db_field=None,
        type=MDItemType.NUMBER,
        description="이미지 회전 방향 (0-8)",
        examples=[0, 1, 3, 6, 8],
        search_aliases=["회전", "orientation", "방향"],
        category="image",
    ),
    "kMDItemHasAlphaChannel": MDItemAttribute(
        key="kMDItemHasAlphaChannel",
        db_field=None,
        type=MDItemType.BOOLEAN,
        description="알파 채널(투명도) 포함 여부",
        examples=[True, False],
        search_aliases=["알파채널", "alpha", "투명도", "transparency"],
        category="image",
    ),
    # ============================================
    # 비디오 속성 (Video Attributes)
    # ============================================
    "kMDItemDurationSeconds": MDItemAttribute(
        key="kMDItemDurationSeconds",
        db_field=None,
        type=MDItemType.NUMBER,
        description="비디오/오디오 재생 시간 (초)",
        examples=[60, 180, 3600, 7200],
        search_aliases=["길이", "duration", "재생시간", "시간"],
        category="video",
    ),
    "kMDItemCodecs": MDItemAttribute(
        key="kMDItemCodecs",
        db_field=None,
        type=MDItemType.ARRAY,
        description="비디오/오디오 코덱 목록",
        examples=[["H.264"], ["H.265", "AAC"], ["VP9", "Opus"]],
        search_aliases=["코덱", "codec", "인코딩", "압축"],
        category="video",
    ),
    "kMDItemVideoBitRate": MDItemAttribute(
        key="kMDItemVideoBitRate",
        db_field=None,
        type=MDItemType.NUMBER,
        description="비디오 비트레이트 (bits/sec)",
        examples=[2500000, 5000000, 10000000],
        search_aliases=["비디오비트레이트", "video bitrate", "화질"],
        category="video",
    ),
    "kMDItemAudioBitRate": MDItemAttribute(
        key="kMDItemAudioBitRate",
        db_field=None,
        type=MDItemType.NUMBER,
        description="오디오 비트레이트 (bits/sec)",
        examples=[128000, 192000, 320000],
        search_aliases=["오디오비트레이트", "audio bitrate", "음질"],
        category="video",
    ),
    "kMDItemAudioChannelCount": MDItemAttribute(
        key="kMDItemAudioChannelCount",
        db_field=None,
        type=MDItemType.NUMBER,
        description="오디오 채널 수 (1=모노, 2=스테레오, 6=5.1)",
        examples=[1, 2, 6],
        search_aliases=["채널", "channel", "스테레오", "모노", "서라운드"],
        category="video",
    ),
    "kMDItemTotalBitRate": MDItemAttribute(
        key="kMDItemTotalBitRate",
        db_field=None,
        type=MDItemType.NUMBER,
        description="전체 비트레이트 (bits/sec)",
        examples=[5000000, 10000000, 20000000],
        search_aliases=["비트레이트", "bitrate", "전송률"],
        category="video",
    ),
    # ============================================
    # 오디오 속성 (Audio Attributes)
    # ============================================
    "kMDItemAudioSampleRate": MDItemAttribute(
        key="kMDItemAudioSampleRate",
        db_field=None,
        type=MDItemType.NUMBER,
        description="오디오 샘플링 레이트 (Hz)",
        examples=[44100, 48000, 96000],
        search_aliases=["샘플레이트", "sample rate", "샘플링"],
        category="audio",
    ),
    "kMDItemMusicalGenre": MDItemAttribute(
        key="kMDItemMusicalGenre",
        db_field=None,
        type=MDItemType.STRING,
        description="음악 장르",
        examples=["Rock", "Jazz", "Classical", "K-Pop"],
        search_aliases=["장르", "genre", "음악장르"],
        category="audio",
    ),
    "kMDItemAlbum": MDItemAttribute(
        key="kMDItemAlbum",
        db_field=None,
        type=MDItemType.STRING,
        description="앨범 이름",
        examples=["Greatest Hits", "Live Concert"],
        search_aliases=["앨범", "album"],
        category="audio",
    ),
    "kMDItemComposer": MDItemAttribute(
        key="kMDItemComposer",
        db_field=None,
        type=MDItemType.STRING,
        description="작곡가",
        examples=["Bach", "Mozart", "윤하"],
        search_aliases=["작곡가", "composer"],
        category="audio",
    ),
    # ============================================
    # 문서 속성 (Document Attributes)
    # ============================================
    "kMDItemTitle": MDItemAttribute(
        key="kMDItemTitle",
        db_field=None,
        type=MDItemType.STRING,
        description="문서 제목",
        examples=["Quarterly Report", "프로젝트 계획서", "회의록"],
        search_aliases=["제목", "title", "문서제목"],
        category="document",
    ),
    "kMDItemAuthors": MDItemAttribute(
        key="kMDItemAuthors",
        db_field=None,
        type=MDItemType.ARRAY,
        description="문서 작성자 목록",
        examples=[["John Doe"], ["홍길동", "김철수"]],
        search_aliases=["작성자", "author", "저자", "만든사람"],
        category="document",
    ),
    "kMDItemCreator": MDItemAttribute(
        key="kMDItemCreator",
        db_field=None,
        type=MDItemType.STRING,
        description="문서 생성 프로그램",
        examples=["Microsoft Word", "Adobe Photoshop", "Pages"],
        search_aliases=["생성프로그램", "creator", "애플리케이션"],
        category="document",
    ),
    "kMDItemKeywords": MDItemAttribute(
        key="kMDItemKeywords",
        db_field=None,
        type=MDItemType.ARRAY,
        description="문서 키워드/태그",
        examples=[["work", "important"], ["업무", "긴급", "검토필요"]],
        search_aliases=["키워드", "keyword", "태그", "tag"],
        category="document",
    ),
    "kMDItemNumberOfPages": MDItemAttribute(
        key="kMDItemNumberOfPages",
        db_field=None,
        type=MDItemType.NUMBER,
        description="문서 페이지 수",
        examples=[1, 10, 50, 100],
        search_aliases=["페이지", "page", "페이지수"],
        category="document",
    ),
    "kMDItemPageWidth": MDItemAttribute(
        key="kMDItemPageWidth",
        db_field=None,
        type=MDItemType.NUMBER,
        description="페이지 너비 (포인트)",
        examples=[612, 792],
        search_aliases=["페이지너비", "page width"],
        category="document",
    ),
    "kMDItemPageHeight": MDItemAttribute(
        key="kMDItemPageHeight",
        db_field=None,
        type=MDItemType.NUMBER,
        description="페이지 높이 (포인트)",
        examples=[792, 1224],
        search_aliases=["페이지높이", "page height"],
        category="document",
    ),
    "kMDItemSecurityMethod": MDItemAttribute(
        key="kMDItemSecurityMethod",
        db_field=None,
        type=MDItemType.STRING,
        description="문서 보안/암호화 방식",
        examples=["Password Encrypted", "None"],
        search_aliases=["암호화", "보안", "encrypted", "security", "password"],
        category="document",
    ),
    # ============================================
    # 다운로드/출처 속성 (Download Attributes)
    # ============================================
    "kMDItemWhereFroms": MDItemAttribute(
        key="kMDItemWhereFroms",
        db_field=None,
        type=MDItemType.ARRAY,
        description="다운로드 출처 URL 목록",
        examples=[["https://example.com/file.pdf"], ["https://github.com/repo"]],
        search_aliases=["출처", "다운로드", "url", "where from", "source"],
        category="download",
    ),
    "kMDItemDownloadedDate": MDItemAttribute(
        key="kMDItemDownloadedDate",
        db_field=None,
        type=MDItemType.DATE,
        description="다운로드 완료 시간",
        examples=["2025-01-01 12:00:00"],
        search_aliases=["다운로드일", "downloaded date"],
        category="download",
    ),
    # ============================================
    # 콘텐츠 속성 (Content Attributes)
    # ============================================
    "kMDItemContentCreationDate": MDItemAttribute(
        key="kMDItemContentCreationDate",
        db_field="content_creation_date",
        type=MDItemType.DATE,
        description="콘텐츠 생성 시간 (EXIF 등)",
        examples=["2025-01-01 12:00:00"],
        search_aliases=["콘텐츠생성일", "content creation"],
        category="content",
    ),
    "kMDItemContentModificationDate": MDItemAttribute(
        key="kMDItemContentModificationDate",
        db_field="content_modification_date",
        type=MDItemType.DATE,
        description="콘텐츠 수정 시간",
        examples=["2025-01-01 12:00:00"],
        search_aliases=["콘텐츠수정일", "content modification"],
        category="content",
    ),
    "kMDItemEncodingApplications": MDItemAttribute(
        key="kMDItemEncodingApplications",
        db_field=None,
        type=MDItemType.ARRAY,
        description="인코딩에 사용된 애플리케이션",
        examples=[["Final Cut Pro"], ["Adobe Premiere Pro", "Compressor"]],
        search_aliases=["인코딩프로그램", "encoding app"],
        category="content",
    ),
    # ============================================
    # 위치 속성 (Location Attributes)
    # ============================================
    "kMDItemLatitude": MDItemAttribute(
        key="kMDItemLatitude",
        db_field=None,
        type=MDItemType.NUMBER,
        description="GPS 위도",
        examples=[37.5665, 35.6762],
        search_aliases=["위도", "latitude", "gps"],
        category="location",
    ),
    "kMDItemLongitude": MDItemAttribute(
        key="kMDItemLongitude",
        db_field=None,
        type=MDItemType.NUMBER,
        description="GPS 경도",
        examples=[126.9780, 139.6503],
        search_aliases=["경도", "longitude", "gps"],
        category="location",
    ),
    "kMDItemAltitude": MDItemAttribute(
        key="kMDItemAltitude",
        db_field=None,
        type=MDItemType.NUMBER,
        description="GPS 고도 (미터)",
        examples=[100, 500, 1000],
        search_aliases=["고도", "altitude", "높이"],
        category="location",
    ),
}


# ============================================
# Search API용 PropertyKey 레지스트리
# ============================================
PROPERTY_KEY_REGISTRY: dict[str, PropertyKeyMapping] = {
    # 파일 시스템 속성
    "size": PropertyKeyMapping(
        property_key="size",
        db_field="size",
        json_path=None,
        value_type=MDItemType.NUMBER,
        supported_operators=["eq", "gt", "gte", "lt", "lte", "between"],
    ),
    "contentType": PropertyKeyMapping(
        property_key="contentType",
        db_field="uniform_type_identifier",
        json_path=None,
        value_type=MDItemType.STRING,
        supported_operators=["eq", "contains", "in"],
    ),
    "kind": PropertyKeyMapping(
        property_key="kind",
        db_field="file_kind",
        json_path=None,
        value_type=MDItemType.STRING,
        supported_operators=["eq", "contains"],
    ),
    "name": PropertyKeyMapping(
        property_key="name",
        db_field="name_full",
        json_path=None,
        value_type=MDItemType.STRING,
        supported_operators=["eq", "contains"],
    ),
    "extension": PropertyKeyMapping(
        property_key="extension",
        db_field="extension",
        json_path=None,
        value_type=MDItemType.STRING,
        supported_operators=["eq", "in"],
    ),
    "isInvisible": PropertyKeyMapping(
        property_key="isInvisible",
        db_field="is_invisible",
        json_path=None,
        value_type=MDItemType.BOOLEAN,
        supported_operators=["eq"],
    ),
    # 날짜 속성
    "createdAt": PropertyKeyMapping(
        property_key="createdAt",
        db_field="creation_date",
        json_path=None,
        value_type=MDItemType.DATE,
        supported_operators=["eq", "gt", "gte", "lt", "lte", "between"],
    ),
    "modifiedAt": PropertyKeyMapping(
        property_key="modifiedAt",
        db_field="modification_date",
        json_path=None,
        value_type=MDItemType.DATE,
        supported_operators=["eq", "gt", "gte", "lt", "lte", "between"],
    ),
    "addedAt": PropertyKeyMapping(
        property_key="addedAt",
        db_field="added_date",
        json_path=None,
        value_type=MDItemType.DATE,
        supported_operators=["eq", "gt", "gte", "lt", "lte", "between"],
    ),
    "lastUsedAt": PropertyKeyMapping(
        property_key="lastUsedAt",
        db_field="last_used_date",
        json_path=None,
        value_type=MDItemType.DATE,
        supported_operators=["eq", "gt", "gte", "lt", "lte", "between"],
    ),
    "contentCreatedAt": PropertyKeyMapping(
        property_key="contentCreatedAt",
        db_field="content_creation_date",
        json_path=None,
        value_type=MDItemType.DATE,
        supported_operators=["eq", "gt", "gte", "lt", "lte", "between"],
    ),
    "contentModifiedAt": PropertyKeyMapping(
        property_key="contentModifiedAt",
        db_field="content_modification_date",
        json_path=None,
        value_type=MDItemType.DATE,
        supported_operators=["eq", "gt", "gte", "lt", "lte", "between"],
    ),
    # 이미지 속성 (JSON)
    "pixelHeight": PropertyKeyMapping(
        property_key="pixelHeight",
        db_field=None,
        json_path="$.kMDItemPixelHeight",
        value_type=MDItemType.NUMBER,
        supported_operators=["eq", "gt", "gte", "lt", "lte", "between"],
    ),
    "pixelWidth": PropertyKeyMapping(
        property_key="pixelWidth",
        db_field=None,
        json_path="$.kMDItemPixelWidth",
        value_type=MDItemType.NUMBER,
        supported_operators=["eq", "gt", "gte", "lt", "lte", "between"],
    ),
    "colorSpace": PropertyKeyMapping(
        property_key="colorSpace",
        db_field=None,
        json_path="$.kMDItemColorSpace",
        value_type=MDItemType.STRING,
        supported_operators=["eq", "in"],
    ),
    "hasAlphaChannel": PropertyKeyMapping(
        property_key="hasAlphaChannel",
        db_field=None,
        json_path="$.kMDItemHasAlphaChannel",
        value_type=MDItemType.BOOLEAN,
        supported_operators=["eq"],
    ),
    # 비디오/오디오 속성 (JSON)
    "duration": PropertyKeyMapping(
        property_key="duration",
        db_field=None,
        json_path="$.kMDItemDurationSeconds",
        value_type=MDItemType.NUMBER,
        supported_operators=["eq", "gt", "gte", "lt", "lte", "between"],
    ),
    "videoBitRate": PropertyKeyMapping(
        property_key="videoBitRate",
        db_field=None,
        json_path="$.kMDItemVideoBitRate",
        value_type=MDItemType.NUMBER,
        supported_operators=["eq", "gt", "gte", "lt", "lte"],
    ),
    "audioBitRate": PropertyKeyMapping(
        property_key="audioBitRate",
        db_field=None,
        json_path="$.kMDItemAudioBitRate",
        value_type=MDItemType.NUMBER,
        supported_operators=["eq", "gt", "gte", "lt", "lte"],
    ),
    "audioSampleRate": PropertyKeyMapping(
        property_key="audioSampleRate",
        db_field=None,
        json_path="$.kMDItemAudioSampleRate",
        value_type=MDItemType.NUMBER,
        supported_operators=["eq", "gt", "gte", "lt", "lte"],
    ),
    "audioChannelCount": PropertyKeyMapping(
        property_key="audioChannelCount",
        db_field=None,
        json_path="$.kMDItemAudioChannelCount",
        value_type=MDItemType.NUMBER,
        supported_operators=["eq", "in"],
    ),
    # 문서 속성 (JSON)
    "title": PropertyKeyMapping(
        property_key="title",
        db_field=None,
        json_path="$.kMDItemTitle",
        value_type=MDItemType.STRING,
        supported_operators=["eq", "contains"],
    ),
    "numberOfPages": PropertyKeyMapping(
        property_key="numberOfPages",
        db_field=None,
        json_path="$.kMDItemNumberOfPages",
        value_type=MDItemType.NUMBER,
        supported_operators=["eq", "gt", "gte", "lt", "lte", "between"],
    ),
    "creator": PropertyKeyMapping(
        property_key="creator",
        db_field=None,
        json_path="$.kMDItemCreator",
        value_type=MDItemType.STRING,
        supported_operators=["eq", "contains"],
    ),
    # 위치 속성 (JSON)
    "latitude": PropertyKeyMapping(
        property_key="latitude",
        db_field=None,
        json_path="$.kMDItemLatitude",
        value_type=MDItemType.NUMBER,
        supported_operators=["eq", "gt", "gte", "lt", "lte", "between"],
    ),
    "longitude": PropertyKeyMapping(
        property_key="longitude",
        db_field=None,
        json_path="$.kMDItemLongitude",
        value_type=MDItemType.NUMBER,
        supported_operators=["eq", "gt", "gte", "lt", "lte", "between"],
    ),
}


def get_property_key_mapping(property_key: str) -> PropertyKeyMapping | None:
    """propertyKey로 매핑 정보 조회"""
    return PROPERTY_KEY_REGISTRY.get(property_key)


def get_all_property_keys() -> list[str]:
    """모든 지원 propertyKey 목록 반환"""
    return list(PROPERTY_KEY_REGISTRY.keys())


def get_attributes_by_category(category: str) -> dict[str, MDItemAttribute]:
    """카테고리별 속성 필터링"""
    return {k: v for k, v in MDITEM_REGISTRY.items() if v.category == category}


def get_indexed_attributes() -> dict[str, MDItemAttribute]:
    """전용 DB 컬럼이 있는 속성들만 반환"""
    return {k: v for k, v in MDITEM_REGISTRY.items() if v.db_field is not None}


def get_json_attributes() -> dict[str, MDItemAttribute]:
    """JSON 쿼리가 필요한 속성들만 반환"""
    return {k: v for k, v in MDITEM_REGISTRY.items() if v.db_field is None}


__all__ = [
    "MDITEM_REGISTRY",
    "MDItemAttribute",
    "MDItemType",
    "PropertyKeyMapping",
    "PROPERTY_KEY_REGISTRY",
    "get_attributes_by_category",
    "get_indexed_attributes",
    "get_json_attributes",
    "get_property_key_mapping",
    "get_all_property_keys",
]
