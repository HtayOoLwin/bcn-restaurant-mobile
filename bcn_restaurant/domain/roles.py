from __future__ import annotations


def build_role_flags(roles: list[str] | tuple[str, ...] | set[str]) -> dict[str, bool]:
    role_set = set(roles)
    if "Administrator" in role_set:
        return {
            "waiter": True,
            "kitchen": True,
            "cashier": True,
            "manager": True,
        }

    return {
        "waiter": "Waiter" in role_set,
        "kitchen": "Kitchen" in role_set,
        "cashier": "Cashier" in role_set,
        "manager": "System Manager" in role_set,
    }
