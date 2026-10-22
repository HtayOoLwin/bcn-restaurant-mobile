"""Pure duration rule for OurCity V2 room charge billing.

This reference helper is safe to import in Python tests. Frappe Server Script
uses restricted execution, so the calculation must be embedded or adapted in
the deployed API script (avoid import assumptions).
"""
from datetime import datetime
from decimal import Decimal, ROUND_CEILING


def room_billable_hours(check_in: datetime, check_out: datetime) -> Decimal:
    """First hour minimum, then every started half hour; result in Hours."""
    if check_out < check_in:
        raise ValueError("Check-out must not precede check-in")
    seconds = Decimal(str((check_out - check_in).total_seconds()))
    half_hours = max(2, int((seconds / Decimal("1800")).to_integral_value(rounding=ROUND_CEILING)))
    return Decimal(half_hours) / Decimal(2)


def room_amount(check_in: datetime, check_out: datetime, hourly_rate) -> Decimal:
    rate = Decimal(str(hourly_rate))
    if rate < 0:
        raise ValueError("Room rate must not be negative")
    return room_billable_hours(check_in, check_out) * rate
