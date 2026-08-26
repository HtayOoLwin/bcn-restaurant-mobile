import ast
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
API = ROOT / "bcn_restaurant" / "api"
SERVICES = ROOT / "bcn_restaurant" / "services"


def parse(path: Path):
    return ast.parse(path.read_text())


def function_names(path: Path):
    return {node.name for node in ast.walk(parse(path)) if isinstance(node, ast.FunctionDef)}


def whitelist_methods(path: Path, function_name: str):
    tree = parse(path)
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == function_name:
            for decorator in node.decorator_list:
                if isinstance(decorator, ast.Call) and isinstance(decorator.func, ast.Attribute):
                    if decorator.func.attr == "whitelist":
                        for keyword in decorator.keywords:
                            if keyword.arg == "methods" and isinstance(keyword.value, (ast.List, ast.Tuple)):
                                return [elt.value for elt in keyword.value.elts if isinstance(elt, ast.Constant)]
            return []
    raise AssertionError(f"{function_name} not found")


def test_preparation_service_contract_exists():
    names = function_names(SERVICES / "preparation.py")
    assert {"get_active_session_order_names", "assert_active_restaurant_order", "recalculate_sales_order"} <= names


def test_kitchen_api_contract_and_post_mutation():
    path = API / "kitchen.py"
    names = function_names(path)
    assert {"get_orders", "update_item_status"} <= names
    assert whitelist_methods(path, "update_item_status") == ["POST"]


def test_waiter_api_contract_and_post_mutations():
    path = API / "waiter.py"
    names = function_names(path)
    assert {"get_order_progress", "get_ready_orders", "item_action", "serve_whole_order"} <= names
    assert whitelist_methods(path, "item_action") == ["POST"]
    assert whitelist_methods(path, "serve_whole_order") == ["POST"]
