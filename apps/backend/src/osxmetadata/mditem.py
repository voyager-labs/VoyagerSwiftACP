"""ctypes 기반 MDItem 접근 모듈 (읽기 전용)."""

from __future__ import annotations

import datetime
import logging
import typing as t
from ctypes import (
    CDLL,
    POINTER,
    byref,
    c_bool,
    c_char_p,
    c_double,
    c_int,
    c_long,
    c_uint32,
    c_void_p,
    create_string_buffer,
    string_at,
)
from typing import TYPE_CHECKING

from .attribute_data import (
    MDIMPORTER_ATTRIBUTE_DATA,
    MDITEM_ATTRIBUTE_DATA,
    MDITEM_ATTRIBUTE_SHORT_NAMES,
)

CFTypeRef = c_void_p
CFStringRef = c_void_p
CFArrayRef = c_void_p
CFDictionaryRef = c_void_p
CFNumberRef = c_void_p
CFDateRef = c_void_p
CFBooleanRef = c_void_p
CFDataRef = c_void_p
MDItemRef = c_void_p

# Absolute time in macOS is measured in seconds relative to Jan 1 2001 00:00:00 GMT.
MACOS_TIME_DELTA = (
    datetime.datetime(2001, 1, 1, 0, 0) - datetime.datetime(1970, 1, 1, 0, 0)
).total_seconds()

if TYPE_CHECKING:
    from .xattr_metadata import Tag

MDItemValueType = t.Union[
    bool,
    str,
    float,
    t.List[str],
    t.List["Tag"],
    datetime.datetime,
    None,
]

CF = CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
MD = CDLL(
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Metadata"
)

# CoreFoundation constants
kCFStringEncodingUTF8 = 0x08000100
kCFNumberDoubleType = 13

# CoreFoundation functions
CFGetTypeID = CF.CFGetTypeID
CFGetTypeID.argtypes = [CFTypeRef]
CFGetTypeID.restype = c_long

CFStringGetTypeID = CF.CFStringGetTypeID
CFStringGetTypeID.argtypes = []
CFStringGetTypeID.restype = c_long

CFNumberGetTypeID = CF.CFNumberGetTypeID
CFNumberGetTypeID.argtypes = []
CFNumberGetTypeID.restype = c_long

CFBooleanGetTypeID = CF.CFBooleanGetTypeID
CFBooleanGetTypeID.argtypes = []
CFBooleanGetTypeID.restype = c_long

CFDateGetTypeID = CF.CFDateGetTypeID
CFDateGetTypeID.argtypes = []
CFDateGetTypeID.restype = c_long

CFArrayGetTypeID = CF.CFArrayGetTypeID
CFArrayGetTypeID.argtypes = []
CFArrayGetTypeID.restype = c_long

CFDictionaryGetTypeID = CF.CFDictionaryGetTypeID
CFDictionaryGetTypeID.argtypes = []
CFDictionaryGetTypeID.restype = c_long

CFDataGetTypeID = CF.CFDataGetTypeID
CFDataGetTypeID.argtypes = []
CFDataGetTypeID.restype = c_long

CFRelease = CF.CFRelease
CFRelease.argtypes = [CFTypeRef]
CFRelease.restype = None

CFStringCreateWithCString = CF.CFStringCreateWithCString
CFStringCreateWithCString.argtypes = [c_void_p, c_char_p, c_uint32]
CFStringCreateWithCString.restype = CFStringRef

CFStringGetLength = CF.CFStringGetLength
CFStringGetLength.argtypes = [CFStringRef]
CFStringGetLength.restype = c_long

CFStringGetMaximumSizeForEncoding = CF.CFStringGetMaximumSizeForEncoding
CFStringGetMaximumSizeForEncoding.argtypes = [c_long, c_uint32]
CFStringGetMaximumSizeForEncoding.restype = c_long

CFStringGetCString = CF.CFStringGetCString
CFStringGetCString.argtypes = [CFStringRef, c_char_p, c_long, c_uint32]
CFStringGetCString.restype = c_bool

CFNumberGetValue = CF.CFNumberGetValue
CFNumberGetValue.argtypes = [CFNumberRef, c_int, c_void_p]
CFNumberGetValue.restype = c_bool

CFBooleanGetValue = CF.CFBooleanGetValue
CFBooleanGetValue.argtypes = [CFBooleanRef]
CFBooleanGetValue.restype = c_bool

