from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / "mobile" / "bcn_restaurant_mobile"
LIB = MOBILE / "lib"


def _read(relative: str) -> str:
    return (MOBILE / relative).read_text(encoding="utf-8")


def test_mobile_server_is_fixed_to_ourcity():
    config = _read("lib/core/config/app_config.dart")
    assert "static const baseUrl = 'https://ourcity.s.frappe.cloud';" in config
    assert "String.fromEnvironment" not in config
    assert "bcndemo-restaurant.nvi.frappe.cloud" not in config


def test_mobile_router_has_no_kitchen_monitor_or_waiter_status_destination():
    router = _read("lib/core/router/app_router.dart")
    assert "features/kitchen" not in router
    assert "KitchenOrdersScreen" not in router
    assert "permissions.kitchen" not in router
    assert "'/kitchen'" not in router
    assert "waiter_progress" not in router
    assert "'/waiter/ready'" not in router
    assert "'/waiter/progress'" not in router


def test_waiter_and_cashier_navigation_have_no_kitchen_monitor_controls():
    for relative in (
        "lib/features/waiter/presentation/waiter_tables_screen.dart",
        "lib/features/cashier/presentation/cashier_screen.dart",
    ):
        source = _read(relative)
        assert "features/kitchen" not in source, relative
        assert "kitchenNewOrderCountProvider" not in source, relative
        assert "'/kitchen'" not in source, relative
        assert "permissions.kitchen" not in source, relative

    waiter = _read("lib/features/waiter/presentation/waiter_tables_screen.dart")
    assert "Ready to Serve" not in waiter
    assert "Order Progress" not in waiter
    assert "mobileNotificationsProvider" not in waiter
    assert "'/waiter/ready'" not in waiter
    assert "'/waiter/progress'" not in waiter


def test_app_does_not_start_kitchen_status_notification_polling():
    source = _read("lib/app.dart")
    assert "MobileNotificationWatcher" not in source
    assert "features/notifications" not in source


def test_mobile_lib_has_no_kitchen_monitor_references():
    forbidden = (
        "features/kitchen",
        "KitchenOrdersScreen",
        "kitchenNewOrderCountProvider",
        "permissions.kitchen",
        "'/kitchen'",
    )
    offenders = []
    for path in LIB.rglob("*.dart"):
        source = path.read_text(encoding="utf-8")
        for token in forbidden:
            if token in source:
                offenders.append(f"{path.relative_to(MOBILE)}: {token}")
    assert offenders == []


def test_bootstrap_model_has_no_mobile_kitchen_permission():
    source = _read("lib/features/bootstrap/domain/bootstrap_model.dart")
    assert "required this.kitchen," not in source
    assert "json['kitchen']" not in source
    assert "final bool kitchen;" not in source


def test_android_direct_printing_dependencies_and_permissions_are_removed():
    pubspec = _read("pubspec.yaml")
    for dependency in (
        "print_bluetooth_thermal",
        "permission_handler",
        "esc_pos_utils_plus",
        "shared_preferences",
    ):
        assert dependency not in pubspec

    manifest = _read("android/app/src/main/AndroidManifest.xml")
    assert "android.permission.BLUETOOTH" not in manifest
    assert "android.permission.BLUETOOTH_ADMIN" not in manifest
    assert "android.permission.BLUETOOTH_CONNECT" not in manifest
    assert "android.permission.BLUETOOTH_SCAN" not in manifest


def test_old_mobile_kitchen_and_direct_print_files_are_deleted():
    removed_paths = (
        "lib/features/kitchen/data/kitchen_printer_service.dart",
        "lib/features/kitchen/data/kitchen_repository.dart",
        "lib/features/kitchen/domain/kitchen_models.dart",
        "lib/features/kitchen/presentation/kitchen_notification_badge.dart",
        "lib/features/kitchen/presentation/kitchen_orders_screen.dart",
        "lib/features/printing/data/direct_printer_service.dart",
        "lib/features/printing/data/printer_settings_repository.dart",
        "lib/features/printing/domain/printer_config.dart",
        "lib/features/printing/services/esc_pos_raster_builder.dart",
        "lib/features/cashier/data/cashier_printer_service.dart",
    )
    for relative in removed_paths:
        assert not (MOBILE / relative).exists(), relative
