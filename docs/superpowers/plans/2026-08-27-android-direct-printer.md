# Android Direct Printer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Wi-Fi-only Kitchen/Cashier printing with a reusable Android Bluetooth/Wi-Fi ESC/POS module, local Printer Setup with Test Print, and manual printing that never blocks payment.

**Architecture:** A transport-neutral adapter sends one ESC/POS payload through TCP or `print_bluetooth_thermal`. `PrinterSettingsRepository` persists one device-local configuration using `SharedPreferencesAsync`. Kitchen and Cashier build feature-specific tickets but share configuration, transport selection, Test Print, paper settings, and footer behavior.

**Tech Stack:** Flutter, Riverpod, go_router, Dart sockets, `print_bluetooth_thermal: ^1.2.2`, `esc_pos_utils_plus: ^2.0.4`, `shared_preferences: ^2.5.5`, pytest, Flutter tests.

**Spec:** `docs/superpowers/specs/2026-08-27-android-direct-printer-design.md`

## Global Constraints

- Android tablets only; no USB, Windows, automatic printing, or item-group routing.
- Bluetooth Classic ESC/POS and Wi-Fi/LAN ESC/POS; default TCP port 9100.
- One local printer configuration per tablet; 58 mm and 80 mm paper.
- Kitchen, Cancel Order, Cashier Bill, and Test Print are manual actions.
- Skipped or failed printing never blocks payment.
- Server print history changes only after the adapter completes the full data write.
- Cashier Bill never prints `PAYMENT PENDING`; it ends with local `Footer Remark`.

## File Map

Create `mobile/bcn_restaurant_mobile/lib/features/printing/` with:

- `domain/printer_config.dart`, `printer_device.dart`, `print_result.dart`.
- `data/printer_adapter.dart`, `network_printer_adapter.dart`, `bluetooth_printer_adapter.dart`, `printer_dispatcher.dart`, `printer_settings_repository.dart`.
- `services/escpos_ticket_builder.dart`, `cancel_ticket_builder.dart`.
- `presentation/printer_settings_controller.dart`, `printer_settings_screen.dart`.

Modify the existing Kitchen/Cashier printer services, screens, router, dependencies, Android manifest, server print tracking, and tests described below.

---

### Task 1: Configuration and Local Persistence

**Files:**
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/domain/printer_config.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/domain/printer_device.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/domain/print_result.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/data/printer_settings_repository.dart`
- Test: `mobile/bcn_restaurant_mobile/test/printer_config_test.dart`
- Test: `mobile/bcn_restaurant_mobile/test/printer_settings_repository_test.dart`
- Modify: `mobile/bcn_restaurant_mobile/pubspec.yaml`

**Interfaces:**
- Produces `PrinterConnectionType.bluetooth/network` and immutable `PrinterConfig` with JSON, `copyWith`, and `isConfigured`.
- Produces `PrinterSettingsRepository.load/save/clear` using injectable storage.

- [ ] **Step 1: Write failing model tests**

```dart
test('network config requires host and port', () {
  const value = PrinterConfig(
    connectionType: PrinterConnectionType.network,
    printerName: 'Kitchen',
    networkHost: '192.168.1.50',
    networkPort: 9100,
  );
  expect(value.isConfigured, isTrue);
  expect(value.copyWith(networkHost: '').isConfigured, isFalse);
});

test('Bluetooth config requires MAC address', () {
  const value = PrinterConfig(
    connectionType: PrinterConnectionType.bluetooth,
    printerName: 'XP-80',
    bluetoothMacAddress: 'AA:BB:CC:DD:EE:FF',
  );
  expect(value.isConfigured, isTrue);
});
```

- [ ] **Step 2: Verify the tests fail**

Run: `flutter test test/printer_config_test.dart`
Expected: FAIL because the types are missing.

- [ ] **Step 3: Implement model defaults and persistence**

```dart
const PrinterConfig.defaults()
    : connectionType = PrinterConnectionType.bluetooth,
      printerName = '',
      bluetoothMacAddress = '',
      networkHost = '',
      networkPort = 9100,
      paperWidthMm = 58,
      fontSizePx = 20,
      footerRemark = '',
      autoCut = true,
      enabled = true;
