import 'dart:async';

import 'package:flutter/material.dart';

class OperationalRefreshIndicator extends StatefulWidget {
  const OperationalRefreshIndicator({
    super.key,
    required this.onRefresh,
    this.interval = const Duration(seconds: 5),
  });

  final FutureOr<void> Function() onRefresh;
  final Duration interval;

  @override
  State<OperationalRefreshIndicator> createState() => _OperationalRefreshIndicatorState();
}

class _OperationalRefreshIndicatorState extends State<OperationalRefreshIndicator> {
  Timer? _timer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant OperationalRefreshIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await Future<void>.sync(widget.onRefresh);
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
