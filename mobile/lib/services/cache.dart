/// A bounded TTL cache, ported from `src/main/cache.ts`.
///
/// Insertion-ordered eviction: the oldest entry goes when the cap is reached.
/// Dart's `LinkedHashMap` preserves insertion order, which gives the same
/// behaviour as the JS `Map` the original relied on.
class TtlCache<T> {
  TtlCache(this.capacity);

  final int capacity;
  final Map<String, ({int at, T value})> _map = <String, ({int at, T value})>{};

  int? _now() => DateTime.now().millisecondsSinceEpoch;

  T? get(String key) {
    final hit = _map[key];
    if (hit == null) return null;
    return hit.value;
  }

  void set(String key, T value) {
    _map.remove(key);
    _map[key] = (at: _now()!, value: value);
    while (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
  }

  void clear() => _map.clear();

  /// Returns the cached value when it is younger than [ttlMs], otherwise runs
  /// [build] and stores the result. Concurrent callers share one in-flight
  /// future, so a burst of rebuilds never fires the same request twice.
  Future<R> wrap<R extends T>(String key, int ttlMs, Future<R> Function() build, [bool force = false]) {
    if (!force) {
      final hit = _map[key];
      if (hit != null && _now()! - hit.at < ttlMs) {
        // Refresh recency so hot keys are not evicted by cold ones.
        _map.remove(key);
        _map[key] = hit;
        return Future.value(hit.value as R);
      }
    }
    final pending = _pending[key];
    if (pending != null) return pending.then((v) => v as R);

    final future = build().then((value) {
      set(key, value);
      return value;
    }).whenComplete(() {
      // Block body on purpose: `remove` returns this very future, and a
      // Future returned here would make whenComplete wait on itself.
      _pending.remove(key);
    });
    _pending[key] = future;
    return future;
  }

  final Map<String, Future<Object?>> _pending = <String, Future<Object?>>{};
}

/// `60_000` — the original's `MIN`.
const int minute = 60 * 1000;
const int hour = 60 * minute;
const int day = 24 * hour;
