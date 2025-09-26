from datetime import datetime
from typing import Optional

from osxmetadata import OSXMetaData


class VoyagerOSXMetaData(OSXMetaData):
    def get_str(self, key: str) -> Optional[str]:
        v_obj: object | None = self.get(key)
        if type(v_obj) is str:
            return v_obj
        if type(v_obj) is list:
            return v_obj[0] if v_obj else None
        return None

    def get_datetime(self, key: str, fallback_ts: float) -> datetime:
        v = self.get(key)
        if isinstance(v, datetime):
            return v
        return datetime.fromtimestamp(fallback_ts)

    def get_datetime_opt(self, key: str) -> Optional[datetime]:
        v = self.get(key)
        return v if isinstance(v, datetime) else None

    def get_tags(self, key: str) -> list[str]:
        v = self.get(key)
        if type(v) is list:
            try:
                return [str(x) for x in v]
            except Exception:
                return []
        return []

    def get_bool(self, key: str, default: bool = False) -> bool:
        v = self.get(key)
        return v if type(v) is bool else default
