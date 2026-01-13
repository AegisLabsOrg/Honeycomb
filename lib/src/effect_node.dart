import 'dart:async';
import 'dart:collection';
import '../honeycomb.dart';

/// 带时间戳的事件，用于 TTL 策略
class _TimestampedEvent<T> {
  _TimestampedEvent(this.payload, this.timestamp);
  final T payload;
  final DateTime timestamp;
}

/// 负责管理 Effect 的事件流
class EffectNode<T> {
  EffectNode(this.effect) {
    // 根据策略初始化
    if (effect.strategy == EffectStrategy.bufferN) {
      _buffer = Queue<T>();
    } else if (effect.strategy == EffectStrategy.ttl) {
      _ttlBuffer = Queue<_TimestampedEvent<T>>();
    }
  }

  final Effect<T> effect;

  // 使用 broadcast 流，允许多个监听者 (如 UI 展示 Toast，同时也打 Log)
  final StreamController<T> _controller = StreamController<T>.broadcast();

  // bufferN 策略的缓冲区
  Queue<T>? _buffer;

  // ttl 策略的带时间戳缓冲区
  Queue<_TimestampedEvent<T>>? _ttlBuffer;

  void emit(T payload) {
    if (_isDisposed) return;

    switch (effect.strategy) {
      case EffectStrategy.drop:
        // 只有有监听者时才发送
        if (_controller.hasListener) {
          _controller.add(payload);
        }
        // 无监听者则丢弃
        break;

      case EffectStrategy.bufferN:
        // 无论是否有监听者都加入缓冲区
        if (_buffer != null) {
          _buffer!.add(payload);
          // 保持缓冲区大小
          while (_buffer!.length > effect.bufferSize) {
            _buffer!.removeFirst();
          }
        }
        // 如果有监听者，也发送
        if (_controller.hasListener) {
          _controller.add(payload);
        }
        break;

      case EffectStrategy.ttl:
        // 加入带时间戳的缓冲区
        if (_ttlBuffer != null) {
          _ttlBuffer!.add(_TimestampedEvent(payload, DateTime.now()));
          // 清理过期事件
          _cleanExpiredEvents();
        }
        // 如果有监听者，也发送
        if (_controller.hasListener) {
          _controller.add(payload);
        }
        break;
    }
  }

  /// 订阅事件流 (会先重放缓冲区中的事件)
  StreamSubscription<T> listen(void Function(T) callback) {
    // 先重放缓冲区
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

    // 然后订阅后续事件
    return _controller.stream.listen(callback);
  }

  Stream<T> get stream => _controller.stream;

  /// 清理过期的 TTL 事件
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
