# MDItem 레지스트리 커버리지 점검

- 작성일: 2026-01-19
- 대상 레지스트리: `shared/system_property_registry.json`
- 비교 데이터:
    - `apps/backend/src/osxmetadata/attribute_data/audio_attributes.json`
    - `apps/backend/src/osxmetadata/attribute_data/common_attributes.json`
    - `apps/backend/src/osxmetadata/attribute_data/filesystem_attributes.json`
    - `apps/backend/src/osxmetadata/attribute_data/image_attributes.json`
    - `apps/backend/src/osxmetadata/attribute_data/video_attributes.json`
    - `apps/backend/src/osxmetadata/attribute_data/mdimporter_constants.json`
    - `apps/backend/src/osxmetadata/attribute_data/nsurl_resource_keys.json`
    - `apps/backend/src/osxmetadata/attribute_data/load_attribute_data.py` (추가 주입 키 참고)

## 비교 방식

- 각 JSON 파일의 `name` 필드를 키로 수집했다.
- `load_attribute_data.py`에서 주입하는 키(`kMDItemDownloadedDate`)를 추가 비교 대상에 포함했다.
- 레지스트리에서는 `$`/`_` 메타 키를 제외하고 실제 MDItem 키만 비교했다.

## 요약

- 레지스트리 키 수: **41**
- 비교 대상 키 총합: **295**
- 레지스트리에 누락된 키: **254**
- 레지스트리에만 존재하는 키: **0**
- 전체 커버리지: **13.9%**

## 파일별 누락 현황

| 파일                          | 총 키 수 | 레지스트리 누락 | 커버리지 |
| ----------------------------- | -------: | --------------: | -------: |
| `audio_attributes.json`       |       19 |              15 |    21.1% |
| `common_attributes.json`      |       57 |              41 |    28.1% |
| `filesystem_attributes.json`  |       12 |               8 |    33.3% |
| `image_attributes.json`       |       37 |              26 |    29.7% |
| `video_attributes.json`       |       13 |               9 |    30.8% |
| `mdimporter_constants.json`   |       44 |              42 |     4.5% |
| `nsurl_resource_keys.json`    |      113 |             113 |     0.0% |
| `load_attribute_data.py` 주입 |        1 |               1 |     0.0% |

## 프리픽스별 커버리지

| 프리픽스     | 총 키 수 | 레지스트리 누락 | 커버리지 |
| ------------ | -------: | --------------: | -------: |
| `NSURL`      |      113 |             113 |     0.0% |
| `kMDItem`    |      163 |             122 |    25.2% |
| `kMDLabel`   |       17 |              17 |     0.0% |
| `kMDPrivate` |        1 |               1 |     0.0% |
| `kMDPublic`  |        1 |               1 |     0.0% |

## 레지스트리 포함 키

- 레지스트리에 정의된 키를 **키 + 한 줄 설명(한국어)**으로 정리했다.

- kMDItemAlbum: 설명: 앨범 이름
- kMDItemAltitude: 설명: GPS 고도 (미터)
- kMDItemAudioBitRate: 설명: 오디오 비트레이트 (bits/sec)
- kMDItemAudioChannelCount: 설명: 오디오 채널 수 (1=모노, 2=스테레오, 6=5.1)
- kMDItemAudioSampleRate: 설명: 오디오 샘플링 레이트 (Hz)
- kMDItemAuthors: 설명: 문서 작성자 목록
- kMDItemBitsPerSample: 설명: 샘플당 비트 수
- kMDItemCodecs: 설명: 비디오/오디오 코덱 목록
- kMDItemColorSpace: 설명: 색공간 (RGB, CMYK 등)
- kMDItemComposer: 설명: 작곡가
- kMDItemContentCreationDate: 설명: 콘텐츠 생성 시간 (EXIF 등)
- kMDItemContentModificationDate: 설명: 콘텐츠 수정 시간
- kMDItemContentType: 설명: Uniform Type Identifier (UTI)
- kMDItemCreator: 설명: 문서 생성 프로그램
- kMDItemDateAdded: 설명: 파일 추가 시간 (다운로드/복사된 시간)
- kMDItemDownloadedDate: 설명: 다운로드 완료 시간
- kMDItemDurationSeconds: 설명: 비디오/오디오 재생 시간 (초)
- kMDItemEncodingApplications: 설명: 인코딩에 사용된 애플리케이션
- kMDItemFSContentChangeDate: 설명: 파일 수정 시간
- kMDItemFSCreationDate: 설명: 파일 생성 시간
- kMDItemFSInvisible: 설명: 숨김 파일 여부
- kMDItemFSSize: 설명: 파일 크기 (bytes)
- kMDItemHasAlphaChannel: 설명: 알파 채널(투명도) 포함 여부
- kMDItemKeywords: 설명: 문서 키워드/태그
- kMDItemKind: 설명: 파일 종류 (로컬라이즈된 설명)
- kMDItemLastUsedDate: 설명: 파일 마지막 실행/사용 시간
- kMDItemLatitude: 설명: GPS 위도
- kMDItemLongitude: 설명: GPS 경도
- kMDItemMusicalGenre: 설명: 음악 장르
- kMDItemNumberOfPages: 설명: 문서 페이지 수
- kMDItemOrientation: 설명: 이미지 회전 방향 (0-8)
- kMDItemPageHeight: 설명: 페이지 높이 (포인트)
- kMDItemPageWidth: 설명: 페이지 너비 (포인트)
- kMDItemPixelCount: 설명: 총 픽셀 수
- kMDItemPixelHeight: 설명: 이미지/비디오 높이 (pixels)
- kMDItemPixelWidth: 설명: 이미지/비디오 너비 (pixels)
- kMDItemSecurityMethod: 설명: 문서 보안/암호화 방식
- kMDItemTitle: 설명: 문서 제목
- kMDItemTotalBitRate: 설명: 전체 비트레이트 (bits/sec)
- kMDItemVideoBitRate: 설명: 비디오 비트레이트 (bits/sec)
- kMDItemWhereFroms: 설명: 다운로드 출처 URL 목록

