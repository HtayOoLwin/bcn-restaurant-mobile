import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../domain/printer_config.dart';

class DirectPrinterService {
  const DirectPrinterService();

  Future<List<PrinterDevice>> pairedBluetoothPrinters() async {
    final permissionError = await _ensureBluetoothReady();
    if (permissionError != null) throw StateError(permissionError);
    final printers = await PrintBluetoothThermal.pairedBluetooths;
    return printers
        .map(
          (device) =>
              PrinterDevice(name: device.name, address: device.macAdress),
        )
        .where((device) => device.address.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<PrintResult> printBytes(PrinterConfig config, List<int> bytes) async {
    if (!config.isConfigured) {
      return const PrintResult.failure('Printer is not configured.');
    }
    if (bytes.isEmpty) {
      return const PrintResult.failure('There is no printable content.');
    }
    return switch (config.connectionType) {
      PrinterConnectionType.bluetooth => _printBluetooth(config, bytes),
      PrinterConnectionType.wifi => _printWifi(config, bytes),
    };
  }

  Future<PrintResult> _printWifi(PrinterConfig config, List<int> bytes) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        config.wifiIpAddress,
        config.wifiPort,
        timeout: const Duration(seconds: 8),
      );
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      return PrintResult.success('Print sent to ${config.displayName}.');
    } on SocketException catch (error) {
      return PrintResult.failure(
        'Cannot reach ${config.wifiIpAddress}:${config.wifiPort}. ${error.message}',
      );
    } catch (error) {
      return PrintResult.failure('Wi-Fi print failed: $error');
    } finally {
      socket?.destroy();
    }
  }

  Future<PrintResult> _printBluetooth(
    PrinterConfig config,
    List<int> bytes,
  ) async {
    final permissionError = await _ensureBluetoothReady();
    if (permissionError != null) return PrintResult.failure(permissionError);
    try {
      var connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        connected = await PrintBluetoothThermal.connect(
          macPrinterAddress: config.bluetoothMacAddress,
        );
      }
      if (!connected) {
        return PrintResult.failure(
          'Unable to connect to ${config.displayName}.',
        );
      }
      final written = await PrintBluetoothThermal.writeBytes(bytes);
      if (!written) {
        await PrintBluetoothThermal.disconnect;
        return const PrintResult.failure(
          'Printer did not accept the print data.',
        );
      }
      return PrintResult.success('Print sent to ${config.displayName}.');
    } catch (error) {
      try {
        await PrintBluetoothThermal.disconnect;
      } catch (_) {}
      return PrintResult.failure('Bluetooth print failed: $error');
    }
  }

  Future<String?> _ensureBluetoothReady() async {
    if (!Platform.isAndroid)
      return 'Bluetooth printing is supported on Android only.';
    final connectPermission = await Permission.bluetoothConnect.request();
    final scanPermission = await Permission.bluetoothScan.request();
    if (!connectPermission.isGranted || !scanPermission.isGranted) {
      return 'Bluetooth permission is required to select and use a printer.';
    }
    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    return enabled ? null : 'Bluetooth is off. Turn it on and try again.';
  }
}
