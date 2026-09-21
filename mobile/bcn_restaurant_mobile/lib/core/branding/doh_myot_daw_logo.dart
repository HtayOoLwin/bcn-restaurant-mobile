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
    final encoded = await rootBundle.loadString(
      'assets/images/doh_myot_daw_logo.b64',
    );
    return base64Decode(encoded.trim());
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
            if (!snapshot.hasData) {
              return const DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFF171614)),
              );
            }

            return Image.memory(
              snapshot.data!,
              width: logoWidth,
              height: logoHeight,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
            );
          },
        ),
      ),
    );
  }
}
