import 'dart:async';

export 'honeycomb_container.dart';
export 'src/flutter_binding.dart';
export 'src/diagnostics.dart';
export 'src/compute_node.dart' show CircularDependencyError;

// --- Core Primitives ---

/// 状态原子基类
abstract class Atom<T> {
  const Atom();

  /// 用于依赖追踪的键
  Object get key;

  R accept<R>(AtomVisitor<R> visitor);
}

abstract class AtomVisitor<R> {
  R visitStateRef<T>(StateRef<T> atom);
  R visitComputed<T>(Computed<T> atom);
  R visitAsyncComputed<T>(AsyncComputed<T> atom);
  R visitEagerComputed<T>(EagerComputed<T> atom);
  R visitSafeComputed<T>(SafeComputed<T> atom);
  // Effect 通常不走 _getNode 创建 StateNode，所以可能不需要 visitEffect？
  // 但为了完整性...
  R visitEffect<T>(Effect<T> atom);
}

/// autoDispose 配置
enum DisposePolicy {
  /// 永不自动回收 (默认，向后兼容)
  keepAlive,

  /// 无人订阅时自动回收
  autoDispose,

  /// 延迟回收 (延迟一段时间再检查是否真的无人订阅)
  delayed,
}

/// 可读写的状态 (Replay Latest)
class StateRef<T> extends Atom<T> {
  StateRef(this.initialValue, {this.disposePolicy = DisposePolicy.keepAlive});
  final T initialValue;
  final DisposePolicy disposePolicy;

  /// 用于 Scope override
  Override<T> overrideWith(T value) {
    return Override<T>(this, value);
  }

  @override
  Object get key => this;

  @override
  R accept<R>(AtomVisitor<R> visitor) => visitor.visitStateRef(this);
}

/// Effect 投递策略
enum EffectStrategy {
  /// 无人订阅时丢弃事件 (默认，安全)
  drop,

  /// 环形缓冲 N 条，新订阅者收到缓冲区中的事件
  bufferN,

  /// 保留最近 X 时间内的事件
  ttl,
}

/// 纯副作用/一次性事件 (Event Stream)
/// 不持有状态，只负责分发事件 (如 Navigation, Toast, Analytics)
class Effect<T> extends Atom<T> {
  const Effect({
    this.name,
    this.strategy = EffectStrategy.drop,
    this.bufferSize = 10,
    this.ttlDuration = const Duration(seconds: 30),
  });

  final String? name;

  /// 投递策略
  final EffectStrategy strategy;

  /// bufferN 策略的缓冲区大小
  final int bufferSize;

  /// ttl 策略的保留时长
  final Duration ttlDuration;

  @override
  Object get key => this;

  @override
  R accept<R>(AtomVisitor<R> visitor) => visitor.visitEffect(this);
}

/// 派生状态 (Computed)
class Computed<T> extends Atom<T> {
  Computed(this.computeFn, {this.disposePolicy = DisposePolicy.keepAlive});

  final T Function(WatchFn watch) computeFn;
  final DisposePolicy disposePolicy;

  static AsyncComputed<T> async<T>(
    Future<T> Function(WatchFn watch) compute, {
    DisposePolicy disposePolicy = DisposePolicy.keepAlive,
  }) {
    return AsyncComputed(compute, disposePolicy: disposePolicy);
  }

  /// 急切模式 - 上游变化立即重算
  static EagerComputed<T> eager<T>(
    T Function(WatchFn watch) compute, {
    DisposePolicy disposePolicy = DisposePolicy.keepAlive,
  }) {
    return EagerComputed(compute, disposePolicy: disposePolicy);
  }

  @override
  Object get key => this;

  @override
  R accept<R>(AtomVisitor<R> visitor) => visitor.visitComputed(this);
}

class AsyncComputed<T> extends Atom<AsyncValue<T>> {
  AsyncComputed(this.computeFn, {this.disposePolicy = DisposePolicy.keepAlive});

  final Future<T> Function(WatchFn watch) computeFn;
  final DisposePolicy disposePolicy;

  @override
  Object get key => this;

  @override
  R accept<R>(AtomVisitor<R> visitor) => visitor.visitAsyncComputed(this);
}

/// 急切求值的 Computed - 上游变化时立即重算，即使没有订阅者
class EagerComputed<T> extends Atom<T> {
  EagerComputed(this.computeFn, {this.disposePolicy = DisposePolicy.keepAlive});

  final T Function(WatchFn watch) computeFn;
  final DisposePolicy disposePolicy;

  @override
  Object get key => this;

  @override
  R accept<R>(AtomVisitor<R> visitor) => visitor.visitEagerComputed(this);
}

// --- Result Type for Safe Computed ---

/// 同步计算结果封装，类似 AsyncValue 但用于同步计算
sealed class Result<T> {
  const Result();

  const factory Result.success(T value) = ResultSuccess<T>;
  const factory Result.failure(Object error, StackTrace stackTrace) =
      ResultFailure<T>;

  T? get valueOrNull;
  bool get isSuccess;
  bool get isFailure;

  /// 获取值，失败时抛出异常
  T get requireValue;

