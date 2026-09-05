enum PrintJobState { pending, sent, printing, success, failed, unknown }

class PrintJobStatusValue {
  const PrintJobStatusValue({required this.state, required this.rawValue});

  factory PrintJobStatusValue.parse(Object? value) {
    final rawValue = value?.toString().trim() ?? '';
    if (rawValue.isEmpty) {
      throw const FormatException('Print job status is missing.');
    }

    final state = switch (rawValue.toLowerCase()) {
      'pending' => PrintJobState.pending,
      'sent' => PrintJobState.sent,
      'printing' => PrintJobState.printing,
      'success' => PrintJobState.success,
      'failed' => PrintJobState.failed,
      _ => PrintJobState.unknown,
    };
    return PrintJobStatusValue(state: state, rawValue: rawValue);
  }

  final PrintJobState state;
  final String rawValue;
}

class PrintRequestResult {
  const PrintRequestResult({
    required this.jobId,
    required this.status,
    required this.isReprint,
  });

  factory PrintRequestResult.fromJson(Map<String, dynamic> json) {
    final jobId = json['job_id']?.toString().trim() ?? '';
    if (jobId.isEmpty) {
      throw const FormatException('Print request response has no job_id.');
    }
    return PrintRequestResult(
      jobId: jobId,
      status: PrintJobStatusValue.parse(json['status']),
      isReprint: _asBool(json['is_reprint'], field: 'is_reprint'),
    );
  }

  final String jobId;
  final PrintJobStatusValue status;
  final bool isReprint;
}

class WindowsPrintStatus {
  const WindowsPrintStatus({
    required this.online,
    required this.lastSeen,
    required this.pending,
    required this.failed,
  });

  factory WindowsPrintStatus.fromJson(Map<String, dynamic> json) {
    final lastSeenValue = json['last_seen']?.toString().trim();
    return WindowsPrintStatus(
      online: _asBool(json['online'], field: 'online'),
      lastSeen: lastSeenValue == null || lastSeenValue.isEmpty
          ? null
          : lastSeenValue,
      pending: _asCount(json['pending'], field: 'pending'),
      failed: _asCount(json['failed'], field: 'failed'),
    );
  }

  final bool online;
  final String? lastSeen;
  final int pending;
  final int failed;
}

bool _asBool(Object? value, {required String field}) {
  if (value == true || value == 1 || value == '1') return true;
  if (value == false || value == 0 || value == '0') return false;
  throw FormatException('Print response has an invalid $field value.');
}

int _asCount(Object? value, {required String field}) {
  final count = value is int ? value : int.tryParse(value?.toString() ?? '');
  if (count == null || count < 0) {
    throw FormatException('Print response has an invalid $field value.');
  }
  return count;
}
