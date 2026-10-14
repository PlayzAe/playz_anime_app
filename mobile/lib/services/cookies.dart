/// A small, dependency-free cookie jar.
///
/// Needed for two things the desktop build got for free from Chromium:
///  1. keeping a session across redirects within one source, and
///  2. holding a `cf_clearance` cookie so a Cloudflare-gated site lets the app
///     past its interstitial.
///
/// Deliberately not `cookie_jar` + `dio_cookie_manager`: `FileStorage` imports
/// `dart:io`, which breaks the web build. This version serialises to plain JSON
/// and lets the caller decide where to keep it.
class CookieJar {
  final Map<String, Map<String, _Cookie>> _byDomain = <String, Map<String, _Cookie>>{};

  /// Every cookie we know about, newest write wins.
  void set(
    String domain,
    String name,
    String value, {
    String path = '/',
    bool secure = false,
    int? expiresAt,
  }) {
    final host = _normaliseDomain(domain);
    if (host.isEmpty) return;
    final bucket = _byDomain.putIfAbsent(host, () => <String, _Cookie>{});
    bucket['$path|$name'] = _Cookie(
      name: name,
      value: value,
      path: path,
      secure: secure,
      expiresAt: expiresAt,
    );
  }

  /// Parses the `Set-Cookie` header(s) from a response.
  void absorb(String url, List<String> setCookieHeaders) {
    final host = _hostOf(url);
    if (host.isEmpty) return;
    for (final raw in setCookieHeaders) {
      // A single header can carry several cookies joined by ", " — split only on
      // the boundary before a `name=` token, since Expires contains a comma.
      for (final part in _splitSetCookie(raw)) {
        final cookie = _parseSetCookie(part, host);
        if (cookie == null) continue;
        _byDomain
            .putIfAbsent(cookie.domain, () => <String, _Cookie>{})['${cookie.path}|${cookie.name}'] = cookie;
      }
    }
  }

  /// The `Cookie:` header value for a request, or null when there is nothing to send.
  String? headerFor(String url) {
    final host = _hostOf(url);
    if (host.isEmpty) return null;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final out = <String>[];
    final isHttps = url.startsWith('https:');

    for (final entry in _byDomain.entries) {
      if (!_domainMatches(host, entry.key)) continue;
      for (final c in entry.value.values) {
        if (c.expiresAt != null && c.expiresAt! <= now) continue;
        if (c.secure && !isHttps) continue;
        out.add('${c.name}=${c.value}');
      }
    }
    return out.isEmpty ? null : out.join('; ');
  }

  /// The raw `cf_clearance=…` style string, for Settings to display back.
  List<String> rawFor(String domain) {
    final host = _normaliseDomain(domain);
    final bucket = _byDomain[host];
    if (bucket == null) return const [];
    return [
      for (final c in bucket.values) '${c.name}=${c.value}',
    ];
  }

  /// Seeds a cookie from a `name=value; name2=value2` string the user pasted.
  void paste(String domain, String raw) {
    for (final piece in raw.split(';')) {
      final trimmed = piece.trim();
      if (trimmed.isEmpty) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final name = trimmed.substring(0, eq).trim();
      final value = trimmed.substring(eq + 1).trim();
      if (name.isEmpty) continue;
      set(domain, name, value, secure: true, expiresAt: null);
    }
  }

  void clearDomain(String domain) => _byDomain.remove(_normaliseDomain(domain));

  void clear() => _byDomain.clear();

  bool get isEmpty => _byDomain.isEmpty;

  Map<String, dynamic> toJson() => {
    for (final e in _byDomain.entries)
      e.key: {
        for (final c in e.value.entries)
          c.key: {
            'n': c.value.name,
            'v': c.value.value,
            'p': c.value.path,
            's': c.value.secure,
            if (c.value.expiresAt != null) 'e': c.value.expiresAt,
          },
      },
  };

