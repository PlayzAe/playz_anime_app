import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../services/log.dart';

/// Scraping helpers shared by every HTML source.
///
/// The extensions we are porting (Madara, MangaThemesia, MangaStream …) are all
/// selector-driven, so this is the layer that turns a page into typed values
/// without every source re-implementing null handling.
abstract final class H {
  static final _log = Log('html');

  static dom.Document parse(String body) => html_parser.parse(body);

  /// First match for [selector], or null.
  static dom.Element? first(dom.Node? root, String selector) {
    if (root == null) return null;
    try {
      if (root is dom.Document) return root.querySelector(selector);
      if (root is dom.Element) return root.querySelector(selector);
      return null;
    } catch (err) {
      _log.warn('bad selector "$selector"', err);
      return null;
    }
  }

  static List<dom.Element> all(dom.Node? root, String selector) {
    if (root == null) return const [];
    try {
      if (root is dom.Document) return root.querySelectorAll(selector);
      if (root is dom.Element) return root.querySelectorAll(selector);
      return const [];
    } catch (err) {
      _log.warn('bad selector "$selector"', err);
      return const [];
    }
  }

  /// Trimmed text of the first match, or null when missing or blank.
  static String? text(dom.Node? root, String selector) {
    final el = first(root, selector);
    if (el == null) return null;
    final t = el.text.trim();
    return t.isEmpty ? null : t;
  }

  /// Trimmed text of an element, or null when blank.
  static String? ownText(dom.Element? el) {
    if (el == null) return null;
    final t = el.text.trim();
    return t.isEmpty ? null : t;
  }

  /// Attribute of the first match, or null.
  static String? attr(dom.Node? root, String selector, String name) =>
      first(root, selector)?.attributes[name];

  /// Attribute of the first match, restricted to a set of preferred names.
  ///
  /// Sites move between `data-src`, `data-lazy-src`, `srcset` and plain `src`
  /// for the same image, so every source would otherwise repeat this list.
  static String? img(dom.Element? el) {
    if (el == null) return null;
    for (final name in const ['data-src', 'data-lazy-src', 'data-original', 'data-url', 'src']) {
      final v = el.attributes[name]?.trim();
      if (v != null && v.isNotEmpty && !v.startsWith('data:image')) return v;
    }
    final srcset = el.attributes['srcset'] ?? el.attributes['data-srcset'];
    if (srcset != null && srcset.isNotEmpty) {
      // Pick the largest candidate: the last entry in most srcsets.
      final best = srcset.split(',').map((s) => s.trim().split(' ').first).where((s) => s.isNotEmpty).toList();
      if (best.isNotEmpty) return best.last;
    }
    final style = el.attributes['style'];
    if (style != null) {
      final m = RegExp(r'url\(([^)]+)\)').firstMatch(style);
      if (m != null) return _strip(m.group(1)!);
    }
    return null;
  }

  static String _strip(String raw) {
    var s = raw.trim();
    if (s.startsWith('"') || s.startsWith("'")) s = s.substring(1);
    if (s.endsWith('"') || s.endsWith("'")) s = s.substring(0, s.length - 1);
    return s;
  }

  /// Resolves a possibly-relative URL against the page it came from.
  static String absolute(String? url, String base) {
    if (url == null || url.isEmpty) return '';
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return trimmed;
    if (trimmed.startsWith('//')) return '${Uri.parse(base).scheme}:$trimmed';
    return Uri.parse(base).resolve(trimmed).toString();
  }

  /// The last path segment, the usual obfuscated id in a Madara permalink.
  static String slug(String url) {
    final clean = url.split('?').first.replaceAll(RegExp(r'/+$'), '');
    final parts = clean.split('/');
    return parts.isEmpty ? '' : parts.last;
  }

  static const Map<String, String> _entities = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'hellip': '…',
    'mdash': '—',
    'ndash': '–',
    'lsquo': '‘',
    'rsquo': '’',
    'ldquo': '“',
    'rdquo': '”',
    'middot': '·',
    'copy': '©',
    'reg': '®',
    'trade': '™',
  };

  /// Sites send titles HTML-escaped: `The Journey&#39;s End`.
  static String decodeEntities(String s) {
    if (!s.contains('&')) return s;
    return s.replaceAllMapped(RegExp(r'&(#x[0-9a-f]+|#\d+|[a-zA-Z]+);'), (m) {
      final code = m.group(1)!;
      if (code.startsWith('#')) {
        final isHex = code.length > 1 && (code[1] == 'x' || code[1] == 'X');
        final n = isHex ? int.tryParse(code.substring(2), radix: 16) : int.tryParse(code.substring(1));
        if (n == null) return m.group(0)!;
        try {
          return String.fromCharCode(n);
        } catch (_) {
          return m.group(0)!;
        }
      }
      return _entities[code.toLowerCase()] ?? m.group(0)!;
    });
  }

  /// Strips tags from a description block and normalises whitespace.
  static String stripTags(String html) => decodeEntities(
    html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'[ \t]+'), ' '),
  ).trim();

  /// `Chapter 12` / `Ch. 12.5` / `12` → `12.5`. Null when there is no number.
  static String? chapterNumber(String raw) {
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(raw);
    return m?.group(1);
  }

  static double chapterSortKey(String raw) {
    final n = chapterNumber(raw);
    return n == null ? -1 : (double.tryParse(n) ?? -1);
  }

  /// The `?page=2` style pager most Madara sites use, read back from the DOM.
  static bool hasNextPage(dom.Document doc) {
    final next = doc.querySelector('a.nextpostslink, a.next, .pagination a[rel=next], a[aria-label="Next"]');
    if (next == null) return false;
    final cls = next.attributes['class'] ?? '';
    return !cls.contains('disabled');
  }

  /// Some engines list pages as JSON in a `<script>`: pull the array out.
  static List<String> urlsFromScript(String html, RegExp keyPattern) {
    final m = keyPattern.firstMatch(html);
    if (m == null) return const [];
    return RegExp(r'''["'\\]*(https?:\\?/\\?/[^"'\\]+)''')
        .allMatches(m.group(0)!)
        .map((x) => x.group(1)!.replaceAll(r'\/', '/'))
        .toList();
  }
}
