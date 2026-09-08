from __future__ import annotations

import argparse
import json
from pathlib import Path
from urllib.parse import quote

import requests


REQUEST_BILL_API = "bcn_request_for_bill"
CASHIER_BILLING_API = "bcn_cashier_billing"


def system_manager_permissions() -> list[dict]:
    return [
        {
            "role": "System Manager",
            "read": 1,
            "write": 1,
            "create": 1,
            "delete": 1,
            "print": 1,
            "email": 1,
            "export": 1,
            "share": 1,
        }
    ]


def sales_order_fields() -> list[dict]:
    return [
        {
            "label": "Mobile Billing Status",
            "fieldname": "custom_mobile_billing_status",
            "fieldtype": "Select",
            "options": "Ordering\nBill Requested\nPaid",
            "default": "Ordering",
            "hidden": 1,
            "allow_on_submit": 1,
        },
        {
            "label": "Bill Requested At",
            "fieldname": "custom_bill_requested_at",
            "fieldtype": "Datetime",
            "hidden": 1,
            "allow_on_submit": 1,
        },
        {
            "label": "Bill Requested By",
            "fieldname": "custom_bill_requested_by",
            "fieldtype": "Link",
            "options": "User",
            "hidden": 1,
            "allow_on_submit": 1,
        },
        {
            "label": "Mobile Sales Invoice",
            "fieldname": "custom_mobile_sales_invoice",
            "fieldtype": "Link",
            "options": "Sales Invoice",
            "hidden": 1,
            "allow_on_submit": 1,
        },
    ]


def cashier_print_settings_payload(module: str = "Selling") -> dict:
    return {
        "name": "Cashier Print Settings",
        "module": module,
        "custom": 1,
        "issingle": 1,
        "track_changes": 1,
        "fields": [
            {
                "label": "Printer Name",
                "fieldname": "printer_name",
                "fieldtype": "Data",
                "reqd": 1,
            },
            {
                "label": "Enabled",
                "fieldname": "enabled",
                "fieldtype": "Check",
                "default": "1",
            },
        ],
        "permissions": system_manager_permissions(),
    }


def cashier_print_queue_payload(module: str = "Selling") -> dict:
    return {
        "name": "Cashier Print Queue",
        "module": module,
        "custom": 1,
        "is_submittable": 0,
        "track_changes": 1,
        "autoname": "format:CPQ-{#####}",
        "sort_field": "creation",
        "sort_order": "ASC",
        "fields": [
            {
                "label": "Sales Invoice",
                "fieldname": "sales_invoice",
                "fieldtype": "Link",
                "options": "Sales Invoice",
                "reqd": 1,
                "in_list_view": 1,
            },
            {
                "label": "Sales Order",
                "fieldname": "sales_order",
                "fieldtype": "Link",
                "options": "Sales Order",
                "reqd": 1,
                "in_list_view": 1,
            },
            {
                "label": "Printer Name",
                "fieldname": "printer_name",
                "fieldtype": "Data",
                "reqd": 1,
                "in_list_view": 1,
            },
            {
                "label": "Status",
                "fieldname": "status",
                "fieldtype": "Select",
                "options": "Pending\nPrinting\nPrinted\nError",
                "default": "Pending",
                "reqd": 1,
                "in_list_view": 1,
                "in_standard_filter": 1,
            },
            {
                "label": "Retry Count",
                "fieldname": "retry_count",
                "fieldtype": "Int",
                "default": "0",
                "reqd": 1,
            },
            {
                "label": "Last Error",
                "fieldname": "last_error",
                "fieldtype": "Long Text",
            },
            {
                "label": "Printed At",
                "fieldname": "printed_at",
                "fieldtype": "Datetime",
            },
            {
                "label": "Queue Key",
                "fieldname": "queue_key",
                "fieldtype": "Data",
                "reqd": 1,
                "unique": 1,
            },
        ],
        "permissions": system_manager_permissions(),
    }


def api_server_script_payload(api_method: str, script: str) -> dict:
    return {
        "name": api_method,
        "script_type": "API",
        "api_method": api_method,
        "allow_guest": 0,
        "disabled": 0,
        "script": script,
    }


