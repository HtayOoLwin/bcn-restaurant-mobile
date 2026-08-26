import frappe
from frappe.model.document import Document
from frappe.utils import now_datetime


class RestaurantTableSession(Document):
    def before_insert(self):
        if not self.waiter:
            self.waiter = frappe.session.user
        if not self.opened_at:
            self.opened_at = now_datetime()

    def validate(self):
        if (self.guest_count or 0) < 1:
            frappe.throw("Guest Count must be at least 1")

        if self.status in {"Paid", "Closed", "Cancelled"} and not self.closed_at:
            self.closed_at = now_datetime()
        elif self.status in {"Open", "Billing"}:
            self.closed_at = None
