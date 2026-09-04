from __future__ import annotations


def build_role_flags(roles: list[str] | tuple[str, ...] | set[str]) -> dict[str, bool]:
    role_set = set(roles)
    administrator = "Administrator" in role_set
    manager = administrator or bool(role_set.intersection({"Restaurant Manager", "System Manager"}))
    cashier = administrator or "Cashier" in role_set

    return {
        "waiter": administrator or "Waiter" in role_set,
        "cashier": cashier,
        "manager": manager,
        "can_request_cashier_print": cashier or manager,
        "can_view_print_status": cashier or manager,
        "can_retry_print_jobs": manager,
    }