CFDateGetAbsoluteTime = CF.CFDateGetAbsoluteTime
CFDateGetAbsoluteTime.argtypes = [CFDateRef]
CFDateGetAbsoluteTime.restype = c_double

CFArrayGetCount = CF.CFArrayGetCount
CFArrayGetCount.argtypes = [CFArrayRef]
CFArrayGetCount.restype = c_long

CFArrayGetValueAtIndex = CF.CFArrayGetValueAtIndex
CFArrayGetValueAtIndex.argtypes = [CFArrayRef, c_long]
CFArrayGetValueAtIndex.restype = CFTypeRef

CFDictionaryGetCount = CF.CFDictionaryGetCount
CFDictionaryGetCount.argtypes = [CFDictionaryRef]
CFDictionaryGetCount.restype = c_long

CFDictionaryGetKeysAndValues = CF.CFDictionaryGetKeysAndValues
CFDictionaryGetKeysAndValues.argtypes = [
    CFDictionaryRef,
    POINTER(CFTypeRef),
    POINTER(CFTypeRef),
]
CFDictionaryGetKeysAndValues.restype = None

CFDataGetLength = CF.CFDataGetLength
CFDataGetLength.argtypes = [CFDataRef]
CFDataGetLength.restype = c_long

CFDataGetBytePtr = CF.CFDataGetBytePtr
CFDataGetBytePtr.argtypes = [CFDataRef]
CFDataGetBytePtr.restype = c_void_p

CFCopyDescription = CF.CFCopyDescription
CFCopyDescription.argtypes = [CFTypeRef]
CFCopyDescription.restype = CFStringRef

# Metadata framework functions
MDItemCreate = MD.MDItemCreate
MDItemCreate.argtypes = [c_void_p, CFStringRef]
MDItemCreate.restype = MDItemRef

MDItemCopyAttribute = MD.MDItemCopyAttribute
MDItemCopyAttribute.argtypes = [MDItemRef, CFStringRef]
MDItemCopyAttribute.restype = CFTypeRef


class MDItemError(RuntimeError):
    """MDItem 생성/조회 중 발생하는 오류"""


def _cfstring_from_py(value: str) -> CFStringRef:
    return CFStringCreateWithCString(None, value.encode("utf-8"), kCFStringEncodingUTF8)


def _cfstring_to_py(value: CFStringRef) -> str:
    length = CFStringGetLength(value)
    max_size = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1
    buffer = create_string_buffer(max_size)
    if CFStringGetCString(value, buffer, max_size, kCFStringEncodingUTF8):
        return buffer.value.decode("utf-8")
    return ""


def _cfnumber_to_py(value: CFNumberRef) -> float:
    out = c_double()
    if CFNumberGetValue(value, kCFNumberDoubleType, byref(out)):
        return float(out.value)
    return 0.0


def _cfdate_to_py(value: CFDateRef) -> datetime.datetime:
    absolute = CFDateGetAbsoluteTime(value)
    return datetime.datetime.fromtimestamp(absolute + MACOS_TIME_DELTA)


def _cfdata_to_py(value: CFDataRef) -> bytes:
    length = CFDataGetLength(value)
    if length <= 0:
        return b""
    ptr = CFDataGetBytePtr(value)
    if not ptr:
        return b""
    return string_at(ptr, length)


def _cf_to_py(value: CFTypeRef) -> t.Any:
    if not value:
        return None
    type_id = CFGetTypeID(value)
    if type_id == CFStringGetTypeID():
        return _cfstring_to_py(value)
    if type_id == CFNumberGetTypeID():
        return _cfnumber_to_py(value)
    if type_id == CFBooleanGetTypeID():
        return bool(CFBooleanGetValue(value))
    if type_id == CFDateGetTypeID():
        return _cfdate_to_py(value)
    if type_id == CFArrayGetTypeID():
        count = CFArrayGetCount(value)
        return [_cf_to_py(CFArrayGetValueAtIndex(value, i)) for i in range(count)]
    if type_id == CFDictionaryGetTypeID():
        count = CFDictionaryGetCount(value)
        keys = (CFTypeRef * count)()
        values = (CFTypeRef * count)()
        CFDictionaryGetKeysAndValues(value, keys, values)
        return {_cf_to_py(keys[i]): _cf_to_py(values[i]) for i in range(count)}
    if type_id == CFDataGetTypeID():
        return _cfdata_to_py(value)
    description = CFCopyDescription(value)
    try:
        return _cfstring_to_py(description) if description else None
    finally:
        if description:
            CFRelease(description)


