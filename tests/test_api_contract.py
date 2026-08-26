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
