import 'package:flutter/services.dart';

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const ThousandsSeparatorInputFormatter({this.maxDecimalPlaces = 2});

  final int maxDecimalPlaces;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(',', '').trim();
    if (raw.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final parts = raw.split('.');
    if (parts.length > 2 ||
        parts.first.contains(RegExp(r'[^0-9]')) ||
        (parts.length == 2 && parts[1].contains(RegExp(r'[^0-9]'))) ||
        (parts.length == 2 && parts[1].length > maxDecimalPlaces)) {
      return oldValue;
    }

    final integerDigits = parts.first.isEmpty ? '0' : parts.first;
    final normalizedInteger = integerDigits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final groupedInteger = normalizedInteger.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );

    final formatted = parts.length == 2
        ? '$groupedInteger.${parts[1]}'
        : groupedInteger;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
