import 'dart:convert';

import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    final data = response?.data;
    String? message;

    if (data is Map) {
      final serverMessages = data['_server_messages'];
      if (serverMessages is String && serverMessages.isNotEmpty) {
        try {
          final outer = jsonDecode(serverMessages);
          if (outer is List && outer.isNotEmpty) {
            final decoded = jsonDecode(outer.first.toString());
            if (decoded is Map && decoded['message'] != null) {
              message = decoded['message'].toString();
            }
          }
        } catch (_) {
          // Fall through to other Frappe error fields.
        }
      }
      message ??= data['message']?.toString();
      message ??= data['exception']?.toString();
      // Frappe may send only exc_type plus a JSON-encoded traceback.
      // Prefer the final exception line instead of a generic NameError.
      if (message == null || message == data['exc_type']?.toString()) {
        final raw = data['exc'];
        dynamic trace = raw;
        if (raw is String) {
          try {
            trace = jsonDecode(raw);
          } catch (_) {
            trace = raw;
          }
        }
        final traces = trace is List ? trace : [trace];
        for (final entry in traces.reversed) {
          if (entry is! String) continue;
          final lines = entry.trim().split('\n');
          if (lines.isNotEmpty && lines.last.trim().isNotEmpty) {
            message = lines.last.trim();
            break;
          }
        }
      }
      message ??= data['exc_type']?.toString();
      if (message == null && data['exc'] is String) {
        final lines = data['exc'].toString().split('\\n');
        for (final line in lines.reversed) {
          if (line.trim().isNotEmpty) {
            message = line.trim();
            break;
          }
        }
      }
    }

    message ??= error.message;
    message ??= 'Unable to connect to the server.';
    return ApiException(message, statusCode: response?.statusCode);
  }

  @override
  String toString() => message;
}
