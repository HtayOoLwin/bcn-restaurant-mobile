import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DohMyotDawLogo extends StatelessWidget {
  const DohMyotDawLogo({
    super.key,
    this.width,
    this.height,
  });

  final double? width;
  final double? height;

  static final Future<Uint8List> _logoBytes = _loadLogoBytes();

  static Future<Uint8List> _loadLogoBytes() async {
    final parts = await Future.wait([
      rootBundle.loadString('assets/images/doh_myot_daw_logo_1.b64'),
      rootBundle.loadString('assets/images/doh_myot_daw_logo_2.b64'),
      rootBundle.loadString('assets/images/doh_myot_daw_logo_3.b64'),
    ]);

    final encoded = parts
        .map((part) => part.replaceAll(RegExp(r'\s+'), ''))
        .join();

    return base64Decode(encoded);
  }

  @override
  Widget build(BuildContext context) {
    final logoWidth = width ?? 160;
    final logoHeight = height ?? width ?? 160;

    return SizedBox(
      width: logoWidth,
      height: logoHeight,
      child: ClipOval(
        child: FutureBuilder<Uint8List>(
          future: _logoBytes,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return Image.memory(
                snapshot.data!,
                width: logoWidth,
                height: logoHeight,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              );
            }

            return const DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFF171614)),
              child: Center(
                child: Icon(
                  Icons.restaurant_rounded,
                  color: Color(0xFFD7A34B),
                  size: 42,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
