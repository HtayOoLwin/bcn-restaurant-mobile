from pathlib import Path


def test_phase2_required_sales_order_item_fields_are_install_guarded():
    source = (Path(__file__).resolve().parents[1] / 'bcn_restaurant' / 'setup.py').read_text()
    for fieldname in (
        'custom_kitchen_counter',
        'custom_preparation_status',
        'custom_prepared_qty',
        'custom_kitchen_note',
        'custom_ready_at',
        'custom_served_at',
    ):
        assert f'"{fieldname}"' in source
