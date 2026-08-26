import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStorage {
  SessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _sidKey = 'frappe_sid';
  final FlutterSecureStorage _storage;

  Future<String?> readSid() => _storage.read(key: _sidKey);

  Future<void> writeSid(String sid) => _storage.write(key: _sidKey, value: sid);

  Future<void> clearSid() => _storage.delete(key: _sidKey);
}
