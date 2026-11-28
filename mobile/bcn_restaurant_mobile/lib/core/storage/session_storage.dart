import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStorage {
  SessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _sidKey = 'frappe_sid';
  final FlutterSecureStorage _storage;

  Future<String?> readSid() => _storage.read(key: _sidKey);

  Future<void> writeSid(String sid) => _storage.write(key: _sidKey, value: sid);

  Future<void> clearSid() async {
    final sid = await readSid();
    if (sid != null) {
      final prefix = _prefix(sid);
      final values = await _storage.readAll();
      for (final key in values.keys.where((key) => key.startsWith(prefix) && !key.contains(':order:'))) {
        await _storage.delete(key: key);
      }
    }
    await _storage.delete(key: _sidKey);
  }

  String _prefix(String sid) => 'offline:v1:${base64Url.encode(utf8.encode(sid))}:';

  Future<String?> readOffline(String key) async {
    final sid = await readSid();
    if (sid == null || sid.isEmpty || sid == 'Guest') return null;
    return _storage.read(key: '${_prefix(sid)}$key');
  }

  Future<void> writeOffline(String key, String value) async {
    final sid = await readSid();
    if (sid == null || sid.isEmpty || sid == 'Guest') {
      throw StateError('An authenticated session is required.');
    }
    await _storage.write(key: '${_prefix(sid)}$key', value: value);
  }

  Future<Map<String, String>> pendingOrders() async {
    final sid = await readSid();
    if (sid == null || sid.isEmpty || sid == 'Guest') return {};
    final prefix = '${_prefix(sid)}order:';
    final values = await _storage.readAll();
    return {
      for (final entry in values.entries)
        if (entry.key.startsWith(prefix)) entry.key.substring(prefix.length): entry.value,
    };
  }

  Future<void> deletePendingOrder(String id, {String? expectedSid}) async {
    final sid = await readSid();
    if (sid == null || (expectedSid != null && sid != expectedSid)) {
      throw StateError('Session missing or changed');
    }
    await _storage.delete(key: '${_prefix(sid)}order:$id');
  }
}
