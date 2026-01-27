import 'dart:async';
import 'dart:collection';
import '../honeycomb.dart';
import 'diagnostics.dart';

/// Timestamped event for TTL strategy.
class _TimestampedEvent<T> {
  _TimestampedEvent(this.payload, this.timestamp);
  final T payload;
  final DateTime timestamp;
}

/// Manages the Effect event stream.
class EffectNode<T> {
  EffectNode(this.effect) {
    // Initialize buffers based on strategy.
    if (effect.strategy == EffectStrategy.bufferN) {
      _buffer = Queue<T>();
    } else if (effect.strategy == EffectStrategy.ttl) {
      _ttlBuffer = Queue<_TimestampedEvent<T>>();
    }
  }

  final Effect<T> effect;

  // Use a broadcast stream to allow multiple listeners (e.g. UI toast + logs).
  final StreamController<T> _controller = StreamController<T>.broadcast();

  // Buffer for bufferN strategy.
  Queue<T>? _buffer;

  // Timestamped buffer for TTL strategy.
  Queue<_TimestampedEvent<T>>? _ttlBuffer;

  void emit(T payload) {
    if (_isDisposed) return;

    if (HoneycombDiagnostics.instance.enabled) {
      HoneycombDiagnostics.instance.logger.log(
        LogLevel.info,
        'Effect emitted: ${effect.name ?? effect.key.toString()} -> $payload',
      );
    }

    switch (effect.strategy) {
      case EffectStrategy.drop:
        // Only emit when there is a listener.
        if (_controller.hasListener) {
          _controller.add(payload);
        }
        // Drop if no listeners.
        break;

      case EffectStrategy.bufferN:
        // Always add to buffer, regardless of listeners.
        if (_buffer != null) {
          _buffer!.add(payload);
          // Keep buffer size bounded.
          while (_buffer!.length > effect.bufferSize) {
            _buffer!.removeFirst();
          }
        }
        // Also emit if there are listeners.
        if (_controller.hasListener) {
          _controller.add(payload);
        }
        break;

      case EffectStrategy.ttl:
        // Add to timestamped buffer.
        if (_ttlBuffer != null) {
          _ttlBuffer!.add(_TimestampedEvent(payload, DateTime.now()));
          // Clean expired events.
          _cleanExpiredEvents();
        }
        // Also emit if there are listeners.
        if (_controller.hasListener) {
          _controller.add(payload);
        }
        break;
    }
  }

  /// Subscribe to the event stream (replays buffered events first).
  StreamSubscription<T> listen(void Function(T) callback) {
    // Replay buffer first.
    if (effect.strategy == EffectStrategy.bufferN && _buffer != null) {
      for (final event in _buffer!) {
        callback(event);
      }
    } else if (effect.strategy == EffectStrategy.ttl && _ttlBuffer != null) {
      _cleanExpiredEvents();
      for (final event in _ttlBuffer!) {
        callback(event.payload);
      }
    }

    // Then subscribe to subsequent events.
    return _controller.stream.listen(callback);
  }

  Stream<T> get stream => _controller.stream;

  /// Clean expired TTL events.
  void _cleanExpiredEvents() {
    if (_ttlBuffer == null) return;

    final now = DateTime.now();
    while (_ttlBuffer!.isNotEmpty) {
      final oldest = _ttlBuffer!.first;
      if (now.difference(oldest.timestamp) > effect.ttlDuration) {
        _ttlBuffer!.removeFirst();
      } else {
        break;
      }
    }
  }

  bool _isDisposed = false;

  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      _buffer?.clear();
      _ttlBuffer?.clear();
      _controller.close();
    }
  }
}