  R when<R>({
    required R Function(T value) success,
    required R Function(Object error, StackTrace stackTrace) failure,
  });

  /// 转换成功值
  Result<R> map<R>(R Function(T) transform);

  /// 失败时返回默认值
  T getOrElse(T defaultValue);
}

class ResultSuccess<T> extends Result<T> {
  const ResultSuccess(this.value);
  final T value;

  @override
  T? get valueOrNull => value;

  @override
  bool get isSuccess => true;

  @override
  bool get isFailure => false;

  @override
  T get requireValue => value;

  @override
  R when<R>({
    required R Function(T value) success,
    required R Function(Object error, StackTrace stackTrace) failure,
  }) {
    return success(value);
  }

  @override
  Result<R> map<R>(R Function(T) transform) {
    try {
      return Result.success(transform(value));
    } catch (e, st) {
      return Result.failure(e, st);
    }
  }

  @override
  T getOrElse(T defaultValue) => value;
}

class ResultFailure<T> extends Result<T> {
  const ResultFailure(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;

  @override
  T? get valueOrNull => null;

  @override
  bool get isSuccess => false;

  @override
  bool get isFailure => true;

  @override
  T get requireValue => throw error;

  @override
  R when<R>({
    required R Function(T value) success,
    required R Function(Object error, StackTrace stackTrace) failure,
  }) {
    return failure(error, stackTrace);
  }

  @override
  Result<R> map<R>(R Function(T) transform) {
    return Result.failure(error, stackTrace);
  }

  @override
  T getOrElse(T defaultValue) => defaultValue;
}

/// 安全的 Computed - 异常会被捕获并封装为 Result.failure
class SafeComputed<T> extends Atom<Result<T>> {
  SafeComputed(this.computeFn, {this.disposePolicy = DisposePolicy.keepAlive});

  final T Function(WatchFn watch) computeFn;
  final DisposePolicy disposePolicy;

  @override
  Object get key => this;

  @override
  R accept<R>(AtomVisitor<R> visitor) => visitor.visitSafeComputed(this);
}

// --- Async Utilities ---

sealed class AsyncValue<T> {
  const AsyncValue();

  const factory AsyncValue.loading({T? previous}) = AsyncLoading<T>;
  const factory AsyncValue.data(T value) = AsyncData<T>;
  const factory AsyncValue.error(Object error, StackTrace stackTrace) =
      AsyncError<T>;

  T? get valueOrNull;

  R when<R>({
    required R Function() loading,
    required R Function(T data) data,
    required R Function(Object error, StackTrace stackTrace) error,
  });
}

class AsyncLoading<T> extends AsyncValue<T> {
  const AsyncLoading({this.previous});
  final T? previous;

  @override
  T? get valueOrNull => previous;

  @override
  R when<R>({
    required R Function() loading,
    required R Function(T data) data,
    required R Function(Object error, StackTrace stackTrace) error,
  }) {
    return loading();
  }
}

class AsyncData<T> extends AsyncValue<T> {
  const AsyncData(this.value);
  final T value;

  @override
  T? get valueOrNull => value;

  @override
  R when<R>({
    required R Function() loading,
    required R Function(T data) data,
    required R Function(Object error, StackTrace stackTrace) error,
  }) {
    return data(value);
  }
}

class AsyncError<T> extends AsyncValue<T> {
  const AsyncError(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;

  @override
  T? get valueOrNull => null;

  @override
  R when<R>({
    required R Function() loading,
    required R Function(T data) data,
    required R Function(Object error, StackTrace stackTrace) error,
  }) {
    return error(this.error, stackTrace);
  }
}

// --- Dependency Injection / Scope ---

class Override<T> {
  Override(this.atom, this.value);
  final Atom<T> atom;
  final T value;
}

/// 依赖追踪函数签名
typedef WatchFn = T Function<T>(Atom<T> atom);

/// Selector 增强扩展方法
extension AtomSelect<T> on Atom<T> {
  /// 选择单个字段，只在 selector 结果变化时触发
  /// 如果提供了 [equals]，使用自定义比较器
  Atom<R> select<R>(
    R Function(T value) selector, {
    bool Function(R, R)? equals,
  }) {
    if (equals == null) {
      // 简单版本 - 使用默认 == 比较
      return Computed((watch) => selector(watch(this)));
    }

    // 带比较器的版本 - 使用闭包保存状态
    R? lastValue;
    bool hasValue = false;

    return Computed((watch) {
      final newValue = selector(watch(this));
      if (hasValue && equals(lastValue as R, newValue)) {
        return lastValue as R;
      }
      lastValue = newValue;
      hasValue = true;
      return newValue;
    });
  }

  /// 选择多个字段，任一变化都触发
  Atom<List<R>> selectMany<R>(List<R Function(T)> selectors) {
    return Computed((watch) {
      final value = watch(this);
      return selectors.map((s) => s(value)).toList();
    });
  }

  /// 条件过滤，只在条件为 true 时返回值
  Atom<T?> where(bool Function(T) predicate) {
    return Computed((watch) {
      final value = watch(this);
      return predicate(value) ? value : null;
    });
  }
}