## 레지스트리에 누락된 키 (전체)

- 파일별로 분류해 누락 키를 정리했다.
- 각 항목은 **키 + 한 줄 설명(한국어)**으로 표기했다.

### audio_attributes.json

- kMDItemAppleLoopDescriptors: 설명: MDItem 메타데이터의 애플 루프 Descriptors 관련 값
- kMDItemAppleLoopsKeyFilterType: 설명: MDItem 메타데이터의 애플 루프 키 필터 타입 관련 값
- kMDItemAppleLoopsLoopMode: 설명: MDItem 메타데이터의 애플 루프 루프 모드 관련 값
- kMDItemAppleLoopsRootKey: 설명: MDItem 메타데이터의 애플 루프 루트 키 관련 값
- kMDItemAudioEncodingApplication: 설명: MDItem 메타데이터의 오디오 인코딩 애플리케이션 관련 값
- kMDItemAudioTrackNumber: 설명: MDItem 메타데이터의 오디오 트랙 번호 관련 값
- kMDItemIsGeneralMIDISequence: 설명: MDItem 메타데이터의 General MIDI Sequence 여부 관련 값
- kMDItemKeySignature: 설명: MDItem 메타데이터의 키 서명 관련 값
- kMDItemLyricist: 설명: MDItem 메타데이터의 작사가 관련 값
- kMDItemMusicalInstrumentCategory: 설명: MDItem 메타데이터의 음악 악기 Category 관련 값
- kMDItemMusicalInstrumentName: 설명: MDItem 메타데이터의 음악 악기 이름 관련 값
- kMDItemRecordingDate: 설명: MDItem 메타데이터의 녹음 날짜 관련 값
- kMDItemRecordingYear: 설명: MDItem 메타데이터의 녹음 연도 관련 값
- kMDItemTempo: 설명: MDItem 메타데이터의 템포 관련 값
- kMDItemTimeSignature: 설명: MDItem 메타데이터의 시간 서명 관련 값

### common_attributes.json

