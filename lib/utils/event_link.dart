class EventLink {
  const EventLink._();

  static const int maxLength = 2048;

  /// Normalizes a user-entered event link and accepts only public HTTPS URLs.
  ///
  /// A missing scheme is treated as HTTPS so that pasting `zoom.us/...` is
  /// convenient. Credentials, local hostnames, and IP literals are rejected to
  /// keep event links from becoming an internal-network or credential-phishing
  /// surface.
  static Uri? parse(String? input) {
    var value = input?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.length > maxLength ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(value)) {
      return null;
    }
    if (!value.contains('://')) value = 'https://$value';

    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment && uri.fragment.length > 512) {
      return null;
    }

    final host = uri.host.toLowerCase();
    final publicDomain = RegExp(
      r'^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+'
      r'(?:[a-z]{2,63}|xn--[a-z0-9-]{2,59})$',
      caseSensitive: false,
    );
    if (host == 'localhost' ||
        !publicDomain.hasMatch(host) ||
        RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$').hasMatch(host) ||
        host.startsWith('[')) {
      return null;
    }

    return uri.replace(scheme: 'https');
  }

  static String? normalize(String? input) => parse(input)?.toString();
}
