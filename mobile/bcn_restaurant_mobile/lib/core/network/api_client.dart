import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/session_storage.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({required SessionStorage sessionStorage, Dio? dio})
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

  Future<dynamic> getMethod(
    String method, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '/api/method/$method',
        queryParameters: queryParameters,
      );
      return _unwrapMessage(response.data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
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
