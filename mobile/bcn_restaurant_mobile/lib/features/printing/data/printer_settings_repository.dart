import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/printer_config.dart';

class PrinterSettingsRepository {
  const PrinterSettingsRepository();

  static const _key = 'bcn.android_printer.config.v1';

  Future<PrinterConfig> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key)?.trim();
    if (raw == null || raw.isEmpty) return const PrinterConfig.defaults();
    try {
      return PrinterConfig.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const PrinterConfig.defaults();
    }
  }

  Future<void> save(PrinterConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(config.toJson()));
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
  }
}
