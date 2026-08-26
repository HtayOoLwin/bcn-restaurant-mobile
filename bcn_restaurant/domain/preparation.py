from __future__ import annotations

KITCHEN_TRANSITIONS = {
    ("New", "Accept"): "Accepted",
    ("Accepted", "Start Preparation"): "Preparing",
    ("Preparing", "Mark Ready"): "Ready",
}


def kitchen_next_status(current_status: str, action: str) -> str:
    current = (current_status or "New").strip() or "New"
    requested = (action or "").strip()
    try:
        return KITCHEN_TRANSITIONS[(current, requested)]
    except KeyError as exc:
        raise ValueError(f"Action {requested or '<blank>'} is not valid for status {current}") from exc


def summarize_statuses(statuses: list[str]) -> dict[str, int | str]:
    normalized = [(status or "New").strip() or "New" for status in statuses]
    active = [status for status in normalized if status != "Cancelled"]
    active_total = len(active)
    ready_count = sum(status == "Ready" for status in active)
    served_count = sum(status == "Served" for status in active)
    working_count = sum(status in {"Accepted", "Preparing"} for status in active)

    summary = "New"
    if active_total and served_count == active_total:
        summary = "Served"
    elif active_total and ready_count + served_count == active_total:
        summary = "Ready to Serve"
    elif ready_count + served_count > 0:
        summary = "Partially Ready"
    elif working_count > 0:
        summary = "Preparing"

    return {
        "summary": summary,
        "active_total": active_total,
        "ready_count": ready_count,
        "served_count": served_count,
    }


def can_serve_whole(statuses: list[str]) -> bool:
    active = [(status or "New").strip() or "New" for status in statuses if (status or "New") != "Cancelled"]
    return any(status == "Ready" for status in active) and all(
        status in {"Ready", "Served"} for status in active
    )
