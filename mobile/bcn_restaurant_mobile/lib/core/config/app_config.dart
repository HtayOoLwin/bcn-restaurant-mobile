class AppConfig {
  const AppConfig._();

  static const baseUrl = 'https://ourcity-testing.s.frappe.cloud';

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
