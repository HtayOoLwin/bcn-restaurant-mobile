enum PrinterConnectionType { bluetooth, wifi }

class PrinterConfig {
  const PrinterConfig({
    required this.connectionType,
    required this.printerName,
    required this.bluetoothMacAddress,
    required this.wifiIpAddress,
    required this.wifiPort,
    required this.paperWidthMm,
    required this.fontSizePx,
    required this.footerRemark,
    required this.autoCut,
    required this.enabled,
  });

  const PrinterConfig.defaults()
    : connectionType = PrinterConnectionType.bluetooth,
      printerName = '',
      bluetoothMacAddress = '',
      wifiIpAddress = '',
      wifiPort = 9100,
      paperWidthMm = 58,
      fontSizePx = 20,
      footerRemark = '',
      autoCut = true,
      enabled = true;

  factory PrinterConfig.fromJson(Map<String, dynamic> json) {
    return PrinterConfig(
      connectionType: json['connection_type'] == 'wifi'
          ? PrinterConnectionType.wifi
          : PrinterConnectionType.bluetooth,
      printerName: json['printer_name']?.toString().trim() ?? '',
      bluetoothMacAddress:
          json['bluetooth_mac_address']?.toString().trim() ?? '',
      wifiIpAddress: json['wifi_ip_address']?.toString().trim() ?? '',
      wifiPort: (json['wifi_port'] as num?)?.toInt() ?? 9100,
      paperWidthMm: (json['paper_width_mm'] as num?)?.toInt() == 80 ? 80 : 58,
      fontSizePx: ((json['font_size_px'] as num?)?.toDouble() ?? 20)
          .clamp(15, 25)
          .toDouble(),
      footerRemark: json['footer_remark']?.toString().trim() ?? '',
      autoCut: json['auto_cut'] != false,
      enabled: json['enabled'] != false,
    );
  }

  final PrinterConnectionType connectionType;
  final String printerName;
  final String bluetoothMacAddress;
  final String wifiIpAddress;
  final int wifiPort;
  final int paperWidthMm;
  final double fontSizePx;
  final String footerRemark;
  final bool autoCut;
  final bool enabled;

  bool get isConfigured {
    if (!enabled) return false;
    return switch (connectionType) {
      PrinterConnectionType.bluetooth => bluetoothMacAddress.isNotEmpty,
      PrinterConnectionType.wifi =>
        wifiIpAddress.isNotEmpty && wifiPort > 0 && wifiPort <= 65535,
    };
  }

  String get displayName {
    if (printerName.isNotEmpty) return printerName;
    return connectionType == PrinterConnectionType.bluetooth
        ? bluetoothMacAddress
        : '$wifiIpAddress:$wifiPort';
  }

  Map<String, dynamic> toJson() => {
    'connection_type': connectionType.name,
    'printer_name': printerName,
    'bluetooth_mac_address': bluetoothMacAddress,
    'wifi_ip_address': wifiIpAddress,
    'wifi_port': wifiPort,
    'paper_width_mm': paperWidthMm,
    'font_size_px': fontSizePx,
    'footer_remark': footerRemark,
    'auto_cut': autoCut,
    'enabled': enabled,
  };

  PrinterConfig copyWith({
    PrinterConnectionType? connectionType,
    String? printerName,
    String? bluetoothMacAddress,
    String? wifiIpAddress,
    int? wifiPort,
    int? paperWidthMm,
    double? fontSizePx,
    String? footerRemark,
    bool? autoCut,
    bool? enabled,
  }) {
    return PrinterConfig(
      connectionType: connectionType ?? this.connectionType,
      printerName: printerName ?? this.printerName,
      bluetoothMacAddress: bluetoothMacAddress ?? this.bluetoothMacAddress,
      wifiIpAddress: wifiIpAddress ?? this.wifiIpAddress,
      wifiPort: wifiPort ?? this.wifiPort,
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      fontSizePx: fontSizePx ?? this.fontSizePx,
      footerRemark: footerRemark ?? this.footerRemark,
      autoCut: autoCut ?? this.autoCut,
      enabled: enabled ?? this.enabled,
    );
  }
}

class PrinterDevice {
  const PrinterDevice({required this.name, required this.address});

  final String name;
  final String address;
}

class PrintResult {
  const PrintResult._(this.succeeded, this.message);

  const PrintResult.success(String message) : this._(true, message);
  const PrintResult.failure(String message) : this._(false, message);

  final bool succeeded;
  final String message;
}
