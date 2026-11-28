import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/session_storage.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({required SessionStorage sessionStorage, Dio? dio})
    // Keep the public named argument `sessionStorage` while the field stays private.
    // ignore: prefer_initializing_formals
    : _sessionStorage = sessionStorage,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.baseUrl,
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 20),
              headers: const {'Accept': 'application/json'},
            ),
          ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final sid = await _sessionStorage.readSid();
          if (sid != null && sid.isNotEmpty) {
            options.headers['Cookie'] = 'sid=$sid';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final SessionStorage _sessionStorage;

  Future<void> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/api/method/login',
        data: {'usr': username, 'pwd': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final cookies = response.headers['set-cookie'] ?? const <String>[];
      final sid = _extractSid(cookies);
      if (sid == null || sid.isEmpty || sid == 'Guest') {
        throw const ApiException(
          'Login succeeded but no valid session was returned.',
        );
      }
      await _sessionStorage.writeSid(sid);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> logout() async {
    try {
      await _dio.get<dynamic>('/api/method/logout');
    } on DioException {
      // Clear the local session even when the server cannot be reached.
    } finally {
      await _sessionStorage.clearSid();
    }
  }

  Future<bool> hasSession() async {
    final sid = await _sessionStorage.readSid();
    return sid != null && sid.isNotEmpty && sid != 'Guest';
  }

  String? _cacheKey(String method, Map<String, dynamic>? query) {
    if (method == 'bcn_mobile_bootstrap' || method == 'bcn_mobile_menu' || method == 'bcn_waiter_order_progress') return 'cache:$method';
    if (method == 'bcn_cashier_billing' && (query?['action']?.toString().isEmpty ?? true)) return 'cache:$method';
    if (method == 'bcn_mobile_tables') return 'cache:$method:${query?['customer_group'] ?? ''}';
    return null;
  }

  Future<void> saveOfflineOrder(String id, Map<String, dynamic> order) =>
      _sessionStorage.writeOffline('order:$id', jsonEncode(order));

  Future<Map<String, String>> pendingOrders() => _sessionStorage.pendingOrders();

  Future<bool> canReachServer() async {
    try {
      final user = await getMethod('frappe.auth.get_logged_user').timeout(const Duration(seconds: 4));
      if (user is! String || user.isEmpty || user == 'Guest') {
        throw const ApiException('Please sign in again.', statusCode: 401);
      }
      return true;
    } on TimeoutException {
      return false;
    } on ApiException catch (error) {
      if (error.statusCode == null) return false;
      rethrow;
    }
  }

  Future<dynamic> getMethod(
    String method, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final key = _cacheKey(method, queryParameters);
    try {
      final response = await _dio.get<dynamic>(
        '/api/method/$method',
        queryParameters: queryParameters,
        options: key == null ? null : Options(receiveTimeout: const Duration(seconds: 5)),
        cancelToken: null,
      ).timeout(key == null ? const Duration(seconds: 35) : const Duration(seconds: 6));
      final result = _unwrapMessage(response.data);
      if (key != null && result is Map) {
        try {
          await _sessionStorage.writeOffline(key, jsonEncode({
            'saved_at': DateTime.now().toUtc().toIso8601String(),
            'data': result,
          }));
        } catch (_) {
          // A storage failure must not break a successful online read.
        }
      }
      return result;
    } on TimeoutException {
      if (key != null) {
        final cached = await _readCache(key);
        if (cached != null) return cached;
      }
      throw const ApiException('Server unreachable. No usable offline cache.');
    } on DioException catch (error) {
      if (key != null && error.response == null &&
          (error.type == DioExceptionType.connectionError ||
           error.type == DioExceptionType.connectionTimeout ||
           error.type == DioExceptionType.receiveTimeout ||
           error.type == DioExceptionType.sendTimeout)) {
        final cached = await _readCache(key);
        if (cached != null) return cached;
      }
      throw ApiException.fromDio(error);
    }
  }

  Future<dynamic> _readCache(String key) async {
    final raw = await _sessionStorage.readOffline(key);
    if (raw == null) return null;
    final value = jsonDecode(raw) as Map;
    final saved = DateTime.tryParse(value['saved_at']?.toString() ?? '');
    if (saved == null || DateTime.now().toUtc().difference(saved) > const Duration(hours: 24)) return null;
    final data = value['data'];
    if (data is Map) return {...data, '_offline_cached': true};
    return data;
  }

  Future<dynamic> postMethod(
    String method, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/api/method/$method',
        data: data,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      return _unwrapMessage(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  static dynamic _unwrapMessage(dynamic data) {
    if (data is Map && data.containsKey('message')) {
      return data['message'];
    }
    return data;
  }

  static String? _extractSid(List<String> setCookieHeaders) {
    final regex = RegExp(r'(?:^|[;,]\s*)sid=([^;]+)');
    for (final header in setCookieHeaders) {
      final match = regex.firstMatch(header);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }
}