- kMDItemAttributeChangeDate: 설명: MDItem 메타데이터의 속성 변경 날짜 관련 값
- kMDItemAudiences: 설명: MDItem 메타데이터의 대상 관련 값
- kMDItemAuthorAddresses: 설명: MDItem 메타데이터의 저자 주소 관련 값
- kMDItemAuthorEmailAddresses: 설명: MDItem 메타데이터의 저자 이메일 주소 관련 값
- kMDItemCFBundleIdentifier: 설명: MDItem 메타데이터의 CF 번들 식별자 관련 값
- kMDItemCity: 설명: MDItem 메타데이터의 도시 관련 값
- kMDItemComment: 설명: MDItem 메타데이터의 코멘트 관련 값
- kMDItemContactKeywords: 설명: MDItem 메타데이터의 연락처 키워드 관련 값
- kMDItemContributors: 설명: MDItem 메타데이터의 기여자 관련 값
- kMDItemCopyright: 설명: MDItem 메타데이터의 저작권 관련 값
- kMDItemCountry: 설명: MDItem 메타데이터의 국가 관련 값
- kMDItemCoverage: 설명: MDItem 메타데이터의 커버리지 관련 값
- kMDItemDescription: 설명: MDItem 메타데이터의 설명 관련 값
- kMDItemDueDate: 설명: MDItem 메타데이터의 기한 날짜 관련 값
- kMDItemEmailAddresses: 설명: MDItem 메타데이터의 이메일 주소 관련 값
- kMDItemFSHasCustomIcon: 설명: MDItem 메타데이터의 파일 시스템 사용자 지정 아이콘 여부 관련 값
- kMDItemFSIsStationery: 설명: MDItem 메타데이터의 파일 시스템 Stationery 여부 관련 값
- kMDItemFinderComment: 설명: MDItem 메타데이터의 파인더 코멘트 관련 값
- kMDItemFonts: 설명: MDItem 메타데이터의 폰트 관련 값
- kMDItemHeadline: 설명: MDItem 메타데이터의 헤드라인 관련 값
- kMDItemIdentifier: 설명: MDItem 메타데이터의 식별자 관련 값
- kMDItemInformation: 설명: MDItem 메타데이터의 정보 관련 값
- kMDItemInstantMessageAddresses: 설명: MDItem 메타데이터의 즉시 메시지 주소 관련 값
- kMDItemInstructions: 설명: MDItem 메타데이터의 지침 관련 값
- kMDItemLanguages: 설명: MDItem 메타데이터의 언어 관련 값
- kMDItemOrganizations: 설명: MDItem 메타데이터의 조직 관련 값
- kMDItemParticipants: 설명: MDItem 메타데이터의 참가자 관련 값
- kMDItemPhoneNumbers: 설명: MDItem 메타데이터의 전화 Numbers 관련 값
- kMDItemProjects: 설명: MDItem 메타데이터의 프로젝트 관련 값
- kMDItemPublishers: 설명: MDItem 메타데이터의 발행자 관련 값
- kMDItemRecipientAddresses: 설명: MDItem 메타데이터의 수신자 주소 관련 값
- kMDItemRecipientEmailAddresses: 설명: MDItem 메타데이터의 수신자 이메일 주소 관련 값
- kMDItemRecipients: 설명: MDItem 메타데이터의 수신자 관련 값
- kMDItemRights: 설명: MDItem 메타데이터의 권리 관련 값
- kMDItemStarRating: 설명: MDItem 메타데이터의 별 평점 관련 값
- kMDItemStateOrProvince: 설명: MDItem 메타데이터의 주 Or 도/주 관련 값
- kMDItemSubject: 설명: MDItem 메타데이터의 주제 관련 값
- kMDItemTextContent: 설명: MDItem 메타데이터의 텍스트 콘텐츠 관련 값
- kMDItemTheme: 설명: MDItem 메타데이터의 테마 관련 값
- kMDItemURL: 설명: MDItem 메타데이터의 URL 관련 값
- kMDItemVersion: 설명: MDItem 메타데이터의 Version 관련 값

### filesystem_attributes.json

- kMDItemDisplayName: 설명: MDItem 메타데이터의 표시 이름 관련 값
- kMDItemFSIsExtensionHidden: 설명: MDItem 메타데이터의 파일 시스템 확장자 숨김 여부 관련 값
- kMDItemFSLabel: 설명: MDItem 메타데이터의 파일 시스템 라벨 관련 값
- kMDItemFSName: 설명: MDItem 메타데이터의 파일 시스템 이름 관련 값
- kMDItemFSNodeCount: 설명: MDItem 메타데이터의 파일 시스템 노드 개수 관련 값
- kMDItemFSOwnerGroupID: 설명: MDItem 메타데이터의 파일 시스템 소유자 Group ID 관련 값
- kMDItemFSOwnerUserID: 설명: MDItem 메타데이터의 파일 시스템 소유자 사용자 ID 관련 값
- kMDItemPath: 설명: MDItem 메타데이터의 경로 관련 값

### image_attributes.json