class SetupClient:
    def __init__(self, base_url: str, api_key: str, api_secret: str, session=None):
        self.base_url = base_url.rstrip("/")
        self.session = session or requests.Session()
        self.headers = {
            "Authorization": f"token {api_key}:{api_secret}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        }

    def _url(self, doctype: str, name: str | None = None) -> str:
        url = f"{self.base_url}/api/resource/{quote(doctype, safe='')}"
        if name:
            url += f"/{quote(name, safe='')}"
        return url

    def exists(self, doctype: str, name: str) -> bool:
        response = self.session.get(self._url(doctype, name), headers=self.headers, timeout=30)
        if response.status_code == 404:
            return False
        self._raise(response)
        return True

    def create(self, doctype: str, payload: dict) -> dict:
        response = self.session.post(
            self._url(doctype), headers=self.headers, json=payload, timeout=30
        )
        self._raise(response)
        return response.json().get("data", {})

    def update(self, doctype: str, name: str, values: dict) -> dict:
        response = self.session.put(
            self._url(doctype, name), headers=self.headers, json=values, timeout=30
        )
        self._raise(response)
        return response.json().get("data", {})

    @staticmethod
    def _raise(response) -> None:
        if response.status_code == 401:
            raise RuntimeError("401 Authentication failed.")
        if response.status_code == 403:
            raise RuntimeError("403 Permission denied.")
        try:
            response.raise_for_status()
        except requests.HTTPError as exc:
            raise RuntimeError(
                f"ERPNext returned HTTP {response.status_code}: {response.text}"
            ) from exc


def ensure_custom_field(client: SetupClient, payload: dict) -> None:
    name = f"Sales Order-{payload['fieldname']}"
    if client.exists("Custom Field", name):
        client.update("Custom Field", name, payload)
        print(f"[UPDATED] Sales Order.{payload['fieldname']}")
        return

    values = {"dt": "Sales Order", **payload}
    client.create("Custom Field", values)
    print(f"[CREATED] Sales Order.{payload['fieldname']}")


def ensure_doctype(client: SetupClient, name: str, payload: dict) -> None:
    if client.exists("DocType", name):
        print(f"[OK] {name} already exists")
        return
    client.create("DocType", payload)
    print(f"[CREATED] {name}")


def ensure_server_script(client: SetupClient, api_method: str, script: str) -> None:
    payload = api_server_script_payload(api_method, script)
    if client.exists("Server Script", api_method):
        values = {key: value for key, value in payload.items() if key != "name"}
        client.update("Server Script", api_method, values)
        print(f"[UPDATED] Server Script {api_method}")
        return
    client.create("Server Script", payload)
    print(f"[CREATED] Server Script {api_method}")


def load_script(name: str) -> str:
    return Path(__file__).resolve().with_name(name).read_text(encoding="utf-8-sig")


def load_config(path: str) -> dict:
    with open(path, "r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="Set up BCN cashier billing on ERPNext.")
    parser.add_argument("config_path", nargs="?", default="config.json")
    parser.add_argument(
        "--printer",
        required=True,
        help="Exact Windows printer name used by the cashier worker.",
    )
    parser.add_argument("--module", default="Selling")
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    config = load_config(args.config_path)
    required = ["FRAPPE_BASE_URL", "API_KEY", "API_SECRET"]
    missing = [key for key in required if not str(config.get(key) or "").strip()]
    if missing:
        print("Missing config values: " + ", ".join(missing))
        return 2

    client = SetupClient(
        config["FRAPPE_BASE_URL"], config["API_KEY"], config["API_SECRET"]
    )

    for field in sales_order_fields():
        ensure_custom_field(client, field)

    ensure_doctype(
        client,
        "Cashier Print Settings",
        cashier_print_settings_payload(args.module),
    )
    ensure_doctype(
        client,
        "Cashier Print Queue",
        cashier_print_queue_payload(args.module),
    )

    client.update(
        "Cashier Print Settings",
        "Cashier Print Settings",
        {"printer_name": args.printer, "enabled": 1},
    )
    print(f"[UPDATED] Cashier Print Settings -> {args.printer}")

    ensure_server_script(
        client, REQUEST_BILL_API, load_script("bcn_request_for_bill.py")
    )
    ensure_server_script(
        client, CASHIER_BILLING_API, load_script("bcn_cashier_billing.py")
    )

    print("Cashier billing setup complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
