import frappe
from frappe.model.document import Document


class RestaurantSettings(Document):
    def validate(self):
        links = {
            "Company": self.company,
            "POS Profile": self.pos_profile,
            "Price List": self.selling_price_list,
            "Currency": self.default_currency,
            "Customer Group": self.dine_in_customer_group,
        }
        for doctype, value in links.items():
            if value and not frappe.db.exists(doctype, value):
                frappe.throw(f"{doctype} {value} does not exist")

        if self.takeaway_customer_group and not frappe.db.exists(
            "Customer Group", self.takeaway_customer_group
        ):
            frappe.throw(f"Customer Group {self.takeaway_customer_group} does not exist")