- kMDItemAcquisitionMake: 설명: MDItem 메타데이터의 Acquisition 제조사 관련 값
- kMDItemAcquisitionModel: 설명: MDItem 메타데이터의 Acquisition 모델 관련 값
- kMDItemAperture: 설명: MDItem 메타데이터의 조리개 관련 값
- kMDItemEXIFGPSVersion: 설명: MDItem 메타데이터의 EXIFGPS Version 관련 값
- kMDItemEXIFVersion: 설명: MDItem 메타데이터의 EXIF Version 관련 값
- kMDItemExposureMode: 설명: MDItem 메타데이터의 노출 모드 관련 값
- kMDItemExposureProgram: 설명: MDItem 메타데이터의 노출 프로그램 관련 값
- kMDItemExposureTimeSeconds: 설명: MDItem 메타데이터의 노출 시간 초 관련 값
- kMDItemExposureTimeString: 설명: MDItem 메타데이터의 노출 시간 문자열 관련 값
- kMDItemFNumber: 설명: MDItem 메타데이터의 F 번호 관련 값
- kMDItemFlashOnOff: 설명: MDItem 메타데이터의 플래시 켜짐 꺼짐 관련 값
- kMDItemFocalLength: 설명: MDItem 메타데이터의 초점 길이 관련 값
- kMDItemGPSTrack: 설명: MDItem 메타데이터의 GPS 트랙 관련 값
- kMDItemISOSpeed: 설명: MDItem 메타데이터의 ISO 속도 관련 값
- kMDItemImageDirection: 설명: MDItem 메타데이터의 이미지 방향 관련 값
- kMDItemLayerNames: 설명: MDItem 메타데이터의 레이어 이름 관련 값
- kMDItemMaxAperture: 설명: MDItem 메타데이터의 최대 조리개 관련 값
- kMDItemMeteringMode: 설명: MDItem 메타데이터의 측광 모드 관련 값
- kMDItemNamedLocation: 설명: MDItem 메타데이터의 명명된 위치 관련 값
- kMDItemProfileName: 설명: MDItem 메타데이터의 프로필 이름 관련 값
- kMDItemRedEyeOnOff: 설명: MDItem 메타데이터의 적색 눈 켜짐 꺼짐 관련 값
- kMDItemResolutionHeightDPI: 설명: MDItem 메타데이터의 해상도 높이 DPI 관련 값
- kMDItemResolutionWidthDPI: 설명: MDItem 메타데이터의 해상도 너비 DPI 관련 값
- kMDItemSpeed: 설명: MDItem 메타데이터의 속도 관련 값
- kMDItemTimestamp: 설명: MDItem 메타데이터의 타임스탬프 관련 값
- kMDItemWhiteBalance: 설명: MDItem 메타데이터의 화이트 밸런스 관련 값

### video_attributes.json

- kMDItemDeliveryType: 설명: MDItem 메타데이터의 전달 타입 관련 값
- kMDItemDirector: 설명: MDItem 메타데이터의 감독 관련 값
- kMDItemGenre: 설명: MDItem 메타데이터의 장르 관련 값
- kMDItemMediaTypes: 설명: MDItem 메타데이터의 미디어 타입 관련 값
- kMDItemOriginalFormat: 설명: MDItem 메타데이터의 원본 형식 관련 값
- kMDItemOriginalSource: 설명: MDItem 메타데이터의 원본 소스 관련 값
- kMDItemPerformers: 설명: MDItem 메타데이터의 연주자 관련 값
- kMDItemProducer: 설명: MDItem 메타데이터의 프로듀서 관련 값
- kMDItemStreamable: 설명: MDItem 메타데이터의 스트리밍 가능 관련 값

### mdimporter_constants.json

