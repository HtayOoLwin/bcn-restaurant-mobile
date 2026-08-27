import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:image/image.dart' as image;

import '../domain/printer_config.dart';

class TicketColumns {
  const TicketColumns({
    required this.qty,
    required this.description,
    required this.rate,
    required this.amount,
  });

  final String qty;
  final String description;
  final String rate;
  final String amount;
}

class TicketLine {
  const TicketLine(
    this.text, {
    this.bold = false,
    this.center = false,
    this.right = false,
    this.sizeFactor = 1,
  }) : isDottedRule = false,
       columns = null;

  const TicketLine.dottedRule()
    : text = '',
      bold = false,
      center = false,
      right = false,
      sizeFactor = 1,
      isDottedRule = true,
      columns = null;

  const TicketLine.columns({
    required String qty,
    required String description,
    required String rate,
    required String amount,
    this.bold = false,
    this.sizeFactor = 0.82,
  }) : text = '',
       center = false,
       right = false,
       isDottedRule = false,
       columns = TicketColumns(
         qty: qty,
         description: description,
         rate: rate,
         amount: amount,
       );

  final String text;
  final bool bold;
  final bool center;
  final bool right;
  final double sizeFactor;
  final bool isDottedRule;
  final TicketColumns? columns;
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
      ...generator.feed(1),
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
          sizeFactor: 1.25,
        ),
        const TicketLine('PRINTER TEST', bold: true, center: true),
        const TicketLine.dottedRule(),
        TicketLine('Printer : ${config.displayName}'),
        TicketLine(
          'Connect : ${config.connectionType == PrinterConnectionType.bluetooth ? 'Bluetooth' : 'Wi-Fi'}',
        ),
        TicketLine('Paper   : ${config.paperWidthMm} mm'),
        TicketLine('Date    : $date'),
        const TicketLine('English Test: ABC 123'),
        const TicketLine('မြန်မာစာ စမ်းသပ်မှု'),
        if (config.footerRemark.isNotEmpty) ...[
          const TicketLine.dottedRule(),
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
    const margin = 8.0;
    const gap = 2.0;
    final contentWidth = width - (margin * 2);
    final renderedLines = <_RenderedLine>[];
    var totalHeight = 4.0;

    for (final line in lines) {
      final rendered = line.isDottedRule
          ? const _RenderedLine.rule(height: 8)
          : line.columns != null
          ? _renderColumns(line, config, contentWidth)
          : _renderText(line, config, contentWidth);
      renderedLines.add(rendered);
      totalHeight += rendered.height + gap;
    }

    final height = totalHeight.ceil().clamp(24, 6000).toInt();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    var y = 2.0;
    for (final rendered in renderedLines) {
      if (rendered.isRule) {
        _paintDottedRule(canvas, margin, width - margin, y + 3);
      } else {
        for (final cell in rendered.cells) {
          cell.painter.paint(canvas, ui.Offset(margin + cell.x, y));
        }
      }
      y += rendered.height + gap;
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

  _RenderedLine _renderText(
    TicketLine line,
    PrinterConfig config,
    double contentWidth,
  ) {
    final painter =
        _textPainter(
          line.text,
          fontSize: config.fontSizePx * line.sizeFactor,
          bold: line.bold,
          align: line.center
              ? ui.TextAlign.center
              : line.right
              ? ui.TextAlign.right
              : ui.TextAlign.left,
        )..layout(
          minWidth: line.center || line.right ? contentWidth : 0,
          maxWidth: contentWidth,
        );
    return _RenderedLine(
      height: line.text.isEmpty ? 3 : painter.height,
      cells: [_RenderedCell(x: 0, painter: painter)],
    );
  }

  _RenderedLine _renderColumns(
    TicketLine line,
    PrinterConfig config,
    double contentWidth,
  ) {
    final values = line.columns!;
    final qtyWidth = contentWidth * 0.12;
    final descriptionWidth = contentWidth * 0.43;
    final rateWidth = contentWidth * 0.21;
    final amountWidth = contentWidth - qtyWidth - descriptionWidth - rateWidth;
    final widths = [qtyWidth, descriptionWidth, rateWidth, amountWidth];
    final texts = [values.qty, values.description, values.rate, values.amount];
    final aligns = [
      ui.TextAlign.left,
      ui.TextAlign.left,
      ui.TextAlign.right,
      ui.TextAlign.right,
    ];
    final cells = <_RenderedCell>[];
    var x = 0.0;
    var height = 0.0;
    for (var index = 0; index < texts.length; index++) {
      final painter = _textPainter(
        texts[index],
        fontSize: config.fontSizePx * line.sizeFactor,
        bold: line.bold,
        align: aligns[index],
      )..layout(minWidth: widths[index], maxWidth: widths[index]);
      cells.add(_RenderedCell(x: x, painter: painter));
      height = math.max(height, painter.height).toDouble();
      x += widths[index];
    }
    return _RenderedLine(height: height, cells: cells);
  }

  painting.TextPainter _textPainter(
    String text, {
    required double fontSize,
    required bool bold,
    required ui.TextAlign align,
  }) {
    return painting.TextPainter(
      text: painting.TextSpan(
        text: text,
        style: painting.TextStyle(
          color: const ui.Color(0xFF000000),
          fontSize: fontSize,
          fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w500,
          height: 1.12,
          fontFamilyFallback: const [
            'Noto Sans Myanmar',
            'Pyidaungsu',
            'Arial',
          ],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: align,
      locale: const ui.Locale('my'),
    );
  }

  void _paintDottedRule(ui.Canvas canvas, double start, double end, double y) {
    final paint = ui.Paint()
      ..color = const ui.Color(0xFF000000)
      ..strokeWidth = 1.5;
    for (var x = start; x < end; x += 6) {
      canvas.drawLine(
        ui.Offset(x, y),
        ui.Offset(math.min(x + 3, end), y),
        paint,
      );
    }
  }
}

class _RenderedLine {
  const _RenderedLine({required this.height, required this.cells})
    : isRule = false;

  const _RenderedLine.rule({required this.height})
    : cells = const [],
      isRule = true;

  final double height;
  final List<_RenderedCell> cells;
  final bool isRule;
}

class _RenderedCell {
  const _RenderedCell({required this.x, required this.painter});

  final double x;
  final painting.TextPainter painter;
}