def create_mditem(path: str) -> MDItemRef:
    cf_path = _cfstring_from_py(path)
    try:
        mditem = MDItemCreate(None, cf_path)
    finally:
        if cf_path:
            CFRelease(cf_path)
    if not mditem:
        raise MDItemError(f"MDItem 생성 실패: {path}")
    return mditem


def release_mditem(mditem: MDItemRef) -> None:
    if mditem:
        CFRelease(mditem)


def get_mditem_metadata(mditem: MDItemRef, attribute: str) -> MDItemValueType:
    """MDItemCopyAttribute를 사용해 메타데이터를 읽는다."""
    if attribute in MDITEM_ATTRIBUTE_DATA:
        attribute_data = MDITEM_ATTRIBUTE_DATA[attribute]
    elif attribute in MDIMPORTER_ATTRIBUTE_DATA:
        attribute_data = MDIMPORTER_ATTRIBUTE_DATA[attribute]
    else:
        raise ValueError(f"Unknown attribute: {attribute}")

    cf_key = _cfstring_from_py(attribute)
    value_ref: CFTypeRef | None = None
    try:
        value_ref = MDItemCopyAttribute(mditem, cf_key)
        if not value_ref:
            return None
        converted = _cf_to_py(value_ref)
    finally:
        if value_ref:
            CFRelease(value_ref)
        if cf_key:
            CFRelease(cf_key)

    attribute_type = attribute_data.get("python_type")
    try:
        if converted is None:
            return None
        if attribute_type == "bool":
            return bool(converted)
        if attribute_type == "str":
            return str(converted)
        if attribute_type == "float":
            return float(converted)
        if attribute_type == "list":
            if isinstance(converted, str):
                return [x.strip() for x in converted.split(",")]
            return [str(x) for x in converted]
        if attribute_type == "datetime.datetime":
            return converted if isinstance(converted, datetime.datetime) else None
        if attribute_type == "list[datetime.datetime]":
            if isinstance(converted, list):
                return [x for x in converted if isinstance(x, datetime.datetime)]
            return None
        return converted
    except ValueError:
        logging.warning(
            "메타데이터 변환 실패 (%s) for %s to %s",
            converted,
            attribute,
            attribute_type,
        )
        return None


def remove_mditem_metadata(mditem: MDItemRef, attribute: str) -> None:
    """ctypes 버전에서는 쓰기/삭제를 지원하지 않는다."""
    raise NotImplementedError("ctypes 기반 메타데이터 삭제는 지원하지 않습니다")


def set_mditem_metadata(mditem: MDItemRef, attribute: str, value: MDItemValueType) -> bool:
    """ctypes 버전에서는 쓰기 기능을 지원하지 않는다."""
    raise NotImplementedError("ctypes 기반 메타데이터 쓰기는 지원하지 않습니다")


def set_or_remove_mditem_metadata(
    mditem: MDItemRef,
    attribute: str,
    value: MDItemValueType,
) -> bool:
    if value is None:
        remove_mditem_metadata(mditem, attribute)
    else:
        set_mditem_metadata(mditem, attribute, value)
    return True


def str_to_mditem_type(attribute: str, value: str) -> MDItemValueType:
    if attribute in MDITEM_ATTRIBUTE_DATA:
        attribute_data = MDITEM_ATTRIBUTE_DATA[attribute]
    elif attribute in MDITEM_ATTRIBUTE_SHORT_NAMES:
        attribute_data = MDITEM_ATTRIBUTE_DATA[MDITEM_ATTRIBUTE_SHORT_NAMES[attribute]]
    else:
        raise ValueError(f"Unknown attribute: {value}")

    attribute_type = attribute_data.get("python_type")
    if attribute_type == "str":
        return value
    if attribute_type == "bool":
        return bool(value)
    if attribute_type == "float":
        return float(value)
    if attribute_type == "list":
        return value
    if attribute_type == "datetime.datetime":
        return datetime.datetime.fromisoformat(value)
    if attribute_type == "list[datetime.datetime]":
        return datetime.datetime.fromisoformat(value)
    return value
