import pytest

from bcn_restaurant.domain.preparation import (
    can_serve_whole,
    kitchen_next_status,
    summarize_statuses,
)


def test_kitchen_transition_sequence():
    assert kitchen_next_status("New", "Accept") == "Accepted"
    assert kitchen_next_status("Accepted", "Start Preparation") == "Preparing"
    assert kitchen_next_status("Preparing", "Mark Ready") == "Ready"


def test_kitchen_transition_rejects_stale_action():
    with pytest.raises(ValueError, match="not valid"):
        kitchen_next_status("Ready", "Mark Ready")


def test_summary_new_when_all_active_lines_are_new():
    result = summarize_statuses(["New", "New", "Cancelled"])
    assert result == {
        "summary": "New",
        "active_total": 2,
        "ready_count": 0,
        "served_count": 0,
    }


def test_summary_preparing_when_any_line_is_working():
    assert summarize_statuses(["New", "Accepted"])["summary"] == "Preparing"
    assert summarize_statuses(["Preparing", "New"])["summary"] == "Preparing"


def test_summary_partially_ready_when_ready_or_served_exists_with_pending_lines():
    assert summarize_statuses(["Ready", "Preparing"])["summary"] == "Partially Ready"
    assert summarize_statuses(["Served", "New"])["summary"] == "Partially Ready"


def test_summary_ready_to_serve_when_all_active_lines_are_ready_or_served():
    result = summarize_statuses(["Ready", "Served", "Cancelled"])
    assert result["summary"] == "Ready to Serve"
    assert result["ready_count"] == 1
    assert result["active_total"] == 2


def test_summary_served_when_all_active_lines_are_served():
    assert summarize_statuses(["Served", "Served"])["summary"] == "Served"


def test_empty_active_lines_fall_back_to_new():
    result = summarize_statuses(["Cancelled"])
    assert result["summary"] == "New"
    assert result["active_total"] == 0


def test_serve_whole_requires_at_least_one_ready_and_no_pending_active_lines():
    assert can_serve_whole(["Ready", "Served", "Cancelled"]) is True
    assert can_serve_whole(["Served", "Served"]) is False
    assert can_serve_whole(["Ready", "Preparing"]) is False
