@preconcurrency import CoreServices
import Foundation

enum MetadataJSONEncoder {
    private nonisolated static let metadataKeys: [String] = [
        "_kMDItemUserTags",
        "kMDItemAcquisitionMake",
        "kMDItemAcquisitionModel",
        "kMDItemAlbum",
        "kMDItemAltitude",
        "kMDItemAperture",
        "kMDItemAppleLoopDescriptors",
        "kMDItemAppleLoopsKeyFilterType",
        "kMDItemAppleLoopsLoopMode",
        "kMDItemAppleLoopsRootKey",
        "kMDItemApplicationCategories",
        "kMDItemAttributeChangeDate",
        "kMDItemAudiences",
        "kMDItemAudioBitRate",
        "kMDItemAudioChannelCount",
        "kMDItemAudioEncodingApplication",
        "kMDItemAudioSampleRate",
        "kMDItemAudioTrackNumber",
        "kMDItemAuthorAddresses",
        "kMDItemAuthorEmailAddresses",
        "kMDItemAuthors",
        "kMDItemBitsPerSample",
        "kMDItemCFBundleIdentifier",
        "kMDItemCameraOwner",
        "kMDItemCity",
        "kMDItemCodecs",
        "kMDItemColorSpace",
        "kMDItemComment",
        "kMDItemComposer",
        "kMDItemContactKeywords",
        "kMDItemContentCreationDate",
        "kMDItemContentModificationDate",
        "kMDItemContentType",
        "kMDItemContentTypeTree",
        "kMDItemContributors",
        "kMDItemCopyright",
        "kMDItemCountry",
        "kMDItemCoverage",
        "kMDItemCreator",
        "kMDItemDateAdded",
        "kMDItemDeliveryType",
        "kMDItemDescription",
        "kMDItemDirector",
        "kMDItemDisplayName",
        "kMDItemDownloadedDate",
        "kMDItemDueDate",
        "kMDItemDurationSeconds",
        "kMDItemEXIFGPSVersion",
        "kMDItemEXIFVersion",
        "kMDItemEditors",
        "kMDItemEmailAddresses",
        "kMDItemEncodingApplications",
        "kMDItemExecutableArchitectures",
        "kMDItemExecutablePlatform",
        "kMDItemExposureMode",
        "kMDItemExposureProgram",
        "kMDItemExposureTimeSeconds",
        "kMDItemExposureTimeString",
        "kMDItemFNumber",
        "kMDItemFSContentChangeDate",
        "kMDItemFSCreationDate",
        "kMDItemFSHasCustomIcon",
        "kMDItemFSInvisible",
        "kMDItemFSIsExtensionHidden",
        "kMDItemFSIsStationery",
        "kMDItemFSLabel",
        "kMDItemFSName",
        "kMDItemFSNodeCount",
        "kMDItemFSOwnerGroupID",
        "kMDItemFSOwnerUserID",
        "kMDItemFSSize",
        "kMDItemFinderComment",
        "kMDItemFlashOnOff",
        "kMDItemFocalLength",
        "kMDItemFocalLength35mm",
        "kMDItemFonts",
        "kMDItemGPSAreaInformation",
        "kMDItemGPSDOP",
        "kMDItemGPSDateStamp",
        "kMDItemGPSDestBearing",
        "kMDItemGPSDestDistance",
        "kMDItemGPSDestLatitude",
        "kMDItemGPSDestLongitude",
        "kMDItemGPSDifferental",
        "kMDItemGPSMapDatum",
        "kMDItemGPSMeasureMode",
        "kMDItemGPSProcessingMethod",
        "kMDItemGPSStatus",
        "kMDItemGPSTrack",
        "kMDItemGenre",
        "kMDItemHTMLContent",
        "kMDItemHasAlphaChannel",
        "kMDItemHeadline",
        "kMDItemISOSpeed",
        "kMDItemIdentifier",
        "kMDItemImageDirection",
        "kMDItemInformation",
        "kMDItemInstantMessageAddresses",
        "kMDItemInstructions",
        "kMDItemIsApplicationManaged",
        "kMDItemIsGeneralMIDISequence",
        "kMDItemIsLikelyJunk",
        "kMDItemKeySignature",
        "kMDItemKeywords",
        "kMDItemKind",
        "kMDItemLanguages",
        "kMDItemLastUsedDate",
        "kMDItemLatitude",
        "kMDItemLayerNames",
        "kMDItemLensModel",
        "kMDItemLongitude",
        "kMDItemLyricist",
        "kMDItemMaxAperture",
        "kMDItemMediaTypes",
        "kMDItemMeteringMode",
        "kMDItemMusicalGenre",
        "kMDItemMusicalInstrumentCategory",
        "kMDItemMusicalInstrumentName",
        "kMDItemNamedLocation",
        "kMDItemNumberOfPages",
        "kMDItemOrganizations",
        "kMDItemOrientation",
        "kMDItemOriginalFormat",
        "kMDItemOriginalSource",
        "kMDItemPageHeight",
        "kMDItemPageWidth",
        "kMDItemParticipants",
        "kMDItemPath",
        "kMDItemPerformers",
        "kMDItemPhoneNumbers",
        "kMDItemPixelCount",
        "kMDItemPixelHeight",
        "kMDItemPixelWidth",
        "kMDItemProducer",
        "kMDItemProfileName",
        "kMDItemProjects",
        "kMDItemPublishers",
        "kMDItemRecipientAddresses",
        "kMDItemRecipientEmailAddresses",
        "kMDItemRecipients",
        "kMDItemRecordingDate",
        "kMDItemRecordingYear",
        "kMDItemRedEyeOnOff",
        "kMDItemResolutionHeightDPI",
        "kMDItemResolutionWidthDPI",
        "kMDItemRights",
        "kMDItemSecurityMethod",
        "kMDItemSpeed",
        "kMDItemStarRating",
        "kMDItemStateOrProvince",
        "kMDItemStreamable",
        "kMDItemSubject",
        "kMDItemTempo",
        "kMDItemTextContent",
        "kMDItemTheme",
        "kMDItemTimeSignature",
        "kMDItemTimestamp",
        "kMDItemTitle",
        "kMDItemTotalBitRate",
        "kMDItemURL",
        "kMDItemVersion",
        "kMDItemVideoBitRate",
        "kMDItemWhereFroms",
        "kMDItemWhiteBalance",
        "kMDLabelAddedNotification",
        "kMDLabelBundleURL",
        "kMDLabelChangedNotification",
        "kMDLabelContentChangeDate",
        "kMDLabelDisplayName",
        "kMDLabelIconData",
        "kMDLabelIconUUID",
        "kMDLabelIsMutuallyExclusiveSetMember",
        "kMDLabelKind",
        "kMDLabelKindIsMutuallyExclusiveSetKey",
        "kMDLabelKindVisibilityKey",
        "kMDLabelLocalDomain",
        "kMDLabelRemovedNotification",
        "kMDLabelSetsFinderColor",
        "kMDLabelUUID",
        "kMDLabelUserDomain",
        "kMDLabelVisibility",
        "kMDPrivateVisibility",
        "kMDPublicVisibility",
    ]

