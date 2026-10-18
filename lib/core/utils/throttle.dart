import 'dart:async';

/// Leading + trailing throttle per key.
///
/// The first value of a window is delivered immediately; further values
/// within the window are collapsed and only the newest is delivered when the
/// window closes. High-frequency system callbacks therefore never reach the
/// UI faster than [interval], and the last value is never lost.
class KeyedThrottle<K, V> {
  KeyedThrottle({required this.interval, required this.onValue});

  /// Evaluated per window so setting changes apply immediately.
  final Duration Function() interval;
  final void Function(K key, V value) onValue;

  final Map<K, _Window<V>> _windows = {};
  bool _disposed = false;

  void add(K key, V value) {
    if (_disposed) return;
    final w = _windows[key];
    if (w == null) {
      onValue(key, value);
      _open(key);
    } else {
      w.pending = value;
      w.hasPending = true;
    }
  }

  void _open(K key) {
    _windows[key] = _Window<V>(Timer(interval(), () => _close(key)));
  }

  void _close(K key) {
    final w = _windows.remove(key);
    if (_disposed || w == null) return;
    if (w.hasPending) {
      onValue(key, w.pending as V);
      _open(key);
    }
  }

  /// Drops pending values and cancels timers.
  void dispose() {
    _disposed = true;
    for (final w in _windows.values) {
      w.timer.cancel();
    }
    _windows.clear();
  }

  /// Cancels pending values but allows reuse.
  void clear() {
    for (final w in _windows.values) {
      w.timer.cancel();
    }
    _windows.clear();
  }
}

class _Window<V> {
  _Window(this.timer);
  final Timer timer;
  V? pending;
  bool hasPending = false;
}