```

Persist one JSON string at `bcn.android_printer.config.v1` with `SharedPreferencesAsync`.

- [ ] **Step 4: Run model and repository tests**

Run: `flutter test test/printer_config_test.dart test/printer_settings_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/bcn_restaurant_mobile/pubspec.yaml mobile/bcn_restaurant_mobile/pubspec.lock mobile/bcn_restaurant_mobile/lib/features/printing mobile/bcn_restaurant_mobile/test/printer_config_test.dart mobile/bcn_restaurant_mobile/test/printer_settings_repository_test.dart
git commit -m "feat: add local Android printer configuration"
```

### Task 2: Bluetooth and Network Adapters

**Files:**
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/data/printer_adapter.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/data/network_printer_adapter.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/data/bluetooth_printer_adapter.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/data/printer_dispatcher.dart`
- Modify: `mobile/bcn_restaurant_mobile/android/app/src/main/AndroidManifest.xml`
- Test: `mobile/bcn_restaurant_mobile/test/printer_dispatcher_test.dart`

**Interfaces:**
- Produces `discover()`, `testConnection(config)`, and `write(config, bytes)`.
- `PrinterDispatcher.write` selects the adapter by `connectionType`.

- [ ] **Step 1: Write failing dispatcher test**

```dart
test('dispatcher selects Bluetooth adapter only', () async {
  final bluetooth = FakePrinterAdapter.success();
  final network = FakePrinterAdapter.failure();
  final dispatcher = PrinterDispatcher(bluetooth: bluetooth, network: network);
  final result = await dispatcher.write(bluetoothConfig, [0x1b, 0x40]);
  expect(result.succeeded, isTrue);
  expect(bluetooth.writeCount, 1);
  expect(network.writeCount, 0);
});
```

- [ ] **Step 2: Verify the test fails**

Run: `flutter test test/printer_dispatcher_test.dart`
Expected: FAIL because adapters are missing.

- [ ] **Step 3: Implement TCP write**

Use `Socket.connect(host, port, timeout: const Duration(seconds: 5))`, `add`, `flush`, and `close`; always `destroy` in `finally`. Return `PrintResult.failure` with host/port and socket error.

- [ ] **Step 4: Implement Bluetooth discovery and write**

Use `PrintBluetoothThermal.isPermissionBluetoothGranted`, `bluetoothEnabled`, `pairedBluetooths`, `connect(macPrinterAddress: ...)`, `writeBytes`, and `disconnect`. A false connect/write is failure; complete successful `writeBytes` is Success.

- [ ] **Step 5: Add Android Bluetooth permissions**

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
```

- [ ] **Step 6: Run tests and analysis**

Run: `flutter test test/printer_dispatcher_test.dart && flutter analyze`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add mobile/bcn_restaurant_mobile/lib/features/printing/data mobile/bcn_restaurant_mobile/android/app/src/main/AndroidManifest.xml mobile/bcn_restaurant_mobile/test/printer_dispatcher_test.dart
git commit -m "feat: add Bluetooth and Wi-Fi printer adapters"
```

### Task 3: ESC/POS and Test Print

**Files:**
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/services/escpos_ticket_builder.dart`
- Test: `mobile/bcn_restaurant_mobile/test/escpos_ticket_builder_test.dart`

**Interfaces:**
- Produces `buildTestPrint(PrinterConfig config, DateTime now)` and shared width/cut helpers.

- [ ] **Step 1: Write failing Test Print test**

```dart
test('test ticket contains identity and footer', () async {
  final bytes = await const EscPosTicketBuilder().buildTestPrint(
    networkConfig.copyWith(footerRemark: 'Thank you'),
    DateTime(2026, 8, 27, 14, 30),
  );
  final text = latin1.decode(bytes, allowInvalid: true);
  expect(text, contains('BCN RESTAURANT'));
  expect(text, contains('PRINTER TEST'));
  expect(text, contains('Thank you'));
});
```

- [ ] **Step 2: Verify failure**

Run: `flutter test test/escpos_ticket_builder_test.dart`
Expected: FAIL because the builder is missing.

- [ ] **Step 3: Implement width-aware ESC/POS**

Use `CapabilityProfile.load()` and `Generator(PaperSize.mm58/mm80, profile)`. Honor `autoCut`, configured font size, and Footer Remark.

- [ ] **Step 4: Implement Myanmar raster fallback**

Use Flutter `ParagraphBuilder` to render non-Latin lines, convert to a monochrome image, and add with `generator.imageRaster`. Test `containsNonLatin('ကျေးဇူးတင်ပါသည်') == true` and `containsNonLatin('Thank you') == false`.

- [ ] **Step 5: Run tests and commit**

Run: `flutter test test/escpos_ticket_builder_test.dart`
Expected: PASS.

```bash
git add mobile/bcn_restaurant_mobile/lib/features/printing/services mobile/bcn_restaurant_mobile/test/escpos_ticket_builder_test.dart
git commit -m "feat: build width-aware ESC POS test tickets"
```

### Task 4: Printer Settings UI

**Files:**
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/presentation/printer_settings_controller.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/presentation/printer_settings_screen.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/core/router/app_router.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/kitchen/presentation/kitchen_orders_screen.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart`
- Test: `mobile/bcn_restaurant_mobile/test/printer_settings_screen_test.dart`