    @MainActor private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated static func attributes(from mdItem: MDItem) -> NSDictionary {
        MDItemCopyAttributes(mdItem, metadataKeys as CFArray) as NSDictionary? ?? [:]
    }

    @MainActor
    static func encode(mdItem: MDItem, path: String) -> String? {
        let attributes = Self.attributes(from: mdItem)
        return encode(attributes: attributes, path: path)
    }

    @MainActor
    static func encode(attributes: NSDictionary, path: String) -> String? {
        var payload: [String: Any] = [:]
        payload.reserveCapacity(metadataKeys.count)

        for key in metadataKeys {
            if key == "_kMDItemUserTags" {
                payload[key] = XattrMetadataReader.readUserTags(path: path)
                continue
            }
            if key == "kMDItemFinderComment" {
                if let value = attributes[key] {
                    payload[key] = jsonValue(from: value)
                } else if let comment = XattrMetadataReader.readComment(path: path) {
                    payload[key] = comment
                } else {
                    payload[key] = NSNull()
                }
                continue
            }
            if let value = attributes[key] {
                payload[key] = jsonValue(from: value)
            } else {
                payload[key] = NSNull()
            }
        }

        guard JSONSerialization.isValidJSONObject(payload) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @MainActor
    private static func jsonValue(from value: Any) -> Any {
        if let scalar = jsonScalarValue(from: value) {
            return scalar
        }
        if let array = jsonArrayValue(from: value) {
            return array
        }
        if let dict = jsonDictionaryValue(from: value) {
            return dict
        }
        if value is NSNull {
            return NSNull()
        }
        return String(describing: value)
    }

    @MainActor
    private static func jsonScalarValue(from value: Any) -> Any? {
        switch value {
        case let string as String:
            string
        case let bool as Bool:
            bool
        case let number as NSNumber:
            number
        case let date as Date:
            iso8601String(from: date)
        case let url as URL:
            url.path
        case let data as Data:
            data.base64EncodedString()
        default:
            nil
        }
    }

    @MainActor
    private static func jsonArrayValue(from value: Any) -> [Any]? {
        if let array = value as? [Any] {
            return array.map { jsonValue(from: $0) }
        }
        if let array = value as? NSArray {
            return array.map { jsonValue(from: $0) }
        }
        return nil
    }

    @MainActor
    private static func jsonDictionaryValue(from value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            var converted: [String: Any] = [:]
            converted.reserveCapacity(dict.count)
            for (key, value) in dict {
                converted[key] = jsonValue(from: value)
            }
            return converted
        }
        if let dict = value as? NSDictionary {
            var converted: [String: Any] = [:]
            converted.reserveCapacity(dict.count)
            for (key, value) in dict {
                converted[String(describing: key)] = jsonValue(from: value)
            }
            return converted
        }
        return nil
    }

    @MainActor
    private static func iso8601String(from date: Date) -> String {
        iso8601Formatter.string(from: date)
    }
}
