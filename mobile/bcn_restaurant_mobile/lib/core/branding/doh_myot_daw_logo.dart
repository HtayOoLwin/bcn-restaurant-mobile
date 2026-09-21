import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Uint8List? _dohMyotDawLogoBytes;

Future<void> preloadDohMyotDawLogo() async {
  if (_dohMyotDawLogoBytes != null) return;

  final parts = await Future.wait([
    rootBundle.loadString('assets/images/doh_myot_daw_logo_1.b64'),
    rootBundle.loadString('assets/images/doh_myot_daw_logo_2.b64'),
    rootBundle.loadString('assets/images/doh_myot_daw_logo_3.b64'),
  ]);

  final encoded = parts.map((part) => part.trim()).join();
  _dohMyotDawLogoBytes = base64Decode(encoded);
}

class DohMyotDawLogo extends StatelessWidget {
  const DohMyotDawLogo({
    super.key,
    this.width,
    this.height,
  });

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final logoWidth = width ?? 160;
    final logoHeight = height ?? width ?? 160;
    final bytes = _dohMyotDawLogoBytes;

    return SizedBox(
      width: logoWidth,
      height: logoHeight,
      child: ClipOval(
        child: bytes == null
            ? const DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFF171614)),
                child: Center(
                  child: Icon(
                    Icons.restaurant_rounded,
                    color: Color(0xFFD7A34B),
                    size: 42,
                  ),
                ),
              )
            : Image.memory(
                bytes,
                width: logoWidth,
                height: logoHeight,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
      ),
    );
  }
}
