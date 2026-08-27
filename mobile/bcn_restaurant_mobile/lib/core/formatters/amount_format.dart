String formatAmount(num value, {int maxDecimalPlaces = 2}) {
  final number = value.toDouble();
  final isNegative = number < 0;
  final absolute = number.abs();

  String raw;
  if (absolute == absolute.roundToDouble()) {
    raw = absolute.toInt().toString();
  } else {
    raw = absolute.toStringAsFixed(maxDecimalPlaces);
    while (raw.contains('.') && raw.endsWith('0')) {
      raw = raw.substring(0, raw.length - 1);
    }
    if (raw.endsWith('.')) {
      raw = raw.substring(0, raw.length - 1);
    }
  }

  final parts = raw.split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final decimal = parts.length > 1 ? '.${parts[1]}' : '';
  return '${isNegative ? '-' : ''}$grouped$decimal';
}

String formatMoney(num value, String currency) {
  final amount = formatAmount(value);
  final unit = currency.trim();
  return unit.isEmpty ? amount : '$amount $unit';
}

String formatQuantity(num value) => formatAmount(value);
