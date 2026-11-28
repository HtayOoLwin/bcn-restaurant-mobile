import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStorage {
  SessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _sidKey = 'frappe_sid';
  final FlutterSecureStorage _storage;

  // Windows secure storage may use a shared backing file. Serialize reads,
  // writes and deletes across all SessionStorage instances in this isolate.
  static Future<void> _tail = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  Future<T> _retry<T>(Future<T> Function() action) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await action();
      } catch (error) {
        final message = error.toString().toLowerCase();
        final accessError = message.contains('pathaccessexception') ||
            message.contains('cannot delete file') ||
            message.contains('access is denied') ||
            message.contains('sharing violation');
        if (!accessError || attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 150 * (attempt + 1)));
      }
    }
  }

  Future<String?> _readSid() => _retry(() => _storage.read(key: _sidKey));

  Future<String?> readSid() => _serialized(_readSid);

  Future<void> writeSid(String sid) => _serialized(() =>
      _retry(() => _storage.write(key: _sidKey, value: sid)));

  Future<void> clearSid() => _serialized(() async {
    final sid = await _readSid();
    if (sid != null) {
      final prefix = _prefix(sid);
      final values = await _retry(() => _storage.readAll());
      for (final key in values.keys.where((key) => key.startsWith(prefix) && !key.contains(':order:'))) {
        await _retry(() => _storage.delete(key: key));
      }
    }
    await _retry(() => _storage.delete(key: _sidKey));
  });

  String _prefix(String sid) => 'offline:v1:${base64Url.encode(utf8.encode(sid))}:';

  Future<String?> readOffline(String key) => _serialized(() async {
    final sid = await _readSid();
    if (sid == null || sid.isEmpty || sid == 'Guest') return null;
    return _retry(() => _storage.read(key: '${_prefix(sid)}$key'));
  });

  Future<void> writeOffline(String key, String value) => _serialized(() async {
    final sid = await _readSid();
    if (sid == null || sid.isEmpty || sid == 'Guest') {
      throw StateError('An authenticated session is required.');
    }
    await _retry(() => _storage.write(key: '${_prefix(sid)}$key', value: value));
  });

  Future<Map<String, String>> pendingOrders() => _serialized(() async {
    final sid = await _readSid();
    if (sid == null || sid.isEmpty || sid == 'Guest') return {};
    final prefix = '${_prefix(sid)}order:';
    final values = await _retry(() => _storage.readAll());
    return {
      for (final entry in values.entries)
        if (entry.key.startsWith(prefix)) entry.key.substring(prefix.length): entry.value,
    };
  });

  Future<void> deletePendingOrder(String id, {String? expectedSid}) => _serialized(() async {
    final sid = await _readSid();
    if (sid == null || (expectedSid != null && sid != expectedSid)) {
      throw StateError('Session missing or changed');
    }
    final key = '${_prefix(sid)}order:$id';
    await _retry(() async {
      // A previous attempt may have deleted the key before reporting an error.
      if (await _storage.read(key: key) != null) {
        await _storage.delete(key: key);
      }
    });
  });
}
