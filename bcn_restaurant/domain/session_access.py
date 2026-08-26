from __future__ import annotations


def can_use_session(session_waiter: str | None, current_user: str, roles) -> bool:
    role_set = set(roles)
    if current_user == 'Administrator' or 'Administrator' in role_set or 'System Manager' in role_set:
        return True
    return bool(session_waiter) and session_waiter == current_user
