app_name = "bcn_restaurant"
app_title = "BCN Restaurant"
app_publisher = "BCN"
app_description = "Mobile backend and restaurant workflow extensions for ERPNext v16"
app_email = "dev@bcn.local"
app_license = "MIT"

before_install = "bcn_restaurant.setup.before_install"
after_install = "bcn_restaurant.setup.after_install"

doc_events = {
    "Sales Order": {
        "before_validate": "bcn_restaurant.events.sales_order.route_kitchen_items",
    }
}
