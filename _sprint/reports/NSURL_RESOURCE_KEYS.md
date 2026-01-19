# NSURL Resource Keys 상세 문서

- 작성일: 2026-01-19
- 원본 데이터: `apps/backend/src/osxmetadata/attribute_data/nsurl_resource_keys.json`
- 총 키 수: 113

## 안내

- 원본 설명은 Apple 문서 기반 요약이며, 여기서는 한국어 설명과 예시를 추가했다.
- 예시는 이해를 돕기 위한 형태이며 실제 타입/값은 파일/볼륨/OS 상태에 따라 달라질 수 있다.

## NSURLIsApplicationKey

- 설명(한국어): URL 리소스의 애플리케이션 여부 관련 값
- 설명(원문): 제공되지 않음
- 버전: iOS 9.0+ iPadOS 9.0+ macOS 10.11+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLApplicationIsScriptableKey

- 설명(한국어): URL 리소스의 애플리케이션 스크립트 가능 여부 관련 값
- 설명(원문): 제공되지 않음
- 버전: macOS 10.11+
- 예시: 예: true/false

## NSURLIsDirectoryKey

- 설명(한국어): URL 리소스의 디렉터리 여부 관련 값
- 설명(원문): Key for determining whether the resource is a directory, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLParentDirectoryURLKey

