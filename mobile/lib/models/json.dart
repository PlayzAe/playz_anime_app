/// Small, allocation-light JSON accessors.
///
/// AniList returns `null` for almost every optional field, and the wire shapes
/// are stable, so typed getters beat `as Map<String, dynamic>` casts sprinkled
/// through every parser — and they never throw on a field AniList omits.
extension JsonMap on Map {
  String? str(dynamic key) {
    final v = this[key];
    return v is String ? v : null;
  }

  int? integer(dynamic key) {
    final v = this[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  double? number(dynamic key) {
    final v = this[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  bool? boolean(dynamic key) {
    final v = this[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    return null;
  }

  Map<String, dynamic>? obj(dynamic key) {
    final v = this[key];
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  Map<String, dynamic>? subMap(dynamic key) => obj(key);

  List<dynamic>? list(dynamic key) {
    final v = this[key];
    return v is List ? v : null;
  }

  List<String>? stringList(dynamic key) {
    final v = this[key];
    if (v is! List) return null;
    return [
      for (final e in v)
        if (e != null) e.toString(),
    ];
  }

  DateTime? date(dynamic key) {
    final v = this[key];
    if (v is! String) return null;
    return DateTime.tryParse(v);
  }
}

/// `Map<String, dynamic>` for the shapes that are always objects.
Map<String, dynamic> asMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
