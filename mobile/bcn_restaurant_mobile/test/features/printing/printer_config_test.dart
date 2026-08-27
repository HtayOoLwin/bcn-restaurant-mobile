import 'package:bcn_restaurant_mobile/features/printing/domain/printer_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrinterConfig', () {
    test('Bluetooth requires a selected MAC address', () {
      expect(const PrinterConfig.defaults().isConfigured, isFalse);
      expect(
        const PrinterConfig.defaults()
            .copyWith(bluetoothMacAddress: 'AA:BB:CC:DD:EE:FF')
            .isConfigured,
        isTrue,
      );
    });

    test('Wi-Fi requires a valid host and port', () {
      final config = const PrinterConfig.defaults().copyWith(
        connectionType: PrinterConnectionType.wifi,
        wifiIpAddress: '192.168.1.50',
        wifiPort: 9100,
      );

      expect(config.isConfigured, isTrue);
      expect(config.copyWith(wifiPort: 70000).isConfigured, isFalse);
    });

    test('round-trips saved settings', () {
      final original = const PrinterConfig.defaults().copyWith(
        connectionType: PrinterConnectionType.wifi,
        printerName: 'Kitchen',
        wifiIpAddress: '192.168.1.20',
        paperWidthMm: 80,
        footerRemark: 'ကျေးဇူးတင်ပါသည်',
        autoCut: false,
      );

      final restored = PrinterConfig.fromJson(original.toJson());

      expect(restored.connectionType, PrinterConnectionType.wifi);
      expect(restored.displayName, 'Kitchen');
      expect(restored.paperWidthMm, 80);
      expect(restored.footerRemark, 'ကျေးဇူးတင်ပါသည်');
      expect(restored.autoCut, isFalse);
    });
  });
}
