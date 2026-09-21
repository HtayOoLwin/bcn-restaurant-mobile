import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'doh_myot_daw_logo_data_1.dart';
import 'doh_myot_daw_logo_data_2.dart';
import 'doh_myot_daw_logo_data_3.dart';
import 'doh_myot_daw_logo_data_4.dart';
import 'doh_myot_daw_logo_data_5.dart';
import 'doh_myot_daw_logo_data_6.dart';

final Uint8List dohMyotDawLogoBytes = base64Decode(
  dohMyotDawLogoData1 +
      dohMyotDawLogoData2 +
      dohMyotDawLogoData3 +
      dohMyotDawLogoData4 +
      dohMyotDawLogoData5 +
      dohMyotDawLogoData6,
);

class DohMyotDawLogo extends StatelessWidget {
  const DohMyotDawLogo({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.circular = false,
  });

  final double? width;
  final double? height;
  final BoxFit fit;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final image = Image.memory(
      dohMyotDawLogoBytes,
      width: width,
      height: height,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.high,
    );

    if (!circular) return image;
    return ClipOval(child: image);
  }
}
