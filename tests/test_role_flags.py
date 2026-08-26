import pytest

from bcn_restaurant.domain.roles import build_role_flags


def test_waiter_role_flag_only_enables_waiter_capability():
    flags = build_role_flags(["Waiter"])
    assert flags == {
        "waiter": True,
        "kitchen": False,
        "cashier": False,
        "manager": False,
    }


def test_system_manager_gets_manager_capability():
    flags = build_role_flags(["System Manager"])
    assert flags["manager"] is True


def test_administrator_gets_all_capabilities():
    flags = build_role_flags(["Administrator"])
    assert all(flags.values())
