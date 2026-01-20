# MDItem 레지스트리 커버리지 점검

- 작성일: 2026-01-20
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
- 레지스트리는 **도메인 키가 아니라 `system_keys` 매핑**을 기준으로 비교했다.
- `system_keys`의 `prefix:`를 제거한 실제 시스템 키로 커버리지를 계산했다.

## 요약

- 레지스트리 매핑 키 수(system_keys 기준): **295**
- 비교 대상 키 총합: **295**
- 레지스트리에 누락된 키: **0**
- 레지스트리에만 존재하는 키: **0**
- 전체 커버리지: **100.0%**

## 파일별 누락 현황

| 파일                                | 총 키 수 | 레지스트리 누락 | 커버리지 |
| ----------------------------------- | -------: | --------------: | -------: |
| `audio_attributes.json`             |       19 |               0 |   100.0% |
| `common_attributes.json`            |       57 |               0 |   100.0% |
| `filesystem_attributes.json`        |       12 |               0 |   100.0% |
| `image_attributes.json`             |       37 |               0 |   100.0% |
| `video_attributes.json`             |       13 |               0 |   100.0% |
| `mdimporter_constants.json`         |       44 |               0 |   100.0% |
| `nsurl_resource_keys.json`          |      113 |               0 |   100.0% |
| `load_attribute_data.py (injected)` |        1 |               0 |   100.0% |

## 프리픽스별 커버리지

| 프리픽스     | 총 키 수 | 레지스트리 누락 | 커버리지 |
| ------------ | -------: | --------------: | -------: |
| `NSURL`      |      113 |               0 |   100.0% |
| `kMDItem`    |      163 |               0 |   100.0% |
| `kMDLabel`   |       17 |               0 |   100.0% |
| `kMDPrivate` |        1 |               0 |   100.0% |
| `kMDPublic`  |        1 |               0 |   100.0% |
| `Other`      |        0 |               0 |     0.0% |

## 레지스트리 포함 키 (system_keys 기준)

- 레지스트리에 매핑된 system_keys를 **키 + 설명(원문)**으로 정리했다.

