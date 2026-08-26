from bcn_restaurant.domain.session_access import can_use_session


def test_waiter_can_only_use_own_session():
    assert can_use_session('waiter@bcnrestaurant.com', 'waiter@bcnrestaurant.com', ['Waiter']) is True
    assert can_use_session('other@bcnrestaurant.com', 'waiter@bcnrestaurant.com', ['Waiter']) is False


def test_system_manager_and_administrator_can_use_any_session():
    assert can_use_session('other@bcnrestaurant.com', 'manager@example.com', ['System Manager']) is True
    assert can_use_session('other@bcnrestaurant.com', 'Administrator', ['Administrator']) is True