- 설명(한국어): URL 리소스의 부모 디렉터리 URL 관련 값
- 설명(원문): The parent directory of the resource, returned as an NSURL object, or nil if the resource is the root directory of its volume (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: file:///Users/me/Documents/Report.pdf

## NSURLFileAllocatedSizeKey

- 설명(한국어): URL 리소스의 파일 할당 크기 관련 값
- 설명(원문): The key for the total size allocated on-disk for the file.
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 1048576 (bytes)

## NSURLFileProtectionKey

- 설명(한국어): URL 리소스의 파일 보호 관련 값
- 설명(원문): The key for the protection level of the file.
- 버전: iOS 9.0+ iPadOS 9.0+ macOS 10.11+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: (조회된 값)

## NSURLFileContentIdentifierKey

- 설명(한국어): URL 리소스의 파일 콘텐츠 식별자 관련 값
- 설명(원문): The key for a value that APFS assigns to identify a file's content data stream.
- 버전: iOS 14.0+ iPadOS 14.0+ macOS 11.0+ Mac Catalyst 14.0+ tvOS 14.0+ watchOS 7.0+
- 예시: 예: 12345

## NSURLFileResourceIdentifierKey

- 설명(한국어): URL 리소스의 파일 리소스 식별자 관련 값
- 설명(원문): The key for the resource's unique identifier.
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 12345

## NSURLFileResourceTypeKey

- 설명(한국어): URL 리소스의 파일 리소스 타입 관련 값
- 설명(원문): The key for the resource's object type.
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: (조회된 값)

## NSURLFileSecurityKey

- 설명(한국어): URL 리소스의 파일 보안 관련 값
- 설명(원문): The key for the resource's security information.
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: (조회된 값)

## NSURLFileSizeKey

- 설명(한국어): URL 리소스의 파일 크기 관련 값
- 설명(원문): The key for the file's size, in bytes.
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 1048576 (bytes)

## NSURLIsAliasFileKey

- 설명(한국어): URL 리소스의 별칭 파일 여부 관련 값
- 설명(원문): The key for determining whether the file is an alias.
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLIsPackageKey

- 설명(한국어): URL 리소스의 패키지 여부 관련 값
- 설명(원문): The key for determining whether the resource is a file package.
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLIsRegularFileKey

- 설명(한국어): URL 리소스의 일반 파일 여부 관련 값
- 설명(원문): The key for determining whether the resource is a regular file rather than a directory or a symbolic link.
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLIsPurgeableKey

- 설명(한국어): URL 리소스의 정리 가능 여부 관련 값
- 설명(원문): The key for a Boolean value that indicates whether the file system can delete a file when the system needs to free space.
- 버전: iOS 14.0+ iPadOS 14.0+ macOS 11.0+ Mac Catalyst 14.0+ tvOS 14.0+ watchOS 7.0+
- 예시: 예: true/false

## NSURLIsSparseKey

- 설명(한국어): URL 리소스의 희소 여부 관련 값
- 설명(원문): The key for a Boolean value that indicates whether the file has sparse regions.
- 버전: iOS 14.0+ iPadOS 14.0+ macOS 11.0+ Mac Catalyst 14.0+ tvOS 14.0+ watchOS 7.0+
- 예시: 예: true/false

## NSURLMayHaveExtendedAttributesKey

- 설명(한국어): URL 리소스의 보유 확장 속성 여부 관련 값
- 설명(원문): The key for a Boolean value that indicates whether the file has extended attributes.
- 버전: iOS 14.0+ iPadOS 14.0+ macOS 11.0+ Mac Catalyst 14.0+ tvOS 14.0+ watchOS 7.0+
- 예시: 예: true/false

## NSURLMayShareFileContentKey

- 설명(한국어): URL 리소스의 공유 파일 콘텐츠 여부 관련 값
- 설명(원문): The key for a Boolean value that indicates whether cloned files and their original files may share data blocks.
- 버전: iOS 14.0+ iPadOS 14.0+ macOS 11.0+ Mac Catalyst 14.0+ tvOS 14.0+ watchOS 7.0+
- 예시: 예: true/false

## NSURLPreferredIOBlockSizeKey

- 설명(한국어): URL 리소스의 권장 I/O 블록 크기 관련 값
- 설명(원문): The key for the optimal block size to use when reading or writing the file's data.
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 1048576 (bytes)

## NSURLTotalFileAllocatedSizeKey

- 설명(한국어): URL 리소스의 총 파일 할당 크기 관련 값
- 설명(원문): The key for the total allocated size of the file, in bytes.
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 1048576 (bytes)

## NSURLTotalFileSizeKey

- 설명(한국어): URL 리소스의 총 파일 크기 관련 값
- 설명(원문): The key for the total displayable size of the file, in bytes.
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 1048576 (bytes)

## NSURLVolumeAvailableCapacityKey

- 설명(한국어): URL 리소스의 볼륨 가용 용량 관련 값
- 설명(원문): Key for the volume's available capacity in bytes (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 1048576 (bytes)

## NSURLVolumeAvailableCapacityForImportantUsageKey

- 설명(한국어): URL 리소스의 볼륨 가용 용량 For 중요 Usage 관련 값
- 설명(원문): Key for the volume's available capacity in bytes for storing important resources (read-only).
- 버전: iOS 11.0+ iPadOS 11.0+ macOS 10.13+ Mac Catalyst 13.1+
- 예시: 예: 1048576 (bytes)

## NSURLVolumeAvailableCapacityForOpportunisticUsageKey

- 설명(한국어): URL 리소스의 볼륨 가용 용량 For 우선순위 낮음 Usage 관련 값
- 설명(원문): Key for the volume's available capacity in bytes for storing nonessential resources (read-only).
- 버전: iOS 11.0+ iPadOS 11.0+ macOS 10.13+ Mac Catalyst 13.1+
- 예시: 예: 1048576 (bytes)

## NSURLVolumeTotalCapacityKey

- 설명(한국어): URL 리소스의 볼륨 총 용량 관련 값
- 설명(원문): Key for the volume's total capacity in bytes (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 1048576 (bytes)

## NSURLVolumeIsAutomountedKey

- 설명(한국어): URL 리소스의 볼륨 자동 마운트 여부 관련 값
- 설명(원문): Key for determining whether the volume is automounted, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeIsBrowsableKey

- 설명(한국어): URL 리소스의 볼륨 탐색 가능 여부 관련 값
- 설명(원문): Key for determining whether the volume is visible in GUI-based file-browsing environments, such as the Desktop or the Finder application, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeIsEjectableKey

- 설명(한국어): URL 리소스의 볼륨 꺼내기 가능 여부 관련 값
- 설명(원문): Key for determining whether the volume is ejectable from the drive mechanism under software control, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeIsEncryptedKey

- 설명(한국어): URL 리소스의 볼륨 암호화 여부 관련 값
- 설명(원문): Whether the volume is encrypted, returned as NSNumber containing a Boolean value (read-only).
- 버전: iOS 10.0+ iPadOS 10.0+ macOS 10.12+ Mac Catalyst 13.1+ tvOS 10.0+ watchOS 3.0+
- 예시: 예: true/false

## NSURLVolumeIsInternalKey

- 설명(한국어): URL 리소스의 볼륨 내부 여부 관련 값
- 설명(원문): Key for determining whether the volume is connected to an internal bus, returned as a Boolean NSNumber object, or nil if it cannot be determined (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeIsJournalingKey

- 설명(한국어): URL 리소스의 볼륨 저널링 여부 관련 값
- 설명(원문): Key for determining whether the volume is currently journaling, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeIsLocalKey

- 설명(한국어): URL 리소스의 볼륨 로컬 여부 관련 값
- 설명(원문): Key for determining whether the volume is stored on a local device, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeIsReadOnlyKey

- 설명(한국어): URL 리소스의 볼륨 Read Only 여부 관련 값
- 설명(원문): Key for determining whether the volume is read-only, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeIsRemovableKey

- 설명(한국어): URL 리소스의 볼륨 이동식 여부 관련 값
- 설명(원문): Key for determining whether the volume is removable from the drive mechanism, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeIsRootFileSystemKey

- 설명(한국어): URL 리소스의 볼륨 루트 파일 시스템 여부 관련 값
- 설명(원문): Whether the volume is the root filesystem, returned as NSNumber containing a Boolean value (read-only).
- 버전: iOS 10.0+ iPadOS 10.0+ macOS 10.12+ Mac Catalyst 13.1+ tvOS 10.0+ watchOS 3.0+
- 예시: 예: true/false

## NSURLVolumeSupportsFileProtectionKey

- 설명(한국어): URL 리소스의 볼륨 파일 보호 여부 관련 값
- 설명(원문): A Boolean value that indicates the volume supports data protection for files.
- 버전: iOS 14.0+ iPadOS 14.0+ macOS 11.0+ Mac Catalyst 14.0+ tvOS 14.0+ watchOS 7.0+
- 예시: 예: true/false

## NSURLIsMountTriggerKey

- 설명(한국어): URL 리소스의 마운트 트리거 여부 관련 값
- 설명(원문): Key for determining whether the URL is a file system trigger directory, returned as a Boolean NSNumber object (read-only). Traversing or opening a file system trigger directory causes an attempt to mount a file system on the directory.
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLIsVolumeKey

- 설명(한국어): URL 리소스의 볼륨 여부 관련 값
- 설명(원문): Key for determining whether the resource is the root directory of a volume, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeCreationDateKey

- 설명(한국어): URL 리소스의 볼륨 생성 날짜 관련 값
- 설명(원문): Key for the volume's creation date, returned as an NSDate object, or NULL if it cannot be determined (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 2026-01-15T09:00:00Z

## NSURLVolumeIdentifierKey

- 설명(한국어): URL 리소스의 볼륨 식별자 관련 값
- 설명(원문): The unique identifier of the resource's volume, returned as an id (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 12345

## NSURLVolumeLocalizedFormatDescriptionKey

- 설명(한국어): URL 리소스의 볼륨 로컬라이즈된 형식 Description 관련 값
- 설명(원문): Key for the volume's descriptive format name, returned as an NSString object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: (조회된 값)

## NSURLVolumeLocalizedNameKey

- 설명(한국어): URL 리소스의 볼륨 로컬라이즈된 이름 관련 값
- 설명(원문): The name of the volume as it should be displayed in the user interface, returned as an NSString object (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: Report.pdf

## NSURLVolumeMaximumFileSizeKey

- 설명(한국어): URL 리소스의 볼륨 최대 파일 크기 관련 값
- 설명(원문): Key for the largest file size supported by the volume in bytes, returned as a Boolean NSNumber object, or nil if it cannot be determined (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 1048576 (bytes)

## NSURLVolumeNameKey

- 설명(한국어): URL 리소스의 볼륨 이름 관련 값
- 설명(원문): The name of the volume, returned as an NSString object (read-write). Settable only if NSURLVolumeSupportsRenamingKey is YES.
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: Report.pdf

## NSURLVolumeResourceCountKey

- 설명(한국어): URL 리소스의 볼륨 리소스 개수 관련 값
- 설명(원문): Key for the total number of resources on the volume, returned as an NSNumber object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 3

## NSURLVolumeSupportsAccessPermissionsKey

- 설명(한국어): URL 리소스의 볼륨 접근 권한 여부 관련 값
- 설명(원문): 제공되지 않음
- 버전: iOS 11.0+ iPadOS 11.0+ macOS 10.13+ Mac Catalyst 13.1+ tvOS 11.0+ watchOS 4.0+
- 예시: 예: true/false

## NSURLVolumeSupportsAdvisoryFileLockingKey

- 설명(한국어): URL 리소스의 볼륨 자문 파일 잠금 여부 관련 값
- 설명(원문): Key for determining whether the volume implements whole-file advisory locks in the style of flock, along with the O_EXLOCK and O_SHLOCK flags of the open function, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeSupportsCasePreservedNamesKey

- 설명(한국어): URL 리소스의 볼륨 대소문자 보존 이름 여부 관련 값
- 설명(원문): Key for determining whether the volume supports case-preserved names, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeSupportsCaseSensitiveNamesKey

- 설명(한국어): URL 리소스의 볼륨 대소문자 민감 이름 여부 관련 값
- 설명(원문): Key for determining whether the volume supports case-sensitive names, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeSupportsCompressionKey

- 설명(한국어): URL 리소스의 볼륨 압축 여부 관련 값
- 설명(원문): Whether the volume supports transparent decompression of compressed files using decmpfs, returned as NSNumber containing a Boolean value (read-only).
- 버전: iOS 10.0+ iPadOS 10.0+ macOS 10.12+ Mac Catalyst 13.1+ tvOS 10.0+ watchOS 3.0+
- 예시: 예: true/false

## NSURLVolumeSupportsExclusiveRenamingKey

- 설명(한국어): URL 리소스의 볼륨 독점 이름 변경 여부 관련 값
- 설명(원문): Whether the volume supports exclusive renaming using renamex_np(2) with the RENAME_EXCL option, returned as NSNumber containing a Boolean value (read-only).
- 버전: iOS 10.0+ iPadOS 10.0+ macOS 10.12+ Mac Catalyst 13.1+ tvOS 10.0+ watchOS 3.0+
- 예시: 예: true/false

## NSURLVolumeSupportsExtendedSecurityKey

- 설명(한국어): URL 리소스의 볼륨 확장 보안 여부 관련 값
- 설명(원문): Key for determining whether the volume supports extended security (access control lists), returned as a Boolean NSNumber object (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeSupportsFileCloningKey

- 설명(한국어): URL 리소스의 볼륨 파일 클로닝 여부 관련 값
- 설명(원문): Whether the volume supports cloning using clonefile(2), returned as NSNumber containing a Boolean value (read-only).
- 버전: iOS 10.0+ iPadOS 10.0+ macOS 10.12+ Mac Catalyst 13.1+ tvOS 10.0+ watchOS 3.0+
- 예시: 예: true/false

## NSURLVolumeSupportsHardLinksKey

- 설명(한국어): URL 리소스의 볼륨 하드 링크 여부 관련 값
- 설명(원문): Key for determining whether the volume supports hard links, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeSupportsImmutableFilesKey

- 설명(한국어): URL 리소스의 볼륨 변경 불가 Files 여부 관련 값
- 설명(원문): 제공되지 않음
- 버전: iOS 11.0+ iPadOS 11.0+ macOS 10.13+ Mac Catalyst 13.1+ tvOS 11.0+ watchOS 4.0+
- 예시: 예: true/false

## NSURLVolumeSupportsJournalingKey

- 설명(한국어): URL 리소스의 볼륨 저널링 여부 관련 값
- 설명(원문): Key for determining whether the volume supports journaling, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeSupportsPersistentIDsKey

- 설명(한국어): URL 리소스의 볼륨 영속 I Ds 여부 관련 값
- 설명(원문): Key for determining whether the volume supports persistent IDs, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeSupportsRenamingKey

- 설명(한국어): URL 리소스의 볼륨 이름 변경 여부 관련 값
- 설명(원문): Key for determining whether the volume can be renamed, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeSupportsRootDirectoryDatesKey

- 설명(한국어): URL 리소스의 볼륨 루트 디렉터리 날짜 여부 관련 값
- 설명(원문): Key for determining whether the volume supports reliable storage of times for the root directory, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeSupportsSparseFilesKey

- 설명(한국어): URL 리소스의 볼륨 희소 Files 여부 관련 값
- 설명(원문): Key for determining whether the volume supports sparse files, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeSupportsSwapRenamingKey

- 설명(한국어): URL 리소스의 볼륨 교환 이름 변경 여부 관련 값
- 설명(원문): Whether the volume supports renaming using renamex_np(2) with the RENAME_SWAP option, returned as NSNumber containing a Boolean value (read-only).
- 버전: iOS 10.0+ iPadOS 10.0+ macOS 10.12+ Mac Catalyst 13.1+ tvOS 10.0+ watchOS 3.0+
- 예시: 예: true/false

## NSURLVolumeSupportsSymbolicLinksKey

- 설명(한국어): URL 리소스의 볼륨 심볼릭 링크 여부 관련 값
- 설명(원문): Key for determining whether the volume supports symbolic links, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeSupportsVolumeSizesKey

- 설명(한국어): URL 리소스의 볼륨 볼륨 크기 여부 관련 값
- 설명(원문): Key for determining whether the volume supports returning volume size information, returned as a Boolean NSNumber object (read-only). If true, volume size information is available as values of the NSURLVolumeTotalCapacityKey andNSURLVolumeAvailableCapacityKey keys.
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeSupportsZeroRunsKey

- 설명(한국어): URL 리소스의 볼륨 제로 런 여부 관련 값
- 설명(원문): Key for determining whether the volume supports zero runs, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLVolumeURLForRemountingKey

- 설명(한국어): URL 리소스의 볼륨 URL For Remounting 관련 값
- 설명(원문): Key for the URL needed to remount the network volume, returned as an NSURL object, or nil if a URL is not available (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: file:///Users/me/Documents/Report.pdf

## NSURLVolumeURLKey

- 설명(한국어): URL 리소스의 볼륨 URL 관련 값
- 설명(원문): The root directory of the resource's volume, returned as an NSURL object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: file:///Users/me/Documents/Report.pdf

## NSURLVolumeUUIDStringKey

- 설명(한국어): URL 리소스의 볼륨 UUID 문자열 관련 값
- 설명(원문): Key for the volume's persistent UUID, returned as an NSString object, or nil if a persistent UUID is not available (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 12345

## NSURLIsUbiquitousItemKey

- 설명(한국어): URL 리소스의 iCloud 항목 여부 관련 값
- 설명(원문): The key for a Boolean value that indicates whether the item is in iCloud storage.
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLUbiquitousSharedItemMostRecentEditorNameComponentsKey

- 설명(한국어): URL 리소스의 iCloud 공유 항목 가장 최근 편집자 이름 Components 관련 값
- 설명(원문): The key for the name components of the most recent editor.
- 버전: iOS 10.0+ iPadOS 10.0+ macOS 10.12+ Mac Catalyst 13.1+
- 예시: 예: Report.pdf

## NSURLUbiquitousItemDownloadRequestedKey

- 설명(한국어): URL 리소스의 iCloud 항목 다운로드 요청 관련 값
- 설명(원문): The key for a Boolean value that indicates whether the system has already made a call startDownloadingUbiquitousItemAtURL:error: to download the item.
- 버전: iOS 8.0+ iPadOS 8.0+ macOS 10.10+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: (조회된 값)

## NSURLUbiquitousItemIsDownloadingKey

- 설명(한국어): URL 리소스의 iCloud 항목 다운로드 중 여부 관련 값
- 설명(원문): The key for a Boolean value that indicates whether the system is downloading the item from iCloud.
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLUbiquitousItemDownloadingErrorKey

- 설명(한국어): URL 리소스의 iCloud 항목 다운로드 중 오류 관련 값
- 설명(원문): The key for an error object that indicates why downloading the item from iCloud fails.
- 버전: iOS 7.0+ iPadOS 7.0+ macOS 10.9+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: (조회된 값)

## NSURLUbiquitousItemDownloadingStatusKey

- 설명(한국어): URL 리소스의 iCloud 항목 다운로드 중 상태 관련 값
- 설명(원문): The key for the current download state for the item.
- 버전: iOS 7.0+ iPadOS 7.0+ macOS 10.9+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: (조회된 값)

## NSURLUbiquitousItemIsExcludedFromSyncKey

- 설명(한국어): URL 리소스의 iCloud 항목 제외 From Sync 여부 관련 값
- 설명(원문): The key of a Boolean value that indicates whether the system excludes the item from syncing.
- 버전: iOS 14.5+ iPadOS 14.5+ macOS 11.3+ Mac Catalyst 14.5+ tvOS 14.5+ watchOS 7.4+
- 예시: 예: true/false

## NSURLUbiquitousItemIsUploadedKey

- 설명(한국어): URL 리소스의 iCloud 항목 업로드됨 여부 관련 값
- 설명(원문): The key for a Boolean value that indicates whether the system uploads the item's data to iCloud storage.
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLUbiquitousItemIsUploadingKey

- 설명(한국어): URL 리소스의 iCloud 항목 업로드 중 여부 관련 값
- 설명(원문): The key for a Boolean value that indicates whether the system is uploading the item to iCloud.
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLUbiquitousItemUploadingErrorKey

- 설명(한국어): URL 리소스의 iCloud 항목 업로드 중 오류 관련 값
- 설명(원문): The key for an error object that indicates why uploading the item to iCloud fails.
- 버전: iOS 7.0+ iPadOS 7.0+ macOS 10.9+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: (조회된 값)

## NSURLUbiquitousItemHasUnresolvedConflictsKey

- 설명(한국어): URL 리소스의 iCloud 항목 Unresolved 충돌 여부 관련 값
- 설명(원문): The key for a Boolean value that indicates whether this item has outstanding conflicts.
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLUbiquitousItemContainerDisplayNameKey

- 설명(한국어): URL 리소스의 iCloud 항목 컨테이너 Display 이름 관련 값
- 설명(원문): The key for a string that contains the name of the item's container as it appears to the user.
- 버전: iOS 8.0+ iPadOS 8.0+ macOS 10.10+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: Report.pdf

## NSURLUbiquitousSharedItemOwnerNameComponentsKey

- 설명(한국어): URL 리소스의 iCloud 공유 항목 소유자 이름 Components 관련 값
- 설명(원문): The key for the name components of the item's owner.
- 버전: iOS 10.0+ iPadOS 10.0+ macOS 10.12+ Mac Catalyst 13.1+
- 예시: 예: Report.pdf

## NSURLUbiquitousSharedItemCurrentUserPermissionsKey

- 설명(한국어): URL 리소스의 iCloud 공유 항목 Current 사용자 권한 관련 값
- 설명(원문): The key for the current user's permissions.
- 버전: iOS 10.0+ iPadOS 10.0+ macOS 10.12+ Mac Catalyst 13.1+
- 예시: 예: owner

## NSURLUbiquitousSharedItemCurrentUserRoleKey

- 설명(한국어): URL 리소스의 iCloud 공유 항목 Current 사용자 역할 관련 값
- 설명(원문): The key for the role of the current user.
- 버전: iOS 10.0+ iPadOS 10.0+ macOS 10.12+ Mac Catalyst 13.1+
- 예시: 예: owner

## NSURLUbiquitousItemIsSharedKey

- 설명(한국어): URL 리소스의 iCloud 항목 공유 여부 관련 값
- 설명(원문): The key for a Boolean value that indicates a shared item.
- 버전: iOS 10.0+ iPadOS 10.0+ macOS 10.12+ Mac Catalyst 13.1+
- 예시: 예: true/false

## NSURLKeysOfUnsetValuesKey

- 설명(한국어): URL 리소스의 키 미설정 값 관련 값
- 설명(원문): Key for the resource properties that have not been set after the setResourceValues:error: method returns an error, returned as an array of NSString objects.
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: (조회된 값)

## NSURLQuarantinePropertiesKey

- 설명(한국어): URL 리소스의 격리 속성 관련 값
- 설명(원문): 제공되지 않음
- 버전: macOS 10.10+
- 예시: 예: (조회된 값)

## NSURLAddedToDirectoryDateKey

- 설명(한국어): URL 리소스의 추가 디렉터리 날짜 관련 값
- 설명(원문): The time at which the resource's was created or renamed into or within its parent directory, returned as an NSDate. Inconsistent behavior may be observed when this attribute is requested on hard-linked items. This property is not supported by all volumes. (read-only)
- 버전: iOS 8.0+ iPadOS 8.0+ macOS 10.10+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 2026-01-15T09:00:00Z

## NSURLAttributeModificationDateKey

- 설명(한국어): URL 리소스의 속성 수정 날짜 관련 값
- 설명(원문): The time at which the resource's attributes were most recently modified, returned as an NSDate object if the volume supports attribute modification dates, or nil if attribute modification dates are unsupported (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 2026-01-15T09:00:00Z

## NSURLContentAccessDateKey

- 설명(한국어): URL 리소스의 콘텐츠 접근 날짜 관련 값
- 설명(원문): The time at which the resource was most recently accessed.
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 2026-01-15T09:00:00Z

## NSURLContentModificationDateKey

- 설명(한국어): URL 리소스의 콘텐츠 수정 날짜 관련 값
- 설명(원문): The time at which the resource was most recently modified.
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 2026-01-15T09:00:00Z

## NSURLCreationDateKey

- 설명(한국어): URL 리소스의 생성 날짜 관련 값
- 설명(원문): The time at which the resource was created.
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 2026-01-15T09:00:00Z

## NSURLCustomIconKey

- 설명(한국어): URL 리소스의 사용자 지정 아이콘 관련 값
- 설명(원문): The icon stored with the resource, returned as an NSImage object, or nil if the resource has no custom icon.
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: (조회된 값)

## NSURLDocumentIdentifierKey

- 설명(한국어): URL 리소스의 문서 식별자 관련 값
- 설명(원문): The document identifier returned as an NSNumber (read-only).
- 버전: iOS 8.0+ iPadOS 8.0+ macOS 10.10+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 12345

## NSURLEffectiveIconKey

- 설명(한국어): URL 리소스의 유효 아이콘 관련 값
- 설명(원문): The resource's normal icon, returned as an NSImage object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: (조회된 값)

## NSURLGenerationIdentifierKey

- 설명(한국어): URL 리소스의 세대 식별자 관련 값
- 설명(원문): An opaque generation identifier, returned as an id <NSCopying, NSCoding, NSObject> (read-only)
- 버전: iOS 8.0+ iPadOS 8.0+ macOS 10.10+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 12345

## NSURLHasHiddenExtensionKey

- 설명(한국어): URL 리소스의 숨김 확장자 여부 관련 값
- 설명(원문): Key for determining whether the resource's extension is normally removed from its localized name, returned as a Boolean NSNumber object (read-write).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLIsExcludedFromBackupKey

- 설명(한국어): URL 리소스의 제외 From 백업 여부 관련 값
- 설명(원문): A key for indicating whether the system excludes the resource from all backups of app data.
- 버전: iOS 5.1+ iPadOS 5.1+ macOS 10.8+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLIsExecutableKey

- 설명(한국어): URL 리소스의 실행 가능 여부 관련 값
- 설명(원문): Key for determining whether the current process (as determined by the EUID) can execute the resource (if it is a file) or search the resource (if it is a directory), returned as a Boolean NSNumber object (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLIsHiddenKey

- 설명(한국어): URL 리소스의 숨김 여부 관련 값
- 설명(원문): Key for determining whether the resource is normally not displayed to users, returned as a Boolean NSNumber object (read-write).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLIsReadableKey

- 설명(한국어): URL 리소스의 읽기 가능 여부 관련 값
- 설명(원문): Key for determining whether the current process (as determined by the EUID) can read the resource, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLIsSymbolicLinkKey

- 설명(한국어): URL 리소스의 심볼릭 링크 여부 관련 값
- 설명(원문): Key for determining whether the resource is a symbolic link, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLIsSystemImmutableKey

- 설명(한국어): URL 리소스의 시스템 변경 불가 여부 관련 값
- 설명(원문): Key for determining whether the resource's system immutable bit is set, returned as a Boolean NSNumber object (read-write).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLIsUserImmutableKey

- 설명(한국어): URL 리소스의 사용자 변경 불가 여부 관련 값
- 설명(원문): Key for determining whether the resource's user immutable bit is set, returned as a Boolean NSNumber object (read-write).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLIsWritableKey

- 설명(한국어): URL 리소스의 쓰기 가능 여부 관련 값
- 설명(원문): Key for determining whether the current process (as determined by the EUID) can write to the resource, returned as a Boolean NSNumber object (read-only).
- 버전: iOS 5.0+ iPadOS 5.0+ macOS 10.7+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: true/false

## NSURLLabelColorKey

- 설명(한국어): URL 리소스의 라벨 색상 관련 값
- 설명(원문): The resource's label color, returned as an NSColor object, or nil if the resource has no label color (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: red

## NSURLLabelNumberKey

- 설명(한국어): URL 리소스의 라벨 번호 관련 값
- 설명(원문): The resource's label number, returned as an NSNumber object (read-write).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 3

## NSURLLinkCountKey

- 설명(한국어): URL 리소스의 링크 개수 관련 값
- 설명(원문): The number of hard links to the resource, returned as an NSNumber object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: 3

## NSURLLocalizedLabelKey

- 설명(한국어): URL 리소스의 로컬라이즈된 라벨 관련 값
- 설명(원문): The resource's localized label text, returned as an NSString object, or nil if the resource has no localized label text (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: (조회된 값)

## NSURLLocalizedNameKey

- 설명(한국어): URL 리소스의 로컬라이즈된 이름 관련 값
- 설명(원문): The resource's localized or extension-hidden name, returned as an NSString object (read-only).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: Report.pdf

## NSURLNameKey

- 설명(한국어): URL 리소스의 이름 관련 값
- 설명(원문): The resource's name in the file system, returned as an NSString object (read-write).
- 버전: iOS 4.0+ iPadOS 4.0+ macOS 10.6+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: Report.pdf

## NSURLPathKey

- 설명(한국어): URL 리소스의 경로 관련 값
- 설명(원문): The file system path for the URL, returned as an NSString object (read-only).
- 버전: iOS 6.0+ iPadOS 6.0+ macOS 10.8+ Mac Catalyst 13.1+ tvOS 9.0+ watchOS 2.0+
- 예시: 예: /Users/me/Documents/Report.pdf

## NSURLCanonicalPathKey

- 설명(한국어): URL 리소스의 정규 경로 관련 값
- 설명(원문): 제공되지 않음
- 버전: iOS 10.0+ iPadOS 10.0+ macOS 10.12+ Mac Catalyst 13.1+ tvOS 10.0+ watchOS 3.0+
- 예시: 예: /Users/me/Documents/Report.pdf

## NSURLTagNamesKey

- 설명(한국어): URL 리소스의 태그 이름 관련 값
- 설명(원문): The names of tags attached to the resource, returned as an array of NSString values (read-write).
- 버전: macOS 10.9+
- 예시: 예: ["tax", "2024"]

## NSURLContentTypeKey

- 설명(한국어): URL 리소스의 콘텐츠 타입 관련 값
- 설명(원문): The resource's type.
- 버전: iOS 14.0+ iPadOS 14.0+ macOS 11.0+ Mac Catalyst 14.0+ tvOS 14.0+ watchOS 7.0+
- 예시: 예: (조회된 값)
