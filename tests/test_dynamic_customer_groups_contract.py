from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_server_tables_uses_leaf_customer_groups_with_enabled_customers():
    source = _read("server_scripts/mobile/tables.py")

    assert 'frappe.form_dict.get("customer_group")' in source
    assert '"Customer Group"' in source
    assert 'filters={"is_group": 0}' in source
    assert 'filters={"disabled": 0}' in source
    assert '"customer_groups": customer_groups' in source
    assert '"customer_group": customer_group' in source


def test_packaged_tables_api_exposes_dynamic_customer_groups():
    source = _read("bcn_restaurant/api/tables.py")

    assert "def get_tables(" in source
    assert "customer_group" in source
    assert '"Customer Group"' in source
    assert 'filters={"is_group": 0}' in source
    assert '"customer_groups": customer_groups' in source


def test_mobile_waiter_uses_dynamic_customer_group_chips():
    screen = _read(
        "mobile/bcn_restaurant_mobile/lib/features/waiter/presentation/waiter_tables_screen.dart"
    )
    repository = _read(
        "mobile/bcn_restaurant_mobile/lib/features/waiter/data/tables_repository.dart"
    )
    models = _read(
        "mobile/bcn_restaurant_mobile/lib/features/waiter/domain/table_models.dart"
    )

    assert "String customerGroup = '';" in screen
    assert "for (final group in response.customerGroups)" in screen
    assert "label: Text(group)" in screen
    assert "serviceType == 'dine_in'" not in screen
    assert "serviceType == 'takeaway'" not in screen

    assert "getTables(String customerGroup)" in repository
    assert "'customer_group': customerGroup" in repository
    assert "'service_type': serviceType" not in repository

    assert "required this.customerGroups" in models
    assert "json['customer_groups']" in models
    assert "final List<String> customerGroups;" in models
