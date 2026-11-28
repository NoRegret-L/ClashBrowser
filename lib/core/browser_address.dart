/// The native view independently enforces this restriction for navigations.
Uri? browserAddress(String value) {
  var text = value.trim();
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
      !RegExp(r'^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$').hasMatch(uri.host) ||
      !RegExp(r'[a-zA-Z]').hasMatch(uri.host) ||
      uri.host.toLowerCase().endsWith('.localhost')) return null;
  return uri;
}