- kMDItemApplicationCategories: 설명: MDItem 메타데이터의 애플리케이션 카테고리 관련 값
- kMDItemCameraOwner: 설명: MDItem 메타데이터의 카메라 소유자 관련 값
- kMDItemContentTypeTree: 설명: MDItem 메타데이터의 콘텐츠 타입 트리 관련 값
- kMDItemEditors: 설명: MDItem 메타데이터의 편집자 관련 값
- kMDItemExecutableArchitectures: 설명: MDItem 메타데이터의 실행 가능 아키텍처 관련 값
- kMDItemExecutablePlatform: 설명: MDItem 메타데이터의 실행 가능 플랫폼 관련 값
- kMDItemFocalLength35mm: 설명: MDItem 메타데이터의 초점 길이 35 mm 관련 값
- kMDItemGPSAreaInformation: 설명: MDItem 메타데이터의 GPS 영역 정보 관련 값
- kMDItemGPSDOP: 설명: MDItem 메타데이터의 GPSDOP 관련 값
- kMDItemGPSDateStamp: 설명: MDItem 메타데이터의 GPS 날짜 스탬프 관련 값
- kMDItemGPSDestBearing: 설명: MDItem 메타데이터의 GPS 목적지 방위 관련 값
- kMDItemGPSDestDistance: 설명: MDItem 메타데이터의 GPS 목적지 거리 관련 값
- kMDItemGPSDestLatitude: 설명: MDItem 메타데이터의 GPS 목적지 위도 관련 값
- kMDItemGPSDestLongitude: 설명: MDItem 메타데이터의 GPS 목적지 경도 관련 값
- kMDItemGPSDifferental: 설명: MDItem 메타데이터의 GPS 차분 관련 값
- kMDItemGPSMapDatum: 설명: MDItem 메타데이터의 GPS 지도 데이텀 관련 값
- kMDItemGPSMeasureMode: 설명: MDItem 메타데이터의 GPS 측정 모드 관련 값
- kMDItemGPSProcessingMethod: 설명: MDItem 메타데이터의 GPS 처리 방법 관련 값
- kMDItemGPSStatus: 설명: MDItem 메타데이터의 GPS 상태 관련 값
- kMDItemHTMLContent: 설명: MDItem 메타데이터의 HTML 콘텐츠 관련 값
- kMDItemIsApplicationManaged: 설명: MDItem 메타데이터의 애플리케이션 관리됨 여부 관련 값
- kMDItemIsLikelyJunk: 설명: MDItem 메타데이터의 가능성 불필요 여부 관련 값
- kMDItemLensModel: 설명: MDItem 메타데이터의 렌즈 모델 관련 값
- kMDLabelAddedNotification: 설명: 라벨 메타데이터의 추가 알림 관련 값
- kMDLabelBundleURL: 설명: 라벨 메타데이터의 번들 URL 관련 값
- kMDLabelChangedNotification: 설명: 라벨 메타데이터의 변경 알림 관련 값
- kMDLabelContentChangeDate: 설명: 라벨 메타데이터의 콘텐츠 변경 날짜 관련 값
- kMDLabelDisplayName: 설명: 라벨 메타데이터의 표시 이름 관련 값
- kMDLabelIconData: 설명: 라벨 메타데이터의 아이콘 데이터 관련 값
- kMDLabelIconUUID: 설명: 라벨 메타데이터의 아이콘 UUID 관련 값
- kMDLabelIsMutuallyExclusiveSetMember: 설명: 라벨 메타데이터의 상호 독점 집합 멤버 여부 관련 값
- kMDLabelKind: 설명: 라벨 메타데이터의 종류 관련 값
- kMDLabelKindIsMutuallyExclusiveSetKey: 설명: 라벨 메타데이터의 종류 상호 독점 집합 키 여부 관련 값
- kMDLabelKindVisibilityKey: 설명: 라벨 메타데이터의 종류 가시성 키 관련 값
- kMDLabelLocalDomain: 설명: 라벨 메타데이터의 로컬 도메인 관련 값
- kMDLabelRemovedNotification: 설명: 라벨 메타데이터의 제거 알림 관련 값
- kMDLabelSetsFinderColor: 설명: 라벨 메타데이터의 설정 파인더 색상 관련 값
- kMDLabelUUID: 설명: 라벨 메타데이터의 UUID 관련 값
- kMDLabelUserDomain: 설명: 라벨 메타데이터의 사용자 도메인 관련 값
- kMDLabelVisibility: 설명: 라벨 메타데이터의 가시성 관련 값
- kMDPrivateVisibility: 설명: 비공개 메타데이터의 가시성 관련 값
- kMDPublicVisibility: 설명: 공개 메타데이터의 가시성 관련 값

### nsurl_resource_keys.json

