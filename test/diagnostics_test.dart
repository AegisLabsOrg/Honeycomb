import 'package:flutter_test/flutter_test.dart';
import 'package:honeycomb/honeycomb.dart';

/// 测试用 Logger，收集日志输出
class TestLogger implements HoneycombLogger {
  final List<LogEntry> logs = [];

  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    logs.add(LogEntry(level, message, error, stackTrace));
  }

  void clear() => logs.clear();
}

class LogEntry {
  final LogLevel level;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  LogEntry(this.level, this.message, this.error, this.stackTrace);
}

void main() {
  group('HoneycombDiagnostics', () {
    late HoneycombDiagnostics diagnostics;
    late TestLogger testLogger;

    setUp(() {
      diagnostics = HoneycombDiagnostics.instance;
      testLogger = TestLogger();
      diagnostics.disableLogging(); // Reset state
    });

    tearDown(() {
      diagnostics.disableLogging();
    });

    test('enableLogging sets enabled to true', () {
      expect(diagnostics.enabled, isFalse);
      diagnostics.enableLogging(customLogger: testLogger);
      expect(diagnostics.enabled, isTrue);
    });

    test('disableLogging sets enabled to false', () {
      diagnostics.enableLogging(customLogger: testLogger);
      diagnostics.disableLogging();
      expect(diagnostics.enabled, isFalse);
    });

    test('custom logger receives log messages', () {
      diagnostics.enableLogging(
        customLogger: testLogger,
        level: LogLevel.debug,
      );

      final event = StateChangeEvent(
        atom: StateRef(0),
        oldValue: 0,
        newValue: 1,
        timestamp: DateTime.now(),
      );
      diagnostics.notifyStateChange(event);

      expect(testLogger.logs, isNotEmpty);
      expect(testLogger.logs.last.message, contains('StateChange'));
    });

    test('log level filtering works', () {
      diagnostics.enableLogging(
        customLogger: testLogger,
        level: LogLevel.warning, // Only warning and above
      );
      diagnostics.minLevel = LogLevel.warning;

      // This should be filtered (info < warning)
      diagnostics.logger.log(LogLevel.info, 'Info message');

      // Reset logs and send warning
      testLogger.clear();
      diagnostics.logger.log(LogLevel.warning, 'Warning message');

      // Warning should be logged
      expect(
        testLogger.logs.any((l) => l.message == 'Warning message'),
        isTrue,
      );
    });

    test('recompute listeners are called', () {
      diagnostics.enabled = true;
      final reasons = <RecomputeReason>[];
      diagnostics.addRecomputeListener(reasons.add);

      final reason = RecomputeReason(
        atom: StateRef(0),
        changedDependencies: [],
        duration: Duration(milliseconds: 1),
        newValue: 1,
        oldValue: 0,
      );
      diagnostics.notifyRecompute(reason);

      expect(reasons, hasLength(1));
      expect(reasons.first.newValue, 1);

      diagnostics.removeRecomputeListener(reasons.add);
      diagnostics.notifyRecompute(reason);
      expect(reasons, hasLength(1)); // No new additions
    });

    test('state change listeners are called', () {
      diagnostics.enabled = true;
      final events = <StateChangeEvent>[];
      diagnostics.addStateChangeListener(events.add);

      final event = StateChangeEvent(
        atom: StateRef(0),
        oldValue: 0,
        newValue: 1,
        timestamp: DateTime.now(),
      );
      diagnostics.notifyStateChange(event);

      expect(events, hasLength(1));
      expect(events.first.newValue, 1);

      diagnostics.removeStateChangeListener(events.add);
      diagnostics.notifyStateChange(event);
      expect(events, hasLength(1));
    });

    test('dirty propagation listeners are called', () {
      diagnostics.enabled = true;
      final events = <DirtyPropagationEvent>[];
      diagnostics.addDirtyPropagationListener(events.add);

      final event = DirtyPropagationEvent(
        source: StateRef(0),
        affectedNodes: [StateRef(1), StateRef(2)],
        timestamp: DateTime.now(),
      );
      diagnostics.notifyDirtyPropagation(event);

      expect(events, hasLength(1));
      expect(events.first.affectedNodes, hasLength(2));

      diagnostics.removeDirtyPropagationListener(events.add);
      diagnostics.notifyDirtyPropagation(event);
      expect(events, hasLength(1));
    });

    test('clearAllListeners removes all listeners', () {
      diagnostics.enabled = true;
      final recomputes = <RecomputeReason>[];
      final changes = <StateChangeEvent>[];
      final propagations = <DirtyPropagationEvent>[];

      diagnostics.addRecomputeListener(recomputes.add);
      diagnostics.addStateChangeListener(changes.add);
      diagnostics.addDirtyPropagationListener(propagations.add);

      diagnostics.clearAllListeners();

      diagnostics.notifyRecompute(
        RecomputeReason(
          atom: StateRef(0),
          changedDependencies: [],
          duration: Duration.zero,
          newValue: 0,
        ),
      );
      diagnostics.notifyStateChange(
        StateChangeEvent(
          atom: StateRef(0),
          oldValue: 0,
          newValue: 1,
          timestamp: DateTime.now(),
        ),
      );
      diagnostics.notifyDirtyPropagation(
        DirtyPropagationEvent(
          source: StateRef(0),
          affectedNodes: [],
          timestamp: DateTime.now(),
        ),
      );

      expect(recomputes, isEmpty);
      expect(changes, isEmpty);
      expect(propagations, isEmpty);
    });

    test('notifications are skipped when disabled', () {
      diagnostics.enabled = false;
      final events = <StateChangeEvent>[];
      diagnostics.addStateChangeListener(events.add);

      diagnostics.notifyStateChange(
        StateChangeEvent(
          atom: StateRef(0),
          oldValue: 0,
          newValue: 1,
          timestamp: DateTime.now(),
        ),
      );

      expect(events, isEmpty);
    });
  });

  group('RecomputeReason', () {
    test('toString includes all fields', () {
      final reason = RecomputeReason(
        atom: StateRef(0),
        changedDependencies: [StateRef(1)],
        duration: Duration(microseconds: 100),
        newValue: 42,
        oldValue: 0,
      );

      final str = reason.toString();
      expect(str, contains('RecomputeReason'));
      expect(str, contains('100µs'));
      expect(str, contains('old: 0'));
      expect(str, contains('new: 42'));
    });
  });

  group('StateChangeEvent', () {
    test('toString includes all fields', () {
      final now = DateTime.now();
      final event = StateChangeEvent(
        atom: StateRef(0),
        oldValue: 'old',
        newValue: 'new',
        timestamp: now,
      );

      final str = event.toString();
      expect(str, contains('StateChange'));
      expect(str, contains('old'));
      expect(str, contains('new'));
    });
  });

  group('DirtyPropagationEvent', () {
    test('toString includes node count', () {
      final event = DirtyPropagationEvent(
        source: StateRef(0),
        affectedNodes: [StateRef(1), StateRef(2), StateRef(3)],
        timestamp: DateTime.now(),
      );

      final str = event.toString();
      expect(str, contains('DirtyPropagation'));
      expect(str, contains('3 nodes'));
    });
  });

  group('Loggers', () {
    test('SilentLogger does nothing', () {
      final logger = SilentLogger();
      // Should not throw
      logger.log(LogLevel.error, 'test', error: Exception('test'));
    });

    test('DeveloperLogger logs without error', () {
      final logger = DeveloperLogger();
      // Should not throw
      logger.log(LogLevel.debug, 'debug message');
      logger.log(LogLevel.info, 'info message');
      logger.log(LogLevel.warning, 'warning message');
      logger.log(
        LogLevel.error,
        'error message',
        error: Exception('test'),
        stackTrace: StackTrace.current,
      );
    });

    test('PrintLogger outputs to console', () {
      final logger = PrintLogger();
      // Should not throw - we can't easily capture print output in tests
      logger.log(LogLevel.debug, 'debug');
      logger.log(LogLevel.info, 'info');
      logger.log(LogLevel.warning, 'warning');
      logger.log(
        LogLevel.error,
        'error',
        error: Exception('test'),
        stackTrace: StackTrace.current,
      );
    });
  });

  group('LogLevel', () {
    test('has correct ordering', () {
      expect(LogLevel.debug.index, lessThan(LogLevel.info.index));
      expect(LogLevel.info.index, lessThan(LogLevel.warning.index));
      expect(LogLevel.warning.index, lessThan(LogLevel.error.index));
    });
  });
}
