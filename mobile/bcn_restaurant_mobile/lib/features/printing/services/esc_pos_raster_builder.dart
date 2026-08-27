import 'dart:ui' as ui;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:image/image.dart' as image;

import '../domain/printer_config.dart';

class TicketLine {
  const TicketLine(
    this.text, {
    this.bold = false,
    this.center = false,
    this.sizeFactor = 1,
  });

  final String text;
  final bool bold;
  final bool center;
  final double sizeFactor;
}

class EscPosRasterBuilder {
  const EscPosRasterBuilder();

  Future<List<int>> build({
    required PrinterConfig config,
    required List<TicketLine> lines,
  }) async {
    final capability = await CapabilityProfile.load();
    final paperSize = config.paperWidthMm == 80
        ? PaperSize.mm80
        : PaperSize.mm58;
    final generator = Generator(paperSize, capability);
    final raster = await _render(lines, config);
    final bytes = <int>[
      ...generator.reset(),
      ...generator.imageRaster(raster, align: PosAlign.center),
      ...generator.feed(3),
    ];
    if (config.autoCut) bytes.addAll(generator.cut());
    return bytes;
  }

  Future<List<int>> buildTestTicket(PrinterConfig config, DateTime now) {
    final date =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    return build(
      config: config,
      lines: [
        const TicketLine(
          'BCN RESTAURANT',
          bold: true,
          center: true,
          sizeFactor: 1.35,
        ),
        const TicketLine('PRINTER TEST', bold: true, center: true),
        const TicketLine('--------------------------------'),
        TicketLine('Printer : ${config.displayName}'),
        TicketLine(
          'Connect : ${config.connectionType == PrinterConnectionType.bluetooth ? 'Bluetooth' : 'Wi-Fi'}',
        ),
        TicketLine('Paper   : ${config.paperWidthMm} mm'),
        TicketLine('Date    : $date'),
        const TicketLine('English Test: ABC 123'),
        const TicketLine('မြန်မာစာ စမ်းသပ်မှု'),
        if (config.footerRemark.isNotEmpty) ...[
          const TicketLine('--------------------------------'),
          TicketLine(config.footerRemark, center: true),
        ],
      ],
    );
  }

  Future<image.Image> _render(
    List<TicketLine> lines,
    PrinterConfig config,
  ) async {
    final width = config.paperWidthMm == 80 ? 576 : 384;
    final painters = <painting.TextPainter>[];
    var totalHeight = 16.0;
    for (final line in lines) {
      final painter = painting.TextPainter(
        text: painting.TextSpan(
          text: line.text,
          style: painting.TextStyle(
            color: const ui.Color(0xFF000000),
            fontSize: config.fontSizePx * line.sizeFactor,
            fontWeight: line.bold ? ui.FontWeight.w700 : ui.FontWeight.w500,
            height: 1.25,
            fontFamilyFallback: const [
              'Noto Sans Myanmar',
              'Pyidaungsu',
              'Arial',
            ],
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        textAlign: line.center ? ui.TextAlign.center : ui.TextAlign.left,
        locale: const ui.Locale('my'),
      )..layout(maxWidth: width - 24);
      painters.add(painter);
      totalHeight += painter.height + 5;
    }

    final height = totalHeight.ceil().clamp(32, 6000).toInt();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    var y = 8.0;
    for (var index = 0; index < painters.length; index++) {
      final painter = painters[index];
      final centered = lines[index].center;
      final x = centered ? (width - painter.width) / 2 : 12.0;
      painter.paint(canvas, ui.Offset(x, y));
      y += painter.height + 5;
    }
    final rendered = await recorder.endRecording().toImage(width, height);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    final decoded = data == null
        ? null
        : image.decodePng(data.buffer.asUint8List());
    if (decoded == null) throw StateError('Unable to render printer ticket.');
    return decoded;
  }
}
