from __future__ import annotations

import importlib
import sys
import types
import unittest


class _Document(types.SimpleNamespace):
    pass


class _Order(_Document):
    def __init__(self):
        super().__init__(name="SO-0001")
        self.cancelled = False
        self.reloaded = False

    def reload(self):
        self.reloaded = True

    def cancel(self):
        self.cancelled = True


class _FakeDatabase:
    def __init__(self, frappe_module):
        self._frappe = frappe_module
        self.values_written = []

    def set_value(self, doctype, name, values, update_modified=True):
        self.values_written.append((doctype, name, values, update_modified))
        if doctype == "Sales Order Item" and name == self._frappe.row.name:
            for fieldname, value in values.items():
                setattr(self._frappe.row, fieldname, value)

    def get_value(self, doctype, filters, fieldname):
        return None


class _FakeFrappe(types.ModuleType):
    class PermissionError(Exception):
        pass

    class ValidationError(Exception):
        pass

    def __init__(self):
        super().__init__("frappe")
        self.session = types.SimpleNamespace(user="waiter@example.com")
        self.roles = ["Waiter"]
        self.row = _Document(
            name="SO-ITEM-1",
            parenttype="Sales Order",
            parent="SO-0001",
            qty=1,
            custom_preparation_status="New",
        )
        self.order = _Order()
        self.db = _FakeDatabase(self)
        self.deleted_docs = []
        self.get_doc_calls = []

    def whitelist(self, methods=None):
        def decorate(function):
            function.allowed_http_methods = tuple(methods or ())
            return function

        return decorate

    def throw(self, message, exception=None):
        raise (exception or self.ValidationError)(message)

    def get_roles(self, user):
        return list(self.roles)

    def get_doc(self, doctype, name):
        self.get_doc_calls.append((doctype, name))
        if (doctype, name) == ("Sales Order Item", self.row.name):
            return self.row
        if (doctype, name) == ("Sales Order", self.order.name):
            return self.order
        raise AssertionError((doctype, name))

    def get_all(self, doctype, **kwargs):
        if doctype == "Sales Invoice Item":
            return []
        raise AssertionError((doctype, kwargs))

    def delete_doc(self, doctype, name, ignore_permissions=False):
        self.deleted_docs.append((doctype, name, ignore_permissions))


class WaiterItemActionPermissionTest(unittest.TestCase):
    def setUp(self):
        self.frappe = _FakeFrappe()
        frappe_utils = types.ModuleType("frappe.utils")
        frappe_utils.now_datetime = lambda: "2026-09-04 12:00:00"
        self.frappe.utils = frappe_utils

        preparation_service = types.ModuleType("bcn_restaurant.services.preparation")
        preparation_service.assert_active_restaurant_order = lambda order, waiter: None
        preparation_service.get_active_session_order_names = lambda waiter: []
        preparation_service.recalculate_sales_order = lambda order_name: {
            "summary": "New",
            "active_total": 0,
        }

        sys.modules.update(
            {
                "frappe": self.frappe,
                "frappe.utils": frappe_utils,
                "bcn_restaurant.services.preparation": preparation_service,
            }
        )
        sys.modules.pop("bcn_restaurant.api.common", None)
        sys.modules.pop("bcn_restaurant.api.waiter", None)
        self.waiter = importlib.import_module("bcn_restaurant.api.waiter")

    def test_waiter_cancel_action_is_denied_before_item_or_order_mutation(self):
        with self.assertRaises(self.frappe.PermissionError):
            self.waiter.item_action("SO-ITEM-1", "Cancel")

        self.assertEqual(self.frappe.row.custom_preparation_status, "New")
        self.assertEqual(self.frappe.get_doc_calls, [])
        self.assertEqual(self.frappe.db.values_written, [])
        self.assertFalse(self.frappe.order.cancelled)

    def _assert_manager_can_cancel(self, role):
        self.frappe.roles = [role]
        self.frappe.session.user = f"{role.lower().replace(' ', '.')}@example.com"

        result = self.waiter.item_action("SO-ITEM-1", "Cancel")

        self.assertEqual(result["order_cancelled"], True)
        self.assertEqual(self.frappe.row.custom_preparation_status, "Cancelled")
        self.assertTrue(self.frappe.order.cancelled)

    def test_restaurant_manager_may_cancel_final_active_item(self):
        self._assert_manager_can_cancel("Restaurant Manager")

    def test_system_manager_may_cancel_final_active_item(self):
        self._assert_manager_can_cancel("System Manager")

    def test_waiter_can_still_mark_a_ready_item_served(self):
        self.frappe.row.custom_preparation_status = "Ready"

        result = self.waiter.item_action("SO-ITEM-1", "Mark Served")

        self.assertEqual(result["status"], "Served")
        self.assertEqual(self.frappe.row.custom_preparation_status, "Served")
        self.assertFalse(self.frappe.order.cancelled)


if __name__ == "__main__":
    unittest.main()