- NSURLAddedToDirectoryDateKey: 설명: URL 리소스의 추가 디렉터리 날짜 키 관련 값
- NSURLApplicationIsScriptableKey: 설명: URL 리소스의 애플리케이션 스크립트 가능 키 여부 관련 값
- NSURLAttributeModificationDateKey: 설명: URL 리소스의 속성 수정 날짜 키 관련 값
- NSURLCanonicalPathKey: 설명: URL 리소스의 정규 경로 키 관련 값
- NSURLContentAccessDateKey: 설명: URL 리소스의 콘텐츠 접근 날짜 키 관련 값
- NSURLContentModificationDateKey: 설명: URL 리소스의 콘텐츠 수정 날짜 키 관련 값
- NSURLContentTypeKey: 설명: URL 리소스의 콘텐츠 타입 키 관련 값
- NSURLCreationDateKey: 설명: URL 리소스의 생성 날짜 키 관련 값
- NSURLCustomIconKey: 설명: URL 리소스의 사용자 지정 아이콘 키 관련 값
- NSURLDocumentIdentifierKey: 설명: URL 리소스의 문서 식별자 키 관련 값
- NSURLEffectiveIconKey: 설명: URL 리소스의 유효 아이콘 키 관련 값
- NSURLFileAllocatedSizeKey: 설명: URL 리소스의 파일 할당 크기 키 관련 값
- NSURLFileContentIdentifierKey: 설명: URL 리소스의 파일 콘텐츠 식별자 키 관련 값
- NSURLFileProtectionKey: 설명: URL 리소스의 파일 보호 키 관련 값
- NSURLFileResourceIdentifierKey: 설명: URL 리소스의 파일 리소스 식별자 키 관련 값
- NSURLFileResourceTypeKey: 설명: URL 리소스의 파일 리소스 타입 키 관련 값
- NSURLFileSecurityKey: 설명: URL 리소스의 파일 보안 키 관련 값
- NSURLFileSizeKey: 설명: URL 리소스의 파일 크기 키 관련 값
- NSURLGenerationIdentifierKey: 설명: URL 리소스의 세대 식별자 키 관련 값
- NSURLHasHiddenExtensionKey: 설명: URL 리소스의 숨김 확장자 키 여부 관련 값
- NSURLIsAliasFileKey: 설명: URL 리소스의 별칭 파일 키 여부 관련 값
- NSURLIsApplicationKey: 설명: URL 리소스의 애플리케이션 키 여부 관련 값
- NSURLIsDirectoryKey: 설명: URL 리소스의 디렉터리 키 여부 관련 값
- NSURLIsExcludedFromBackupKey: 설명: URL 리소스의 제외 From 백업 키 여부 관련 값
- NSURLIsExecutableKey: 설명: URL 리소스의 실행 가능 키 여부 관련 값
- NSURLIsHiddenKey: 설명: URL 리소스의 숨김 키 여부 관련 값
- NSURLIsMountTriggerKey: 설명: URL 리소스의 마운트 트리거 키 여부 관련 값
- NSURLIsPackageKey: 설명: URL 리소스의 패키지 키 여부 관련 값
- NSURLIsPurgeableKey: 설명: URL 리소스의 정리 가능 키 여부 관련 값
- NSURLIsReadableKey: 설명: URL 리소스의 읽기 가능 키 여부 관련 값
- NSURLIsRegularFileKey: 설명: URL 리소스의 일반 파일 키 여부 관련 값
- NSURLIsSparseKey: 설명: URL 리소스의 희소 키 여부 관련 값
- NSURLIsSymbolicLinkKey: 설명: URL 리소스의 심볼릭 링크 키 여부 관련 값
- NSURLIsSystemImmutableKey: 설명: URL 리소스의 시스템 변경 불가 키 여부 관련 값
- NSURLIsUbiquitousItemKey: 설명: URL 리소스의 iCloud 항목 키 여부 관련 값
- NSURLIsUserImmutableKey: 설명: URL 리소스의 사용자 변경 불가 키 여부 관련 값
- NSURLIsVolumeKey: 설명: URL 리소스의 볼륨 키 여부 관련 값
- NSURLIsWritableKey: 설명: URL 리소스의 쓰기 가능 키 여부 관련 값
- NSURLKeysOfUnsetValuesKey: 설명: URL 리소스의 키 Of 미설정 값 키 관련 값
- NSURLLabelColorKey: 설명: URL 리소스의 라벨 색상 키 관련 값
- NSURLLabelNumberKey: 설명: URL 리소스의 라벨 번호 키 관련 값
- NSURLLinkCountKey: 설명: URL 리소스의 링크 개수 키 관련 값
- NSURLLocalizedLabelKey: 설명: URL 리소스의 로컬라이즈된 라벨 키 관련 값
- NSURLLocalizedNameKey: 설명: URL 리소스의 로컬라이즈된 이름 키 관련 값
- NSURLMayHaveExtendedAttributesKey: 설명: URL 리소스의 보유 확장 속성 키 여부 관련 값
- NSURLMayShareFileContentKey: 설명: URL 리소스의 공유 파일 콘텐츠 키 여부 관련 값
- NSURLNameKey: 설명: URL 리소스의 이름 키 관련 값
- NSURLParentDirectoryURLKey: 설명: URL 리소스의 부모 디렉터리 URL 키 관련 값
- NSURLPathKey: 설명: URL 리소스의 경로 키 관련 값
- NSURLPreferredIOBlockSizeKey: 설명: URL 리소스의 권장 I/O 블록 크기 키 관련 값
- NSURLQuarantinePropertiesKey: 설명: URL 리소스의 격리 속성 키 관련 값
- NSURLTagNamesKey: 설명: URL 리소스의 태그 이름 키 관련 값
- NSURLTotalFileAllocatedSizeKey: 설명: URL 리소스의 총 파일 할당 크기 키 관련 값
- NSURLTotalFileSizeKey: 설명: URL 리소스의 총 파일 크기 키 관련 값
- NSURLUbiquitousItemContainerDisplayNameKey: 설명: URL 리소스의 iCloud 항목 컨테이너 표시 이름 키 관련 값
- NSURLUbiquitousItemDownloadRequestedKey: 설명: URL 리소스의 iCloud 항목 다운로드 요청 키 관련 값
- NSURLUbiquitousItemDownloadingErrorKey: 설명: URL 리소스의 iCloud 항목 다운로드 중 오류 키 관련 값
- NSURLUbiquitousItemDownloadingStatusKey: 설명: URL 리소스의 iCloud 항목 다운로드 중 상태 키 관련 값
- NSURLUbiquitousItemHasUnresolvedConflictsKey: 설명: URL 리소스의 iCloud 항목 Unresolved 충돌 키 여부 관련 값
- NSURLUbiquitousItemIsDownloadingKey: 설명: URL 리소스의 iCloud 항목 다운로드 중 키 여부 관련 값
- NSURLUbiquitousItemIsExcludedFromSyncKey: 설명: URL 리소스의 iCloud 항목 제외 From Sync 키 여부 관련 값
- NSURLUbiquitousItemIsSharedKey: 설명: URL 리소스의 iCloud 항목 공유 키 여부 관련 값
- NSURLUbiquitousItemIsUploadedKey: 설명: URL 리소스의 iCloud 항목 업로드됨 키 여부 관련 값
- NSURLUbiquitousItemIsUploadingKey: 설명: URL 리소스의 iCloud 항목 업로드 중 키 여부 관련 값
- NSURLUbiquitousItemUploadingErrorKey: 설명: URL 리소스의 iCloud 항목 업로드 중 오류 키 관련 값
- NSURLUbiquitousSharedItemCurrentUserPermissionsKey: 설명: URL 리소스의 iCloud 공유 항목 Current 사용자 권한 키 관련 값
- NSURLUbiquitousSharedItemCurrentUserRoleKey: 설명: URL 리소스의 iCloud 공유 항목 Current 사용자 역할 키 관련 값
- NSURLUbiquitousSharedItemMostRecentEditorNameComponentsKey: 설명: URL 리소스의 iCloud 공유 항목 가장 최근 편집자 이름 Components 키 관련 값
- NSURLUbiquitousSharedItemOwnerNameComponentsKey: 설명: URL 리소스의 iCloud 공유 항목 소유자 이름 Components 키 관련 값
- NSURLVolumeAvailableCapacityForImportantUsageKey: 설명: URL 리소스의 볼륨 가용 용량 For 중요 Usage 키 관련 값
- NSURLVolumeAvailableCapacityForOpportunisticUsageKey: 설명: URL 리소스의 볼륨 가용 용량 For 우선순위 낮음 Usage 키 관련 값
- NSURLVolumeAvailableCapacityKey: 설명: URL 리소스의 볼륨 가용 용량 키 관련 값
- NSURLVolumeCreationDateKey: 설명: URL 리소스의 볼륨 생성 날짜 키 관련 값
- NSURLVolumeIdentifierKey: 설명: URL 리소스의 볼륨 식별자 키 관련 값
- NSURLVolumeIsAutomountedKey: 설명: URL 리소스의 볼륨 자동 마운트 키 여부 관련 값
- NSURLVolumeIsBrowsableKey: 설명: URL 리소스의 볼륨 탐색 가능 키 여부 관련 값
- NSURLVolumeIsEjectableKey: 설명: URL 리소스의 볼륨 꺼내기 가능 키 여부 관련 값
- NSURLVolumeIsEncryptedKey: 설명: URL 리소스의 볼륨 암호화 키 여부 관련 값
- NSURLVolumeIsInternalKey: 설명: URL 리소스의 볼륨 내부 키 여부 관련 값
- NSURLVolumeIsJournalingKey: 설명: URL 리소스의 볼륨 저널링 키 여부 관련 값
- NSURLVolumeIsLocalKey: 설명: URL 리소스의 볼륨 로컬 키 여부 관련 값
- NSURLVolumeIsReadOnlyKey: 설명: URL 리소스의 볼륨 Read Only 키 여부 관련 값
- NSURLVolumeIsRemovableKey: 설명: URL 리소스의 볼륨 이동식 키 여부 관련 값
- NSURLVolumeIsRootFileSystemKey: 설명: URL 리소스의 볼륨 루트 파일 시스템 키 여부 관련 값
- NSURLVolumeLocalizedFormatDescriptionKey: 설명: URL 리소스의 볼륨 로컬라이즈된 형식 설명 키 관련 값
- NSURLVolumeLocalizedNameKey: 설명: URL 리소스의 볼륨 로컬라이즈된 이름 키 관련 값
- NSURLVolumeMaximumFileSizeKey: 설명: URL 리소스의 볼륨 최대 파일 크기 키 관련 값
- NSURLVolumeNameKey: 설명: URL 리소스의 볼륨 이름 키 관련 값
- NSURLVolumeResourceCountKey: 설명: URL 리소스의 볼륨 리소스 개수 키 관련 값
- NSURLVolumeSupportsAccessPermissionsKey: 설명: URL 리소스의 볼륨 접근 권한 키 여부 관련 값
- NSURLVolumeSupportsAdvisoryFileLockingKey: 설명: URL 리소스의 볼륨 자문 파일 잠금 키 여부 관련 값
- NSURLVolumeSupportsCasePreservedNamesKey: 설명: URL 리소스의 볼륨 대소문자 보존 이름 키 여부 관련 값
- NSURLVolumeSupportsCaseSensitiveNamesKey: 설명: URL 리소스의 볼륨 대소문자 민감 이름 키 여부 관련 값
- NSURLVolumeSupportsCompressionKey: 설명: URL 리소스의 볼륨 압축 키 여부 관련 값
- NSURLVolumeSupportsExclusiveRenamingKey: 설명: URL 리소스의 볼륨 독점 이름 변경 키 여부 관련 값
- NSURLVolumeSupportsExtendedSecurityKey: 설명: URL 리소스의 볼륨 확장 보안 키 여부 관련 값
- NSURLVolumeSupportsFileCloningKey: 설명: URL 리소스의 볼륨 파일 클로닝 키 여부 관련 값
- NSURLVolumeSupportsFileProtectionKey: 설명: URL 리소스의 볼륨 파일 보호 키 여부 관련 값
- NSURLVolumeSupportsHardLinksKey: 설명: URL 리소스의 볼륨 하드 링크 키 여부 관련 값
- NSURLVolumeSupportsImmutableFilesKey: 설명: URL 리소스의 볼륨 변경 불가 Files 키 여부 관련 값
- NSURLVolumeSupportsJournalingKey: 설명: URL 리소스의 볼륨 저널링 키 여부 관련 값
- NSURLVolumeSupportsPersistentIDsKey: 설명: URL 리소스의 볼륨 영속 I Ds 키 여부 관련 값
- NSURLVolumeSupportsRenamingKey: 설명: URL 리소스의 볼륨 이름 변경 키 여부 관련 값
- NSURLVolumeSupportsRootDirectoryDatesKey: 설명: URL 리소스의 볼륨 루트 디렉터리 날짜 키 여부 관련 값
- NSURLVolumeSupportsSparseFilesKey: 설명: URL 리소스의 볼륨 희소 Files 키 여부 관련 값
- NSURLVolumeSupportsSwapRenamingKey: 설명: URL 리소스의 볼륨 교환 이름 변경 키 여부 관련 값
- NSURLVolumeSupportsSymbolicLinksKey: 설명: URL 리소스의 볼륨 심볼릭 링크 키 여부 관련 값
- NSURLVolumeSupportsVolumeSizesKey: 설명: URL 리소스의 볼륨 볼륨 크기 키 여부 관련 값
- NSURLVolumeSupportsZeroRunsKey: 설명: URL 리소스의 볼륨 제로 런 키 여부 관련 값
- NSURLVolumeTotalCapacityKey: 설명: URL 리소스의 볼륨 총 용량 키 관련 값
- NSURLVolumeURLForRemountingKey: 설명: URL 리소스의 볼륨 URL For Remounting 키 관련 값
- NSURLVolumeURLKey: 설명: URL 리소스의 볼륨 URL 키 관련 값
- NSURLVolumeUUIDStringKey: 설명: URL 리소스의 볼륨 UUID 문자열 키 관련 값

### load_attribute_data.py 주입

- kMDItemDownloadedDate: 설명: MDItem 메타데이터의 다운로드 날짜 관련 값(레지스트리에 이미 포함됨)

## 레지스트리에만 존재하는 키

없음

## 참고 사항

- `nsurl_resource_keys.json`/`mdimporter_constants.json` 항목은 현재 레지스트리에 포함되어 있지 않다.
- 레지스트리는 검색/DSL에서 사용하는 subset만 정의하고 있으므로 전체 MDItem/NSURL 상수와 1:1 매칭되지 않는다.
