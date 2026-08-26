import json

import pytest

from bcn_restaurant.domain.order_payload import normalize_items, validate_client_order_id


def test_validate_client_order_id_accepts_uuid():
    value = "550e8400-e29b-41d4-a716-446655440000"
    assert validate_client_order_id(value) == value


def test_validate_client_order_id_rejects_non_uuid():
    with pytest.raises(ValueError, match="valid UUID"):
        validate_client_order_id("not-a-uuid")


def test_normalize_items_rejects_zero_qty():
    with pytest.raises(ValueError, match="greater than zero"):
        normalize_items([{"item_code": "FOOD-001", "qty": 0}])


def test_normalize_items_preserves_duplicate_lines():
    result = normalize_items(
        [
            {"item_code": "FOOD-001", "qty": 1},
            {"item_code": "FOOD-001", "qty": 2},
        ]
    )
    assert [row["qty"] for row in result] == [1.0, 2.0]


def test_normalize_items_trims_kitchen_note_and_uom():
    result = normalize_items(
        [
            {
                "item_code": " FOOD-001 ",
                "qty": "2",
                "uom": " Plate ",
                "kitchen_note": "  No onion  ",
            }
        ]
    )
    assert result == [
        {
            "item_code": "FOOD-001",
            "qty": 2.0,
            "uom": "Plate",
            "kitchen_note": "No onion",
        }
    ]


def test_normalize_items_accepts_json_string_payload():
    payload = json.dumps([{"item_code": "FOOD-001", "qty": 1}])
    assert normalize_items(payload)[0]["item_code"] == "FOOD-001"