**Interfaces:**
- Produces `/printer-settings` and controller actions load/discover/select/test/save/clear.

- [ ] **Step 1: Write failing widget test**

```dart
testWidgets('shows Bluetooth and Wi-Fi but not USB', (tester) async {
  await tester.pumpWidget(buildPrinterSettingsTestApp());
  await tester.pumpAndSettle();
  expect(find.text('Bluetooth'), findsOneWidget);
  expect(find.text('Wi-Fi'), findsOneWidget);
  expect(find.text('USB'), findsNothing);
  expect(find.text('Test Print'), findsOneWidget);
  expect(find.text('Save Printer Setup'), findsOneWidget);
});
```

- [ ] **Step 2: Verify failure**

Run: `flutter test test/printer_settings_screen_test.dart`
Expected: FAIL because the screen is missing.

- [ ] **Step 3: Build the approved responsive screen**

Use current Material 3 theme: AppBar, Bluetooth/Wi-Fi SegmentedButton, conditional paired-device or IP/port card, 58/80 controls, font slider/sample, Footer Remark, outlined Test Print, and filled Save action. Save is allowed without Test Print.

- [ ] **Step 4: Add settings route and AppBar buttons**

Authenticated Kitchen and Cashier users can open `/printer-settings`; preserve current role redirects.

- [ ] **Step 5: Run tests, analyze, and commit**

Run: `flutter test test/printer_settings_screen_test.dart && flutter analyze`
Expected: PASS.

```bash
git add mobile/bcn_restaurant_mobile/lib/features/printing/presentation mobile/bcn_restaurant_mobile/lib/core/router/app_router.dart mobile/bcn_restaurant_mobile/lib/features/kitchen/presentation/kitchen_orders_screen.dart mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart mobile/bcn_restaurant_mobile/test/printer_settings_screen_test.dart
git commit -m "feat: add Android printer setup and test print UI"
```

### Task 5: Kitchen and Cashier Integration

**Files:**
- Modify: `mobile/bcn_restaurant_mobile/lib/features/kitchen/data/kitchen_printer_service.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/kitchen/presentation/kitchen_orders_screen.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/data/cashier_printer_service.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart`
- Test: `mobile/bcn_restaurant_mobile/test/kitchen_ticket_builder_test.dart`
- Test: `mobile/bcn_restaurant_mobile/test/cashier_ticket_builder_test.dart`
- Test: `mobile/bcn_restaurant_mobile/test/cashier_optional_print_test.dart`

**Interfaces:**
- Consumes local config and dispatcher; preserves server record calls only after Success.

- [ ] **Step 1: Write failing ticket and optional-payment tests**

Assert Cashier bytes exclude `PAYMENT PENDING` and fixed `Please present this bill for payment`, include `footerRemark`, and Payment remains available when `billPrinted == false`. Assert Kitchen bytes contain `KITCHEN ORDER`, item quantity/note, no price/tax, and `KITCHEN ORDER - ADD` for a delta.

- [ ] **Step 2: Verify failures**

Run: `flutter test test/kitchen_ticket_builder_test.dart test/cashier_ticket_builder_test.dart test/cashier_optional_print_test.dart`
Expected: FAIL against current IP-only services and fixed footer.

- [ ] **Step 3: Refactor services**

