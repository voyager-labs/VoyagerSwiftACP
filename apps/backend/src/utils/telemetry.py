from __future__ import annotations

import logging
from typing import Any


def log_metric(name: str, value: float | int, tags: dict[str, Any] | None = None) -> None:
    logger = logging.getLogger("uvicorn.error")
    payload = {
        "metric": name,
        "value": value,
    }
    if tags:
        payload["tags"] = tags
    logger.info("%s", payload)
