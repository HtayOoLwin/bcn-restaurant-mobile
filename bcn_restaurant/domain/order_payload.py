from __future__ import annotations

import json
import uuid
from collections.abc import Iterable
from typing import Any


def validate_client_order_id(value: Any) -> str:
    text = str(value or "").strip()
    try:
        parsed = uuid.UUID(text)
    except (ValueError, AttributeError, TypeError) as exc:
        raise ValueError("client_order_id must be a valid UUID") from exc
    return str(parsed)


def normalize_items(items: str | Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    if isinstance(items, str):
        try:
            items = json.loads(items)
        except json.JSONDecodeError as exc:
            raise ValueError("items must be valid JSON") from exc

    if not isinstance(items, list) or not items:
        raise ValueError("items must contain at least one row")

    normalized: list[dict[str, Any]] = []
    for index, row in enumerate(items, start=1):
        if not isinstance(row, dict):
            raise ValueError(f"items row {index} must be an object")

        item_code = str(row.get("item_code") or "").strip()
        if not item_code:
            raise ValueError(f"items row {index} requires item_code")

        try:
            qty = float(row.get("qty"))
        except (TypeError, ValueError) as exc:
            raise ValueError(f"items row {index} qty must be a number") from exc
        if qty <= 0:
            raise ValueError(f"items row {index} qty must be greater than zero")

        clean: dict[str, Any] = {
            "item_code": item_code,
            "qty": qty,
        }

        uom = str(row.get("uom") or "").strip()
        if uom:
            clean["uom"] = uom

        kitchen_note = str(row.get("kitchen_note") or "").strip()
        if kitchen_note:
            clean["kitchen_note"] = kitchen_note

        normalized.append(clean)

    return normalized