- NSURLAddedToDirectoryDateKey: 설명: The time at which the resource's was created or renamed into or within its parent directory, returned as an NSDate. Inconsistent behavior may be observed when this attribute is requested on hard-linked items. This property is not supported by all volumes. (read-only)
- NSURLApplicationIsScriptableKey: 설명:
- NSURLAttributeModificationDateKey: 설명: The time at which the resource's attributes were most recently modified, returned as an NSDate object if the volume supports attribute modification dates, or nil if attribute modification dates are unsupported (read-only).
- NSURLCanonicalPathKey: 설명:
- NSURLContentAccessDateKey: 설명: The time at which the resource was most recently accessed.
- NSURLContentModificationDateKey: 설명: The time at which the resource was most recently modified.
- NSURLContentTypeKey: 설명: The resource's type.
- NSURLCreationDateKey: 설명: The time at which the resource was created.
- NSURLCustomIconKey: 설명: The icon stored with the resource, returned as an NSImage object, or nil if the resource has no custom icon.
- NSURLDocumentIdentifierKey: 설명: The document identifier returned as an NSNumber (read-only).
- NSURLEffectiveIconKey: 설명: The resource's normal icon, returned as an NSImage object (read-only).
- NSURLFileAllocatedSizeKey: 설명: The key for the total size allocated on-disk for the file.
- NSURLFileContentIdentifierKey: 설명: The key for a value that APFS assigns to identify a file's content data stream.
- NSURLFileProtectionKey: 설명: The key for the protection level of the file.
- NSURLFileResourceIdentifierKey: 설명: The key for the resource's unique identifier.
- NSURLFileResourceTypeKey: 설명: The key for the resource's object type.
- NSURLFileSecurityKey: 설명: The key for the resource's security information.
- NSURLFileSizeKey: 설명: The key for the file's size, in bytes.
- NSURLGenerationIdentifierKey: 설명: An opaque generation identifier, returned as an id <NSCopying, NSCoding, NSObject> (read-only)
- NSURLHasHiddenExtensionKey: 설명: Key for determining whether the resource's extension is normally removed from its localized name, returned as a Boolean NSNumber object (read-write).
- NSURLIsAliasFileKey: 설명: The key for determining whether the file is an alias.
- NSURLIsApplicationKey: 설명:
- NSURLIsDirectoryKey: 설명: Key for determining whether the resource is a directory, returned as a Boolean NSNumber object (read-only).
- NSURLIsExcludedFromBackupKey: 설명: A key for indicating whether the system excludes the resource from all backups of app data.
- NSURLIsExecutableKey: 설명: Key for determining whether the current process (as determined by the EUID) can execute the resource (if it is a file) or search the resource (if it is a directory), returned as a Boolean NSNumber object (read-only).
- NSURLIsHiddenKey: 설명: Key for determining whether the resource is normally not displayed to users, returned as a Boolean NSNumber object (read-write).
- NSURLIsMountTriggerKey: 설명: Key for determining whether the URL is a file system trigger directory, returned as a Boolean NSNumber object (read-only). Traversing or opening a file system trigger directory causes an attempt to mount a file system on the directory.
- NSURLIsPackageKey: 설명: The key for determining whether the resource is a file package.
- NSURLIsPurgeableKey: 설명: The key for a Boolean value that indicates whether the file system can delete a file when the system needs to free space.
- NSURLIsReadableKey: 설명: Key for determining whether the current process (as determined by the EUID) can read the resource, returned as a Boolean NSNumber object (read-only).
- NSURLIsRegularFileKey: 설명: The key for determining whether the resource is a regular file rather than a directory or a symbolic link.
- NSURLIsSparseKey: 설명: The key for a Boolean value that indicates whether the file has sparse regions.
- NSURLIsSymbolicLinkKey: 설명: Key for determining whether the resource is a symbolic link, returned as a Boolean NSNumber object (read-only).
- NSURLIsSystemImmutableKey: 설명: Key for determining whether the resource's system immutable bit is set, returned as a Boolean NSNumber object (read-write).
- NSURLIsUbiquitousItemKey: 설명: The key for a Boolean value that indicates whether the item is in iCloud storage.
- NSURLIsUserImmutableKey: 설명: Key for determining whether the resource's user immutable bit is set, returned as a Boolean NSNumber object (read-write).
- NSURLIsVolumeKey: 설명: Key for determining whether the resource is the root directory of a volume, returned as a Boolean NSNumber object (read-only).
- NSURLIsWritableKey: 설명: Key for determining whether the current process (as determined by the EUID) can write to the resource, returned as a Boolean NSNumber object (read-only).
- NSURLKeysOfUnsetValuesKey: 설명: Key for the resource properties that have not been set after the setResourceValues:error: method returns an error, returned as an array of NSString objects.
- NSURLLabelColorKey: 설명: The resource's label color, returned as an NSColor object, or nil if the resource has no label color (read-only).
- NSURLLabelNumberKey: 설명: The resource's label number, returned as an NSNumber object (read-write).
- NSURLLinkCountKey: 설명: The number of hard links to the resource, returned as an NSNumber object (read-only).
- NSURLLocalizedLabelKey: 설명: The resource's localized label text, returned as an NSString object, or nil if the resource has no localized label text (read-only).
- NSURLLocalizedNameKey: 설명: The resource's localized or extension-hidden name, returned as an NSString object (read-only).
- NSURLMayHaveExtendedAttributesKey: 설명: The key for a Boolean value that indicates whether the file has extended attributes.
- NSURLMayShareFileContentKey: 설명: The key for a Boolean value that indicates whether cloned files and their original files may share data blocks.
- NSURLNameKey: 설명: The resource's name in the file system, returned as an NSString object (read-write).
- NSURLParentDirectoryURLKey: 설명: The parent directory of the resource, returned as an NSURL object, or nil if the resource is the root directory of its volume (read-only).
- NSURLPathKey: 설명: The file system path for the URL, returned as an NSString object (read-only).
- NSURLPreferredIOBlockSizeKey: 설명: The key for the optimal block size to use when reading or writing the file's data.
- NSURLQuarantinePropertiesKey: 설명:
- NSURLTagNamesKey: 설명: The names of tags attached to the resource, returned as an array of NSString values (read-write).
- NSURLTotalFileAllocatedSizeKey: 설명: The key for the total allocated size of the file, in bytes.
- NSURLTotalFileSizeKey: 설명: The key for the total displayable size of the file, in bytes.
- NSURLUbiquitousItemContainerDisplayNameKey: 설명: The key for a string that contains the name of the item's container as it appears to the user.
- NSURLUbiquitousItemDownloadRequestedKey: 설명: The key for a Boolean value that indicates whether the system has already made a call startDownloadingUbiquitousItemAtURL:error: to download the item.
- NSURLUbiquitousItemDownloadingErrorKey: 설명: The key for an error object that indicates why downloading the item from iCloud fails.
- NSURLUbiquitousItemDownloadingStatusKey: 설명: The key for the current download state for the item.
- NSURLUbiquitousItemHasUnresolvedConflictsKey: 설명: The key for a Boolean value that indicates whether this item has outstanding conflicts.
- NSURLUbiquitousItemIsDownloadingKey: 설명: The key for a Boolean value that indicates whether the system is downloading the item from iCloud.
- NSURLUbiquitousItemIsExcludedFromSyncKey: 설명: The key of a Boolean value that indicates whether the system excludes the item from syncing.
- NSURLUbiquitousItemIsSharedKey: 설명: The key for a Boolean value that indicates a shared item.
- NSURLUbiquitousItemIsUploadedKey: 설명: The key for a Boolean value that indicates whether the system uploads the item's data to iCloud storage.
- NSURLUbiquitousItemIsUploadingKey: 설명: The key for a Boolean value that indicates whether the system is uploading the item to iCloud.
- NSURLUbiquitousItemUploadingErrorKey: 설명: The key for an error object that indicates why uploading the item to iCloud fails.
- NSURLUbiquitousSharedItemCurrentUserPermissionsKey: 설명: The key for the current user's permissions.
- NSURLUbiquitousSharedItemCurrentUserRoleKey: 설명: The key for the role of the current user.
- NSURLUbiquitousSharedItemMostRecentEditorNameComponentsKey: 설명: The key for the name components of the most recent editor.
- NSURLUbiquitousSharedItemOwnerNameComponentsKey: 설명: The key for the name components of the item's owner.
- NSURLVolumeAvailableCapacityForImportantUsageKey: 설명: Key for the volume's available capacity in bytes for storing important resources (read-only).
- NSURLVolumeAvailableCapacityForOpportunisticUsageKey: 설명: Key for the volume's available capacity in bytes for storing nonessential resources (read-only).
- NSURLVolumeAvailableCapacityKey: 설명: Key for the volume's available capacity in bytes (read-only).
- NSURLVolumeCreationDateKey: 설명: Key for the volume's creation date, returned as an NSDate object, or NULL if it cannot be determined (read-only).
- NSURLVolumeIdentifierKey: 설명: The unique identifier of the resource's volume, returned as an id (read-only).
- NSURLVolumeIsAutomountedKey: 설명: Key for determining whether the volume is automounted, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeIsBrowsableKey: 설명: Key for determining whether the volume is visible in GUI-based file-browsing environments, such as the Desktop or the Finder application, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeIsEjectableKey: 설명: Key for determining whether the volume is ejectable from the drive mechanism under software control, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeIsEncryptedKey: 설명: Whether the volume is encrypted, returned as NSNumber containing a Boolean value (read-only).
- NSURLVolumeIsInternalKey: 설명: Key for determining whether the volume is connected to an internal bus, returned as a Boolean NSNumber object, or nil if it cannot be determined (read-only).
- NSURLVolumeIsJournalingKey: 설명: Key for determining whether the volume is currently journaling, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeIsLocalKey: 설명: Key for determining whether the volume is stored on a local device, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeIsReadOnlyKey: 설명: Key for determining whether the volume is read-only, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeIsRemovableKey: 설명: Key for determining whether the volume is removable from the drive mechanism, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeIsRootFileSystemKey: 설명: Whether the volume is the root filesystem, returned as NSNumber containing a Boolean value (read-only).
- NSURLVolumeLocalizedFormatDescriptionKey: 설명: Key for the volume's descriptive format name, returned as an NSString object (read-only).
- NSURLVolumeLocalizedNameKey: 설명: The name of the volume as it should be displayed in the user interface, returned as an NSString object (read-only).
- NSURLVolumeMaximumFileSizeKey: 설명: Key for the largest file size supported by the volume in bytes, returned as a Boolean NSNumber object, or nil if it cannot be determined (read-only).
- NSURLVolumeNameKey: 설명: The name of the volume, returned as an NSString object (read-write). Settable only if NSURLVolumeSupportsRenamingKey is YES.
- NSURLVolumeResourceCountKey: 설명: Key for the total number of resources on the volume, returned as an NSNumber object (read-only).
- NSURLVolumeSupportsAccessPermissionsKey: 설명:
- NSURLVolumeSupportsAdvisoryFileLockingKey: 설명: Key for determining whether the volume implements whole-file advisory locks in the style of flock, along with the O_EXLOCK and O_SHLOCK flags of the open function, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeSupportsCasePreservedNamesKey: 설명: Key for determining whether the volume supports case-preserved names, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeSupportsCaseSensitiveNamesKey: 설명: Key for determining whether the volume supports case-sensitive names, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeSupportsCompressionKey: 설명: Whether the volume supports transparent decompression of compressed files using decmpfs, returned as NSNumber containing a Boolean value (read-only).
- NSURLVolumeSupportsExclusiveRenamingKey: 설명: Whether the volume supports exclusive renaming using renamex_np(2) with the RENAME_EXCL option, returned as NSNumber containing a Boolean value (read-only).
- NSURLVolumeSupportsExtendedSecurityKey: 설명: Key for determining whether the volume supports extended security (access control lists), returned as a Boolean NSNumber object (read-only).
- NSURLVolumeSupportsFileCloningKey: 설명: Whether the volume supports cloning using clonefile(2), returned as NSNumber containing a Boolean value (read-only).
- NSURLVolumeSupportsFileProtectionKey: 설명: A Boolean value that indicates the volume supports data protection for files.
- NSURLVolumeSupportsHardLinksKey: 설명: Key for determining whether the volume supports hard links, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeSupportsImmutableFilesKey: 설명:
- NSURLVolumeSupportsJournalingKey: 설명: Key for determining whether the volume supports journaling, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeSupportsPersistentIDsKey: 설명: Key for determining whether the volume supports persistent IDs, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeSupportsRenamingKey: 설명: Key for determining whether the volume can be renamed, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeSupportsRootDirectoryDatesKey: 설명: Key for determining whether the volume supports reliable storage of times for the root directory, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeSupportsSparseFilesKey: 설명: Key for determining whether the volume supports sparse files, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeSupportsSwapRenamingKey: 설명: Whether the volume supports renaming using renamex_np(2) with the RENAME_SWAP option, returned as NSNumber containing a Boolean value (read-only).
- NSURLVolumeSupportsSymbolicLinksKey: 설명: Key for determining whether the volume supports symbolic links, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeSupportsVolumeSizesKey: 설명: Key for determining whether the volume supports returning volume size information, returned as a Boolean NSNumber object (read-only). If true, volume size information is available as values of the NSURLVolumeTotalCapacityKey andNSURLVolumeAvailableCapacityKey keys.
- NSURLVolumeSupportsZeroRunsKey: 설명: Key for determining whether the volume supports zero runs, returned as a Boolean NSNumber object (read-only).
- NSURLVolumeTotalCapacityKey: 설명: Key for the volume's total capacity in bytes (read-only).
- NSURLVolumeURLForRemountingKey: 설명: Key for the URL needed to remount the network volume, returned as an NSURL object, or nil if a URL is not available (read-only).
- NSURLVolumeURLKey: 설명: The root directory of the resource's volume, returned as an NSURL object (read-only).
- NSURLVolumeUUIDStringKey: 설명: Key for the volume's persistent UUID, returned as an NSString object, or nil if a persistent UUID is not available (read-only).
- kMDItemAcquisitionMake: 설명: The manufacturer of the device used to aquire the document contents.
- kMDItemAcquisitionModel: 설명: The model of the device used to aquire the document contents. For example, 100, 200, 400, etc.
- kMDItemAlbum: 설명: The title for a collection of media. This is analagous to a record album, or photo album.
- kMDItemAltitude: 설명: The altitude of the item in meters above sea level, expressed using the WGS84 datum. Negative values lie below sea level.
- kMDItemAperture: 설명: The aperture setting used to acquire the document contents. This unit is the APEX value.
- kMDItemAppleLoopDescriptors: 설명: Specifies multiple pieces of descriptive information about a loop.
- kMDItemAppleLoopsKeyFilterType: 설명: Specifies key filtering information about a loop. Loops are matched against projects that often in a major or minor key.
- kMDItemAppleLoopsLoopMode: 설명: Specifies how a file should be played.
- kMDItemAppleLoopsRootKey: 설명: Specifies the loop's original key. The key is the root note or tonic for the loop, and does not include the scale type.
- kMDItemApplicationCategories: 설명: Description not found.
- kMDItemAttributeChangeDate: 설명: The date and time of the last change made to a metadata attribute.
- kMDItemAudiences: 설명: The audience for which the file is intended. The audience may be determined by the creator or the publisher or by a third party.
- kMDItemAudioBitRate: 설명: The audio bit rate.
- kMDItemAudioChannelCount: 설명: Number of channels in the audio data contained in the file.
- kMDItemAudioEncodingApplication: 설명: The name of the application that encoded the data contained in the audio file.
- kMDItemAudioSampleRate: 설명: Sample rate of the audio data contained in the file. The sample rate is a float value representing hz (audio_frames/second). For example: 44100. 0, 22254. 54.
- kMDItemAudioTrackNumber: 설명: The track number of a song or composition when it is part of an album.
- kMDItemAuthorAddresses: 설명: This attribute indicates the author addresses of the document.
- kMDItemAuthorEmailAddresses: 설명: This attribute indicates the author of the emails message addresses. (This is always the email address, and not the human readable version).
- kMDItemAuthors: 설명: The author, or authors, of the contents of the file.
- kMDItemBitsPerSample: 설명: The number of bits per sample. For example, the bit depth of an image (8-bit, 16-bit etc. . . ) or the bit depth per audio sample of uncompressed audio data (8, 16, 24, 32, 64, etc. . ).
- kMDItemCFBundleIdentifier: 설명: If this item is a bundle, then this is the CFBundleIdentifier.
- kMDItemCameraOwner: 설명: Description not found.
- kMDItemCity: 설명: Identifies city of origin according to guidelines established by the provider.
- kMDItemCodecs: 설명: The codecs used to encode/decode the media.
- kMDItemColorSpace: 설명: The color space model used by the document contents. For example, "RGB", "CMYK", "YUV", or "YCbCr".
- kMDItemComment: 설명: A comment related to the file. This differs from the Finder comment, kMDItemFinderComment.
- kMDItemComposer: 설명: The composer of the music contained in the audio file.
- kMDItemContactKeywords: 설명: A list of contacts that are associated with this document, not including the authors.
- kMDItemContentCreationDate: 설명: The creation date of an edited or optimized version of the song or composition.
- kMDItemContentModificationDate: 설명: The date and time that the contents of the file were last modified.
- kMDItemContentType: 설명: The UTI pedigree of a file.
- kMDItemContentTypeTree: 설명: Description not found.
- kMDItemContributors: 설명: The entities responsible for making contributions to the content of the resource.
- kMDItemCopyright: 설명: The copyright owner of the file contents.
- kMDItemCountry: 설명: The full, publishable name of the country or region where the intellectual property of the item was created, according to guidelines of the provider.
- kMDItemCoverage: 설명: The extent or scope of the content of the resource.
- kMDItemCreator: 설명: Application used to create the document content (for example "Word", "Pages", and so on).
- kMDItemDateAdded: 설명: Description not found.
- kMDItemDeliveryType: 설명: The delivery type. Values are "Fast start" or "RTSP".
- kMDItemDescription: 설명: A description of the content of the resource. The description may include an abstract, table of contents, reference to a graphical representation of content or a free-text account of the content.
- kMDItemDirector: 설명: Directory of the movie.
- kMDItemDisplayName: 설명: The localized version of the file name.
- kMDItemDownloadedDate: 설명: Date the item was downloaded.
- kMDItemDueDate: 설명: Date this item is due.
- kMDItemDurationSeconds: 설명: The duration, in seconds, of the content of file. A value of 10. 5 represents media that is 10 and 1/2 seconds long.
- kMDItemEXIFGPSVersion: 설명: The version of GPSInfoIFD in EXIF used to generate the metadata.
- kMDItemEXIFVersion: 설명: The version of the EXIF header used to generate the metadata.
- kMDItemEditors: 설명: Description not found.
- kMDItemEmailAddresses: 설명: Email addresses related to this item.
- kMDItemEncodingApplications: 설명: Application used to convert the original content into it's current form. For example, a PDF file might have an encoding application set to "Distiller".
- kMDItemExecutableArchitectures: 설명: Description not found.
- kMDItemExecutablePlatform: 설명: Description not found.
- kMDItemExposureMode: 설명: The exposure mode used to acquire the document contents.
- kMDItemExposureProgram: 설명: The class of the exposure program used by the camera to set exposure when the image is taken. Possible values include: Manual, Normal, and Aperture priority.
- kMDItemExposureTimeSeconds: 설명: The exposure time, in seconds, used to acquire the document contents.
- kMDItemExposureTimeString: 설명: The time of the exposure.
- kMDItemFNumber: 설명: The diameter of the diaphragm aperture in terms of the effective focal length of the lens.
- kMDItemFSContentChangeDate: 설명: The date the file contents last changed.
- kMDItemFSCreationDate: 설명: The date and time that the file was created.
- kMDItemFSHasCustomIcon: 설명: Boolean indicating if this file has a custom icon.
- kMDItemFSInvisible: 설명: Indicates whether the file is invisible.
- kMDItemFSIsExtensionHidden: 설명: Indicates whether the file extension of the file is hidden.
- kMDItemFSIsStationery: 설명: Boolean indicating if this file is stationery.
- kMDItemFSLabel: 설명: Index of the Finder label of the file. Possible values are 0 through 7.
- kMDItemFSName: 설명: The file name of the item.
- kMDItemFSNodeCount: 설명: Number of files in a directory.
- kMDItemFSOwnerGroupID: 설명: The group ID of the owner of the file.
- kMDItemFSOwnerUserID: 설명: The user ID of the owner of the file.
- kMDItemFSSize: 설명: The size, in bytes, of the file on disk.
- kMDItemFinderComment: 설명: Finder comments for this file.
- kMDItemFlashOnOff: 설명: Indicates if a camera flash was used.
- kMDItemFocalLength: 설명: The actual focal length of the lens, in millimeters.
- kMDItemFocalLength35mm: 설명: Description not found.
- kMDItemFonts: 설명: Fonts used in this item. You should store the font's full name, the postscript name, or the font family name, based on the available information.
- kMDItemGPSAreaInformation: 설명: Description not found.
- kMDItemGPSDOP: 설명: Description not found.
- kMDItemGPSDateStamp: 설명: Description not found.
- kMDItemGPSDestBearing: 설명: Description not found.
- kMDItemGPSDestDistance: 설명: Description not found.
- kMDItemGPSDestLatitude: 설명: Description not found.
- kMDItemGPSDestLongitude: 설명: Description not found.
- kMDItemGPSDifferental: 설명: Description not found.
- kMDItemGPSMapDatum: 설명: Description not found.
- kMDItemGPSMeasureMode: 설명: Description not found.
- kMDItemGPSProcessingMethod: 설명: Description not found.
- kMDItemGPSStatus: 설명: Description not found.
- kMDItemGPSTrack: 설명: The direction of travel of the item, in degrees from true north.
- kMDItemGenre: 설명: Genre of the movie.
- kMDItemHTMLContent: 설명: Description not found.
- kMDItemHasAlphaChannel: 설명: Indicates if this image file has an alpha channel.
- kMDItemHeadline: 설명: A publishable entry providing a synopsis of the contents of the file. For example, "Apple Introduces the iPod Photo".
- kMDItemISOSpeed: 설명: The ISO speed used to acquire the document contents.
- kMDItemIdentifier: 설명: A formal identifier used to reference the resource within a given context.
- kMDItemImageDirection: 설명: The direction of the item's image, in degrees from true north.
- kMDItemInformation: 설명: Information about the item.
- kMDItemInstantMessageAddresses: 설명: Instant message addresses related to this item.
- kMDItemInstructions: 설명: Editorial instructions concerning the use of the item, such as embargoes and warnings. For example, "Second of four stories".
- kMDItemIsApplicationManaged: 설명: Description not found.
- kMDItemIsGeneralMIDISequence: 설명: Indicates whether the MIDI sequence contained in the file is setup for use with a General MIDI device.
- kMDItemIsLikelyJunk: 설명: Description not found.
- kMDItemKeySignature: 설명: The key of the music contained in the audio file. For example: C, Dm, F#m, Bb.
- kMDItemKeywords: 설명: Keywords associated with this file. For example, "Birthday", "Important", etc.
- kMDItemKind: 설명: A description of the kind of item this file represents.
- kMDItemLanguages: 설명: Indicates the languages of the intellectual content of the resource. Recommended best practice for the values of the Language element is defined by RFC 3066.
- kMDItemLastUsedDate: 설명: The date and time that the file was last used. This value is updated automatically by LaunchServices everytime a file is opened by double clicking, or by asking LaunchServices to open a file.
- kMDItemLatitude: 설명: The latitude of the item in degrees north of the equator, expressed using the WGS84 datum. Negative values lie south of the equator.
- kMDItemLayerNames: 설명: The names of the layers in the file.
- kMDItemLensModel: 설명: Description not found.
- kMDItemLongitude: 설명: The longitude of the item in degrees east of the prime meridian, expressed using the WGS84 datum. Negative values lie west of the prime meridian.
- kMDItemLyricist: 설명: The lyricist, or text writer, of the music contained in the audio file.
- kMDItemMaxAperture: 설명: The smallest f-number of the lens. Ordinarily it is given in the range of 00. 00 to 99. 99.
- kMDItemMediaTypes: 설명: The media types present in the content.
- kMDItemMeteringMode: 설명: The metering mode used to take the image.
- kMDItemMusicalGenre: 설명: The musical genre of the song or composition contained in the audio file. For example: Jazz, Pop, Rock, Classical.
- kMDItemMusicalInstrumentCategory: 설명: Specifies the category of an instrument.
- kMDItemMusicalInstrumentName: 설명: Specifies the name of instrument relative to the instrument category.
- kMDItemNamedLocation: 설명: The name of the location or point of interest associated with the item. The name may be user provided.
- kMDItemNumberOfPages: 설명: Number of pages in the document.
- kMDItemOrganizations: 설명: The company or organization that created the document.
- kMDItemOrientation: 설명: The orientation of the document contents. Possible values are 0 (landscape) and 1 (portrait).
- kMDItemOriginalFormat: 설명: Original format of the movie.
- kMDItemOriginalSource: 설명: Original source of the movie.
- kMDItemPageHeight: 설명: Height of the document page, in points (72 points per inch). For PDF files this indicates the height of the first page only.
- kMDItemPageWidth: 설명: Width of the document page, in points (72 points per inch). For PDF files this indicates the width of the first page only.
- kMDItemParticipants: 설명: The list of people who are visible in an image or movie or written about in a document.
- kMDItemPath: 설명: The complete path to the file.
- kMDItemPerformers: 설명: Performers in the movie.
- kMDItemPhoneNumbers: 설명: Phone numbers related to this item.
- kMDItemPixelCount: 설명: The total number of pixels in the contents. Same as kMDItemPixelWidth x kMDItemPixelHeight.
- kMDItemPixelHeight: 설명: The height, in pixels, of the contents. For example, the image height or the video frame height.
- kMDItemPixelWidth: 설명: The width, in pixels, of the contents. For example, the image width or the video frame width.
- kMDItemProducer: 설명: Producer of the content.
- kMDItemProfileName: 설명: The name of the color profile used by the document contents.
- kMDItemProjects: 설명: The list of projects that this file is part of. For example, if you were working on a movie all of the files could be marked as belonging to the project "My Movie".
- kMDItemPublishers: 설명: The entity responsible for making the resource available. For example, a person, an organization, or a service. Typically, the name of a publisher should be used to indicate the entity.
- kMDItemRecipientAddresses: 설명: This attribute indicates the recipient addresses of the document.
- kMDItemRecipientEmailAddresses: 설명: This attribute indicates the recipients email addresses. (This is always the email address, and not the human readable version).
- kMDItemRecipients: 설명: Recipients of this item.
- kMDItemRecordingDate: 설명: The recording date of the song or composition.
- kMDItemRecordingYear: 설명: Indicates the year the item was recorded. For example, 1964, 2003, etc.
- kMDItemRedEyeOnOff: 설명: Indicates if red-eye reduction was used to take the picture.
- kMDItemResolutionHeightDPI: 설명: Resolution height, in DPI, of this image.
- kMDItemResolutionWidthDPI: 설명: Resolution width, in DPI, of this image.
- kMDItemRights: 설명: Provides a link to information about rights held in and over the resource.
- kMDItemSecurityMethod: 설명: The security or encryption method used for the file.
- kMDItemSpeed: 설명: The speed of the item, in kilometers per hour.
- kMDItemStarRating: 설명: User rating of this item. For example, the stars rating of an iTunes track.
- kMDItemStateOrProvince: 설명: Identifies the province or state of origin according to guidelines established by the provider. For example, "CA", "Ontario", or "Sussex".
- kMDItemStreamable: 설명: Whether the content is prepared for streaming.
- kMDItemSubject: 설명: Subject of the this item.
- kMDItemTempo: 설명: A float value that specifies the beats per minute of the music contained in the audio file.
- kMDItemTextContent: 설명: Contains a text representation of the content of the document. Data in multiple fields should be combined using a whitespace character as a separator.
- kMDItemTheme: 설명: Theme of the this item.
- kMDItemTimeSignature: 설명: The time signature of the musical composition contained in the audio/MIDI file. For example: "4/4", "7/8".
- kMDItemTimestamp: 설명: The timestamp on the item. This generally is used to indicate the time at which the event captured by the item took place.
- kMDItemTitle: 설명: The title of the file. For example, this could be the title of a document, the name of a song, or the subject of an email message.
- kMDItemTotalBitRate: 설명: The total bit rate, audio and video combined, of the media.
- kMDItemURL: 설명: Url of the item.
- kMDItemVersion: 설명: The version number of this file.
- kMDItemVideoBitRate: 설명: The video bit rate.
- kMDItemWhereFroms: 설명: Describes where the file was obtained from.
- kMDItemWhiteBalance: 설명: The white balance setting used to acquire the document contents. Possible values are 0 (auto white balance) and 1 (manual).
- kMDLabelAddedNotification: 설명: Description not found.
- kMDLabelBundleURL: 설명: Description not found.
- kMDLabelChangedNotification: 설명: Description not found.
- kMDLabelContentChangeDate: 설명: Description not found.
- kMDLabelDisplayName: 설명: Description not found.
- kMDLabelIconData: 설명: Description not found.
- kMDLabelIconUUID: 설명: Description not found.
- kMDLabelIsMutuallyExclusiveSetMember: 설명: Description not found.
- kMDLabelKind: 설명: Description not found.
- kMDLabelKindIsMutuallyExclusiveSetKey: 설명: Description not found.
- kMDLabelKindVisibilityKey: 설명: Description not found.
- kMDLabelLocalDomain: 설명: Description not found.
- kMDLabelRemovedNotification: 설명: Description not found.
- kMDLabelSetsFinderColor: 설명: Description not found.
- kMDLabelUUID: 설명: Description not found.
- kMDLabelUserDomain: 설명: Description not found.
- kMDLabelVisibility: 설명: Description not found.
- kMDPrivateVisibility: 설명: Description not found.
- kMDPublicVisibility: 설명: Description not found.

## 레지스트리에 누락된 키 (전체)

- 파일별로 분류해 누락 키를 정리했다.
- 각 항목은 **키 + 설명(원문)**으로 표기했다.

### audio_attributes.json

- (없음)

### common_attributes.json

- (없음)

### filesystem_attributes.json

- (없음)

### image_attributes.json

- (없음)

### video_attributes.json

- (없음)

### mdimporter_constants.json

- (없음)

### nsurl_resource_keys.json

- (없음)

### load_attribute_data.py (injected)

- (없음)

## 레지스트리에만 존재하는 키

- (없음)