Remove direct sockets from feature services. Each builds bytes, loads local settings, dispatches, and returns `PrintResult`. UI records server history only on Success.

- [ ] **Step 4: Keep payment independent**

Always show Payment for a draft invoice. Do not gate `_openPaymentSheet` on `billPrinted`. Retain the bill-changed warning only after an earlier successful print.

- [ ] **Step 5: Test and commit**

Run: `flutter test && flutter analyze`
Expected: PASS.

```bash
git add mobile/bcn_restaurant_mobile/lib/features/kitchen mobile/bcn_restaurant_mobile/lib/features/cashier mobile/bcn_restaurant_mobile/test
git commit -m "feat: use saved Android printer for Kitchen and Cashier"
```

### Task 6: Quantity Tracking and Cancel Order Ticket

**Files:**
- Modify: `bcn_restaurant/api/kitchen.py`
- Modify: `bcn_restaurant/api/waiter.py`
- Modify: `bcn_restaurant/setup.py`
- Create: `bcn_restaurant/patches/v1_0/add_print_tracking_fields.py`
- Modify: `bcn_restaurant/patches.txt`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/kitchen/domain/kitchen_models.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/kitchen/data/kitchen_repository.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/kitchen/presentation/kitchen_orders_screen.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/services/cancel_ticket_builder.dart`
- Test: `tests/test_kitchen_print_tracking.py`
- Test: `mobile/bcn_restaurant_mobile/test/cancel_ticket_builder_test.dart`

**Interfaces:**
- Produces Sales Order Item fields `custom_printed_qty`, `custom_cancel_ticket_qty`, `custom_last_print_job_id`.
- Produces `printable_qty = max(qty - custom_printed_qty, 0)` and idempotent job acknowledgement.

- [ ] **Step 1: Write failing server tests**

```python
def test_printable_qty_is_unprinted_delta():
    assert printable_qty(ordered_qty=3, printed_qty=2) == 1

def test_duplicate_ack_does_not_increment_twice():
    row = FakeRow(printed_qty=1, last_job_id="JOB-1")
    acknowledge_print(row, job_id="JOB-1", qty=1)
    assert row.printed_qty == 1
```

- [ ] **Step 2: Verify failure**

Run: `pytest -q tests/test_kitchen_print_tracking.py`
Expected: FAIL because helpers and fields are missing.

- [ ] **Step 3: Add fields, delta response, and idempotent acknowledgement**

Reject negative/over-quantity acknowledgements. Update printed quantity only after mobile Success. Return only unprinted delta to the ticket builder.

- [ ] **Step 4: Add Cancel Order flow**

Cancellation commits independently of printing. Return cancelled delta/reason, and build a high-contrast `CANCEL ORDER` ticket with original printed, cancelled, remaining, user, and job ID. Failed printing remains retryable.

- [ ] **Step 5: Test and commit**

Run: `pytest -q tests/test_kitchen_print_tracking.py tests/test_phase2_contract.py && cd mobile/bcn_restaurant_mobile && flutter test test/cancel_ticket_builder_test.dart`
Expected: PASS.

```bash
git add bcn_restaurant tests mobile/bcn_restaurant_mobile/lib/features/kitchen mobile/bcn_restaurant_mobile/lib/features/printing/services/cancel_ticket_builder.dart mobile/bcn_restaurant_mobile/test/cancel_ticket_builder_test.dart
git commit -m "feat: track Kitchen print quantities and cancellation tickets"
```

### Task 7: Full Verification

**Files:**
- Modify only files required by verification findings.

**Interfaces:**
- Verifies Tasks 1-6 together.

- [ ] **Step 1: Run all server tests**

Run: `pytest -q`
Expected: PASS.

- [ ] **Step 2: Run Flutter tests and analyzer**

Run: `cd mobile/bcn_restaurant_mobile && flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 3: Build Android debug APK**

Run: `flutter build apk --debug`
Expected: exit code 0 and `build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 4: Real-device smoke checks**

Verify Android 12+ Bluetooth permission, paired-device selection, Test Print, Kitchen Print, Cancel Order ticket, Cashier Footer Remark, Wi-Fi IP/port, retry after disconnect, Payment without Print, and 58/80 mm layouts.

- [ ] **Step 5: Commit verification fixes if any**

```bash
git add -A
git commit -m "test: verify Android direct printer workflow"
```
