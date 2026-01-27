import 'dart:developer' as developer;
import '../honeycomb.dart';

/// Log level.
enum LogLevel { debug, info, warning, error }

/// Pluggable logger interface.
abstract class HoneycombLogger {
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  });
}

/// Default logger using dart:developer.
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

/// Silent logger (no output).
class SilentLogger implements HoneycombLogger {
  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

/// Console logger (prints to stdout).
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

/// Recompute reason.
class RecomputeReason {
  RecomputeReason({
    required this.atom,
    required this.changedDependencies,
    required this.duration,
    required this.newValue,
    this.oldValue,
  });

  /// Atom being recomputed.
  final Atom atom;

  /// Upstream dependencies that caused recompute.
  final List<Atom> changedDependencies;

  /// Recompute duration.
  final Duration duration;

  /// New value.
  final dynamic newValue;

  /// Old value (may be null).
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

/// State change event.
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

/// Dirty propagation event.
class DirtyPropagationEvent {
  DirtyPropagationEvent({
    required this.source,
    required this.affectedNodes,
    required this.timestamp,
  });

  /// Source atom that triggered propagation.
  final Atom source;

  /// Downstream nodes marked dirty.
  final List<Atom> affectedNodes;

  final DateTime timestamp;

  @override
  String toString() {
    return 'DirtyPropagation($source → ${affectedNodes.length} nodes)';
  }
}

/// Observability hook callback types.
typedef OnRecompute = void Function(RecomputeReason reason);
typedef OnStateChange = void Function(StateChangeEvent event);
typedef OnDirtyPropagation = void Function(DirtyPropagationEvent event);

/// Global diagnostics configuration.
class HoneycombDiagnostics {
  HoneycombDiagnostics._();

  static final instance = HoneycombDiagnostics._();

  /// Whether diagnostics are enabled (default: off).
  bool enabled = false;

  /// Pluggable logger (defaults to dart:developer).
  HoneycombLogger logger = DeveloperLogger();

  /// Minimum log level.
  LogLevel minLevel = LogLevel.debug;

  /// Recompute callbacks.
  final List<OnRecompute> _onRecomputeListeners = [];

  /// State change callbacks.
  final List<OnStateChange> _onStateChangeListeners = [];

  /// Dirty propagation callbacks.
  final List<OnDirtyPropagation> _onDirtyPropagationListeners = [];

  /// Add recompute listener.
  void addRecomputeListener(OnRecompute listener) {
    _onRecomputeListeners.add(listener);
  }

  void removeRecomputeListener(OnRecompute listener) {
    _onRecomputeListeners.remove(listener);
  }

  /// Add state change listener.
  void addStateChangeListener(OnStateChange listener) {
    _onStateChangeListeners.add(listener);
  }

  void removeStateChangeListener(OnStateChange listener) {
    _onStateChangeListeners.remove(listener);
  }

  /// Add dirty propagation listener.
  void addDirtyPropagationListener(OnDirtyPropagation listener) {
    _onDirtyPropagationListeners.add(listener);
  }

  void removeDirtyPropagationListener(OnDirtyPropagation listener) {
    _onDirtyPropagationListeners.remove(listener);
  }

  /// Notify recompute (internal).
  void notifyRecompute(RecomputeReason reason) {
    if (!enabled) return;
    for (final listener in _onRecomputeListeners) {
      listener(reason);
    }
  }

  /// Notify state change (internal).
  void notifyStateChange(StateChangeEvent event) {
    if (!enabled) return;
    for (final listener in _onStateChangeListeners) {
      listener(event);
    }
  }

  /// Notify dirty propagation (internal).
  void notifyDirtyPropagation(DirtyPropagationEvent event) {
    if (!enabled) return;
    for (final listener in _onDirtyPropagationListeners) {
      listener(event);
    }
  }

  /// Clear all listeners.
  void clearAllListeners() {
    _onRecomputeListeners.clear();
    _onStateChangeListeners.clear();
    _onDirtyPropagationListeners.clear();
  }

  /// Internal logging helper.
  void _log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!enabled || level.index < minLevel.index) return;
    logger.log(level, message, error: error, stackTrace: stackTrace);
  }

  /// Enable logging (with configurable logger).
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

  /// Disable all logging.
  void disableLogging() {
    enabled = false;
    logger = SilentLogger();
    clearAllListeners();
  }
}
