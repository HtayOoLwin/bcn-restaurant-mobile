import ast
from pathlib import Path

API = Path(__file__).resolve().parents[1] / "bcn_restaurant" / "api"


def function_names(filename):
    tree = ast.parse((API / filename).read_text())
    return {node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)}


def test_phase1_api_functions_exist():
    assert "get_bootstrap" in function_names("bootstrap.py")
    assert "get_tables" in function_names("tables.py")
    assert "get_menu" in function_names("menu.py")
    assert "create_order" in function_names("orders.py")


def test_create_order_sets_pos_profile_from_restaurant_settings():
    tree = ast.parse((API / "orders.py").read_text())
    create_order = next(
        node
        for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name == "create_order"
    )

    assignments = [node for node in ast.walk(create_order) if isinstance(node, ast.Assign)]
    pos_profile_assignments = [
        node
        for node in assignments
        if any(
            isinstance(target, ast.Attribute)
            and isinstance(target.value, ast.Name)
            and target.value.id == "doc"
            and target.attr == "pos_profile"
            for target in node.targets
        )
    ]

    assert pos_profile_assignments
    assert ast.unparse(pos_profile_assignments[0].value) == "settings['pos_profile']"
