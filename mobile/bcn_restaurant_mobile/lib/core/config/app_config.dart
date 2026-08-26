class AppConfig {
  const AppConfig._();

  static const baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://bcndemo-restaurant.nvi.frappe.cloud',
  );

  static Uri resolveAssetUrl(String? path) {
    if (path == null || path.trim().isEmpty) {
      return Uri();
    }
    final value = path.trim();
    final absolute = Uri.tryParse(value);
    if (absolute != null && absolute.hasScheme) {
      return absolute;
    }
    return Uri.parse(baseUrl).resolve(value);
  }
}
