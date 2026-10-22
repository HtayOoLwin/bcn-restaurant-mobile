from datetime import datetime, timedelta
from decimal import Decimal
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "bcn_restaurant" / "domain" / "room_charges.py"
spec = importlib.util.spec_from_file_location("room_charges", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_room_duration_rounding():
    start = datetime(2026, 10, 22, 10)
    samples = {0: "1", 1: "1", 60: "1", 61: "1.5", 75: "1.5", 90: "1.5", 91: "2", 102: "2", 120: "2", 121: "2.5"}
    for minutes, expected in samples.items():
        assert module.room_billable_hours(start, start + timedelta(minutes=minutes)) == Decimal(expected)


def test_room_amount():
    start = datetime(2026, 10, 22, 10)
    assert module.room_amount(start, start + timedelta(minutes=102), 10000) == Decimal("20000")
