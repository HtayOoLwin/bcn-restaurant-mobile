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
    }

    message ??= error.message;
    message ??= 'Unable to connect to the server.';
    return ApiException(message, statusCode: response?.statusCode);
  }

  @override
  String toString() => message;
}
