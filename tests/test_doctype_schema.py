import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "bcn_restaurant" / "bcn_restaurant" / "doctype"


def load_doctype(name):
    return json.loads((ROOT / name / f"{name}.json").read_text())


def test_restaurant_settings_is_single_and_has_required_configuration_fields():
    data = load_doctype("restaurant_settings")
    assert data["issingle"] == 1
    fields = {field["fieldname"]: field for field in data["fields"]}
    for fieldname in (
        "company",
        "pos_profile",
        "selling_price_list",
        "dine_in_customer_group",
        "takeaway_customer_group",
        "default_currency",
    ):
        assert fields[fieldname]["reqd"] == 1


def test_restaurant_table_session_has_expected_status_options():
    data = load_doctype("restaurant_table_session")
    fields = {field["fieldname"]: field for field in data["fields"]}
    assert fields["status"]["options"].split("\n") == [
        "Open",
        "Billing",
        "Paid",
        "Closed",
        "Cancelled",
    ]
