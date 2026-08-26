from bcn_restaurant.setup import create_sales_order_custom_fields, initialize_restaurant_settings


def execute():
    create_sales_order_custom_fields()
    initialize_restaurant_settings()
