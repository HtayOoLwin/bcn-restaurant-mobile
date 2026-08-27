import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AdaptiveOrientation extends StatefulWidget {
  const AdaptiveOrientation({super.key, required this.child});

  final Widget child;

  @override
  State<AdaptiveOrientation> createState() => _AdaptiveOrientationState();
}

class _AdaptiveOrientationState extends State<AdaptiveOrientation> {
  bool? _lastWasTablet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    if (_lastWasTablet == isTablet) return;
    _lastWasTablet = isTablet;

    SystemChrome.setPreferredOrientations(
      isTablet
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [DeviceOrientation.portraitUp],
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
