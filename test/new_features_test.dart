import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_honeycomb/honeycomb.dart';

void main() {
  group('autoDispose / keepAlive', () {
    test('keepAlive (default) - node persists after unsubscribe', () {
      final container = HoneycombContainer();
      final counter = StateRef(0); // default: keepAlive

      container.write(counter, 5);

      final cancel = container.subscribe(counter, () {});
      cancel(); // unsubscribe

      // Node should still exist and retain value
      expect(container.read(counter), 5);

      container.dispose();
    });

    test('autoDispose - node is disposed when no subscribers', () {
      final container = HoneycombContainer();
      final counter = StateRef(0, disposePolicy: DisposePolicy.autoDispose);

      container.write(counter, 5);

      final cancel = container.subscribe(counter, () {});
      expect(container.read(counter), 5);

      cancel(); // unsubscribe - should trigger dispose

      // Reading again should create a new node with initial value
      expect(container.read(counter), 0);

      container.dispose();
    });

    test('delayed dispose - waits before disposing', () async {
      HoneycombContainer.delayedDisposeDelay = const Duration(milliseconds: 50);

      final container = HoneycombContainer();
      final counter = StateRef(0, disposePolicy: DisposePolicy.delayed);

      container.write(counter, 5);

      final cancel = container.subscribe(counter, () {});
      cancel();

      // Immediately after unsubscribe, value should still be there
      expect(container.read(counter), 5);

      // Wait for delayed dispose
      await Future.delayed(const Duration(milliseconds: 100));

      // After delay, should be reset to initial
      expect(container.read(counter), 0);

      container.dispose();
    });

    test('keepAlive() prevents autoDispose', () {
      final container = HoneycombContainer();
      final counter = StateRef(0, disposePolicy: DisposePolicy.autoDispose);

      container.write(counter, 5);
      container.keepAlive(counter); // prevent dispose

      final cancel = container.subscribe(counter, () {});
      cancel();

      // Should still have the value
      expect(container.read(counter), 5);

      container.dispose();
    });
  });

  group('Effect strategies', () {
    test('drop strategy - events lost when no listener', () async {
      final container = HoneycombContainer();
      final toast = Effect<String>(strategy: EffectStrategy.drop);

      // Emit before any listener
      container.emit(toast, 'Hello');
      container.emit(toast, 'World');

      final events = <String>[];
      container.on(toast, events.add);

      // Should not receive buffered events
      expect(events, isEmpty);

      // New events should be received
      container.emit(toast, 'New');

      // Give the stream time to deliver
      await Future.delayed(Duration.zero);

      expect(events, ['New']);

      container.dispose();
    });

    test('bufferN strategy - replays buffered events', () {
      final container = HoneycombContainer();
      final toast = Effect<String>(
        strategy: EffectStrategy.bufferN,
        bufferSize: 3,
      );

      // Emit before any listener
      container.emit(toast, 'A');
      container.emit(toast, 'B');
      container.emit(toast, 'C');
      container.emit(toast, 'D'); // Should push out 'A'

      final events = <String>[];
      container.on(toast, events.add);

      // Should receive buffered events (B, C, D)
      expect(events, ['B', 'C', 'D']);

      container.dispose();
    });

    test('ttl strategy - only replays recent events', () async {
      final container = HoneycombContainer();
      final toast = Effect<String>(
        strategy: EffectStrategy.ttl,
        ttlDuration: const Duration(milliseconds: 100),
      );

      container.emit(toast, 'Old');
      await Future.delayed(const Duration(milliseconds: 150));
      container.emit(toast, 'New');

      final events = <String>[];
      container.on(toast, events.add);

      // Only 'New' should be replayed, 'Old' is expired
      expect(events, ['New']);

      container.dispose();
    });
  });

  group('Selector enhancements', () {
    test('select with custom equals', () {
      final container = HoneycombContainer();
      final user = StateRef({'name': 'Alice', 'age': 30});

      int computeCount = 0;
      final name = user.select((u) {
        computeCount++;
        return u['name'];
      }, equals: (a, b) => a == b);

      expect(container.read(name), 'Alice');
      expect(computeCount, 1);

      // Change age but not name
      container.write(user, {'name': 'Alice', 'age': 31});
      expect(container.read(name), 'Alice');
      expect(computeCount, 2); // Recomputed but returned same value

      // Change name
      container.write(user, {'name': 'Bob', 'age': 31});
      expect(container.read(name), 'Bob');

      container.dispose();
    });

    test('selectMany - tracks multiple fields', () {
      final container = HoneycombContainer();
      final user = StateRef({'name': 'Alice', 'avatar': 'a.png'});

      final displayInfo = user.selectMany([
        (u) => u['name'] as String,
        (u) => u['avatar'] as String,
      ]);

      expect(container.read(displayInfo), ['Alice', 'a.png']);

      container.write(user, {'name': 'Bob', 'avatar': 'b.png'});
      expect(container.read(displayInfo), ['Bob', 'b.png']);

      container.dispose();
    });

    test('where - conditional filtering', () {
      final container = HoneycombContainer();
      final value = StateRef(5);

      final filtered = value.where((v) => v > 3);

      expect(container.read(filtered), 5);

      container.write(value, 2);
      expect(container.read(filtered), null);

      container.write(value, 10);
      expect(container.read(filtered), 10);

      container.dispose();
    });
  });

  group('EagerComputed', () {
    test('eager computed recomputes immediately', () {
      final container = HoneycombContainer();
      final a = StateRef(1);

      int computeCount = 0;
      final eager = Computed.eager((watch) {
        computeCount++;
        return watch(a) * 2;
      });

      // Just reading creates and computes
      expect(container.read(eager), 2);
      expect(computeCount, 1);

      // Changing a should immediately recompute, even without subscription
      container.write(a, 5);
      // Read to verify
      expect(container.read(eager), 10);
      expect(computeCount, 2);

      container.dispose();
    });
  });

  group('SafeComputed (error handling)', () {
    test('captures exceptions as Result.failure', () {
      final container = HoneycombContainer();
      final shouldFail = StateRef(false);

      final safe = SafeComputed((watch) {
        if (watch(shouldFail)) {
          throw Exception('Computation failed!');
        }
        return 'OK';
      });

      // Initially succeeds
      final result1 = container.read(safe);
      expect(result1.isSuccess, true);
      expect(result1.valueOrNull, 'OK');

      // Trigger failure
      container.write(shouldFail, true);
      final result2 = container.read(safe);
      expect(result2.isFailure, true);
      expect(result2.valueOrNull, null);

      // Recover
      container.write(shouldFail, false);
      final result3 = container.read(safe);
      expect(result3.isSuccess, true);
      expect(result3.valueOrNull, 'OK');

      container.dispose();
    });

    test('Result.when pattern matching', () {
      final success = Result<int>.success(42);
      final failure = Result<int>.failure(Exception('err'), StackTrace.empty);

      final successResult = success.when(
        success: (v) => 'Value: $v',
        failure: (e, st) => 'Error: $e',
      );
      expect(successResult, 'Value: 42');

      final failureResult = failure.when(
        success: (v) => 'Value: $v',
        failure: (e, st) => 'Error',
      );
      expect(failureResult, 'Error');
    });

    test('Result.map transforms success', () {
      final success = Result<int>.success(21);
      final mapped = success.map((v) => v * 2);
      expect(mapped.valueOrNull, 42);

      final failure = Result<int>.failure(Exception('err'), StackTrace.empty);
      final mappedFailure = failure.map((v) => v * 2);
      expect(mappedFailure.isFailure, true);
    });
  });

  group('Diagnostics / Observability', () {
    test('diagnostics can be enabled and listeners called', () {
      final diag = HoneycombDiagnostics.instance;
      diag.clearAllListeners();
      diag.enabled = true;

      final stateChanges = <StateChangeEvent>[];
      diag.addStateChangeListener(stateChanges.add);

      // Simulate a state change notification
      diag.notifyStateChange(
        StateChangeEvent(
          atom: StateRef(0),
          oldValue: 0,
          newValue: 1,
          timestamp: DateTime.now(),
        ),
      );

      expect(stateChanges.length, 1);
      expect(stateChanges.first.oldValue, 0);
      expect(stateChanges.first.newValue, 1);

      diag.clearAllListeners();
      diag.enabled = false;
    });

    test('diagnostics disabled - no callbacks', () {
      final diag = HoneycombDiagnostics.instance;
      diag.clearAllListeners();
      diag.enabled = false;

      final stateChanges = <StateChangeEvent>[];
      diag.addStateChangeListener(stateChanges.add);

      diag.notifyStateChange(
        StateChangeEvent(
          atom: StateRef(0),
          oldValue: 0,
          newValue: 1,
          timestamp: DateTime.now(),
        ),
      );

      expect(stateChanges, isEmpty);

      diag.clearAllListeners();
    });
  });

  group('Hot Reload support', () {
    test('invalidateAllComputed marks computed as dirty', () {
      final container = HoneycombContainer();
      final a = StateRef(1);

      int computeCount = 0;
      final derived = Computed((watch) {
        computeCount++;
        return watch(a) * 2;
      });

      // Initial read
      expect(container.read(derived), 2);
      expect(computeCount, 1);

      // Read again without changes - should use cached value
      expect(container.read(derived), 2);
      expect(computeCount, 1);

      // Simulate hot reload
      container.invalidateAllComputed();

      // Next read should recompute
      expect(container.read(derived), 2);
      expect(computeCount, 2);

      container.dispose();
    });
  });
}