  void loadJson(Map<String, dynamic> json) {
    _byDomain.clear();
    for (final domain in json.entries) {
      final bucket = domain.value;
      if (bucket is! Map) continue;
      final target = _byDomain.putIfAbsent(domain.key, () => <String, _Cookie>{});
      for (final key in bucket.entries) {
        final raw = key.value;
        if (raw is! Map) continue;
        target[key.key] = _Cookie(
          name: raw['n']?.toString() ?? '',
          value: raw['v']?.toString() ?? '',
          path: raw['p']?.toString() ?? '/',
          secure: raw['s'] == true,
          expiresAt: raw['e'] is int ? raw['e'] as int : null,
        );
      }
    }
  }

  // ── internals ─────────────────────────────────────────────────────────────

  static String _hostOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    return _normaliseDomain(uri.host);
  }

  static String _normaliseDomain(String d) => d.toLowerCase().replaceFirst(RegExp(r'^\.'), '');

  /// RFC 6265 domain matching: exact, or a suffix with a dot boundary.
  static bool _domainMatches(String host, String domain) =>
      host == domain || host.endsWith('.$domain');

  static Iterable<String> _splitSetCookie(String raw) sync* {
    // Split on ',' only when the next token looks like `name=`.
    final re = RegExp(r',(?=\s*[A-Za-z0-9!#$%&\x27*+\-.^_`|~]+=)');
    for (final part in raw.split(re)) {
      yield part;
    }
  }

  static _Cookie? _parseSetCookie(String raw, String requestHost) {
    final pieces = raw.split(';');
    if (pieces.isEmpty) return null;
    final first = pieces.first.trim();
    final eq = first.indexOf('=');
    if (eq <= 0) return null;
    final name = first.substring(0, eq).trim();
    final value = first.substring(eq + 1).trim();
    if (name.isEmpty) return null;

    var path = '/';
    var secure = false;
    var domain = '';
    int? expiresAt;

    for (final attr in pieces.skip(1)) {
      final t = attr.trim();
      final i = t.indexOf('=');
      final key = (i < 0 ? t : t.substring(0, i)).trim().toLowerCase();
      final v = i < 0 ? '' : t.substring(i + 1).trim();
      switch (key) {
        case 'path':
          path = v.isEmpty ? '/' : v;
        case 'secure':
          secure = true;
        case 'domain':
          domain = _normaliseDomain(v);
        case 'max-age':
          final secs = int.tryParse(v);
          if (secs != null) expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + secs;
        case 'expires':
          final d = _parseHttpDate(v);
          if (d != null) expiresAt = d.millisecondsSinceEpoch ~/ 1000;
      }
    }

    // A cookie without an explicit Domain belongs to the host that set it.
    final owned = domain.isEmpty ? requestHost : domain;
    if (!_domainMatches(requestHost, owned)) return null;

    return _Cookie(
      name: name,
      value: value,
      path: path,
      secure: secure,
      expiresAt: expiresAt,
      domain: owned,
    );
  }

  static const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

  /// `Wed, 21 Oct 2015 07:28:00 GMT`
  static DateTime? _parseHttpDate(String raw) {
    final m = RegExp(r'(\d{1,2})[-\s](\w{3})[-\s](\d{2,4})\s+(\d{2}):(\d{2}):(\d{2})').firstMatch(raw);
    if (m == null) return null;
    final day = int.tryParse(m.group(1)!);
    final month = _months.indexOf(m.group(2)!.toLowerCase()) + 1;
    var year = int.tryParse(m.group(3)!) ?? 0;
    if (year < 100) year += 2000;
    if (day == null || month == 0) return null;
    return DateTime.utc(
      year,
      month,
      day,
      int.tryParse(m.group(4)!) ?? 0,
      int.tryParse(m.group(5)!) ?? 0,
      int.tryParse(m.group(6)!) ?? 0,
    );
  }
}

class _Cookie {
  _Cookie({
    required this.name,
    required this.value,
    required this.path,
    required this.secure,
    this.expiresAt,
    this.domain = '',
  });

  final String name;
  final String value;
  final String path;
  final bool secure;
  final int? expiresAt;
  final String domain;
}
