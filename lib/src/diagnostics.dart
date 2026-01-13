import 'dart:developer' as developer;
import '../honeycomb.dart';

/// 日志级别
enum LogLevel { debug, info, warning, error }

/// 可插拔的 Logger 接口
abstract class HoneycombLogger {
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  });
}

/// 默认 Logger - 使用 dart:developer
class DeveloperLogger implements HoneycombLogger {
  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: 'Honeycomb',
      level: _levelToInt(level),
      error: error,
      stackTrace: stackTrace,
    );
  }

  int _levelToInt(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
    }
  }
}

/// 静默 Logger - 不输出任何内容
class SilentLogger implements HoneycombLogger {
  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

/// 控制台 Logger - 直接 print 到终端
class PrintLogger implements HoneycombLogger {
  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final prefix = _levelPrefix(level);
    // ignore: avoid_print
    print('$prefix [Honeycomb] $message');
    if (error != null) {
      // ignore: avoid_print
      print('  Error: $error');
    }
    if (stackTrace != null) {
      // ignore: avoid_print
      print('  $stackTrace');
    }
  }

  String _levelPrefix(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return '🔍';
      case LogLevel.info:
        return '💡';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
    }
  }
}

/// 重算原因
class RecomputeReason {
  RecomputeReason({
    required this.atom,
    required this.changedDependencies,
    required this.duration,
    required this.newValue,
    this.oldValue,
  });

  /// 被重算的 Atom
  final Atom atom;

  /// 导致重算的上游依赖
  final List<Atom> changedDependencies;

  /// 重算耗时
  final Duration duration;

  /// 新值
  final dynamic newValue;

  /// 旧值 (可能为 null)
  final dynamic oldValue;

  @override
  String toString() {
    return 'RecomputeReason('
        'atom: $atom, '
        'changedDeps: $changedDependencies, '
        'duration: ${duration.inMicroseconds}µs, '
        'old: $oldValue, '
        'new: $newValue)';
  }
}

/// 状态变更事件
class StateChangeEvent {
  StateChangeEvent({
    required this.atom,
    required this.oldValue,
    required this.newValue,
    required this.timestamp,
  });

  final Atom atom;
  final dynamic oldValue;
  final dynamic newValue;
  final DateTime timestamp;

  @override
  String toString() {
    return 'StateChange($atom: $oldValue → $newValue @ $timestamp)';
  }
}

/// Dirty 传播事件
class DirtyPropagationEvent {
  DirtyPropagationEvent({
    required this.source,
    required this.affectedNodes,
    required this.timestamp,
  });

  /// 触发传播的源 Atom
  final Atom source;

  /// 被标记为 dirty 的下游节点
  final List<Atom> affectedNodes;

  final DateTime timestamp;

  @override
  String toString() {
    return 'DirtyPropagation($source → ${affectedNodes.length} nodes)';
  }
}

/// 可观测性钩子回调类型
typedef OnRecompute = void Function(RecomputeReason reason);
typedef OnStateChange = void Function(StateChangeEvent event);
typedef OnDirtyPropagation = void Function(DirtyPropagationEvent event);

/// 全局诊断配置
class HoneycombDiagnostics {
  HoneycombDiagnostics._();

  static final instance = HoneycombDiagnostics._();

  /// 是否启用诊断 (默认关闭)
  bool enabled = false;

  /// 可插拔的 Logger (默认使用 dart:developer)
  HoneycombLogger logger = DeveloperLogger();

  /// 最小日志级别
  LogLevel minLevel = LogLevel.debug;

  /// 重算回调
  final List<OnRecompute> _onRecomputeListeners = [];

  /// 状态变更回调
  final List<OnStateChange> _onStateChangeListeners = [];

  /// Dirty 传播回调
  final List<OnDirtyPropagation> _onDirtyPropagationListeners = [];

  /// 添加重算监听
  void addRecomputeListener(OnRecompute listener) {
    _onRecomputeListeners.add(listener);
  }

  void removeRecomputeListener(OnRecompute listener) {
    _onRecomputeListeners.remove(listener);
  }

  /// 添加状态变更监听
  void addStateChangeListener(OnStateChange listener) {
    _onStateChangeListeners.add(listener);
  }

  void removeStateChangeListener(OnStateChange listener) {
    _onStateChangeListeners.remove(listener);
  }

  /// 添加 Dirty 传播监听
  void addDirtyPropagationListener(OnDirtyPropagation listener) {
    _onDirtyPropagationListeners.add(listener);
  }

  void removeDirtyPropagationListener(OnDirtyPropagation listener) {
    _onDirtyPropagationListeners.remove(listener);
  }

  /// 通知重算事件 (内部调用)
  void notifyRecompute(RecomputeReason reason) {
    if (!enabled) return;
    for (final listener in _onRecomputeListeners) {
      listener(reason);
    }
  }

  /// 通知状态变更事件 (内部调用)
  void notifyStateChange(StateChangeEvent event) {
    if (!enabled) return;
    for (final listener in _onStateChangeListeners) {
      listener(event);
    }
  }

  /// 通知 Dirty 传播事件 (内部调用)
  void notifyDirtyPropagation(DirtyPropagationEvent event) {
    if (!enabled) return;
    for (final listener in _onDirtyPropagationListeners) {
      listener(event);
    }
  }

  /// 清除所有监听器
  void clearAllListeners() {
    _onRecomputeListeners.clear();
    _onStateChangeListeners.clear();
    _onDirtyPropagationListeners.clear();
  }

  /// 内部日志方法
  void _log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!enabled || level.index < minLevel.index) return;
    logger.log(level, message, error: error, stackTrace: stackTrace);
  }

  /// 启用日志记录 (使用可配置的 Logger)
  void enableLogging({HoneycombLogger? customLogger, LogLevel? level}) {
    enabled = true;
    if (customLogger != null) logger = customLogger;
    if (level != null) minLevel = level;

    addRecomputeListener((reason) {
      _log(
        LogLevel.debug,
        'Recompute: ${reason.atom} (${reason.duration.inMicroseconds}µs)',
      );
    });

    addStateChangeListener((event) {
      _log(
        LogLevel.info,
        'StateChange: ${event.atom}: ${event.oldValue} → ${event.newValue}',
      );
    });

    addDirtyPropagationListener((event) {
      _log(
        LogLevel.debug,
        'DirtyPropagation: ${event.source} → ${event.affectedNodes.length} nodes',
      );
    });
  }

  /// 禁用所有日志
  void disableLogging() {
    enabled = false;
    logger = SilentLogger();
    clearAllListeners();
  }
}
