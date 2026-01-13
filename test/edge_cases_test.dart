import 'package:flutter_test/flutter_test.dart';
import 'package:honeycomb/honeycomb.dart';

void main() {
  group('AsyncComputeNode', () {
    test('initial state is loading', () async {
      final container = HoneycombContainer();
      final source = StateRef(1);
      final async = Computed.async((watch) async {
        return watch(source) * 10;
      });

      final value = container.read(async);
      expect(value, isA<AsyncLoading<int>>());

      container.dispose();
    });

    test('resolves to data', () async {
      final container = HoneycombContainer();
      final source = StateRef(5);
      final async = Computed.async((watch) async {
        await Future.delayed(const Duration(milliseconds: 10));
        return watch(source) * 2;
      });

      // Trigger computation
      container.read(async);

      // Wait for async completion
      await Future.delayed(const Duration(milliseconds: 50));

      final value = container.read(async);
      expect(value, isA<AsyncData<int>>());
      expect((value as AsyncData).value, 10);

      container.dispose();
    });

    test('handles errors', () async {
      final container = HoneycombContainer();
      final async = Computed.async((watch) async {
        await Future.delayed(const Duration(milliseconds: 10));
        throw Exception('test error');
      });

      container.read(async);
      await Future.delayed(const Duration(milliseconds: 50));

      final value = container.read(async);
      expect(value, isA<AsyncError<int>>());

      container.dispose();
    });

    test('recomputes when dependency changes', () async {
      final container = HoneycombContainer();
      final source = StateRef(1);
      final async = Computed.async((watch) async {
        await Future.delayed(const Duration(milliseconds: 10));
        return watch(source) * 10;
      });

      // First computation
      container.read(async);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(container.read(async).valueOrNull, 10);

      // Change source
      container.write(source, 2);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(container.read(async).valueOrNull, 20);

      container.dispose();
    });

    test('discards stale results (race condition)', () async {
      final container = HoneycombContainer();
      final source = StateRef(1);
      int callCount = 0;

      final async = Computed.async((watch) async {
        final val = watch(source);
        callCount++;
        // First call takes longer
        await Future.delayed(Duration(milliseconds: val == 1 ? 100 : 10));
        return val * 10;
      });

      // Start first computation
      container.read(async);
      await Future.delayed(const Duration(milliseconds: 5));

      // Change source before first completes
      container.write(source, 2);
      await Future.delayed(const Duration(milliseconds: 150));

      // Should have result from second computation only
      expect(container.read(async).valueOrNull, 20);
      expect(callCount, 2);

      container.dispose();
    });

    test('preserves previous value during loading', () async {
      final container = HoneycombContainer();
      final source = StateRef(1);
      final async = Computed.async((watch) async {
        await Future.delayed(const Duration(milliseconds: 10));
        return watch(source) * 10;
      });

      // First load
      container.read(async);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(container.read(async).valueOrNull, 10);

      // Trigger reload
      container.write(source, 2);
      final loading = container.read(async);
      expect(loading, isA<AsyncLoading<int>>());
      expect((loading as AsyncLoading).previous, 10);

      container.dispose();
    });

    test('invalidate triggers recomputation', () async {
      final container = HoneycombContainer();
      int computeCount = 0;
      final async = Computed.async((watch) async {
        computeCount++;
        return 42;
      });

      container.read(async);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(computeCount, 1);

      container.invalidate(async);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(computeCount, 2);

      container.dispose();
    });

    test('disposes correctly', () async {
      final container = HoneycombContainer();
      final source = StateRef(1);
      final async = Computed.async((watch) async {
        return watch(source);
      });

      container.read(async);
      await Future.delayed(const Duration(milliseconds: 50));

      // This should not throw
      container.dispose();
    });

    test('subscription triggers computation', () async {
      final container = HoneycombContainer();
      int computeCount = 0;
      final async = Computed.async((watch) async {
        computeCount++;
        return 42;
      });

      // Subscribe without reading
      final cancel = container.subscribe(async, () {});
      await Future.delayed(const Duration(milliseconds: 50));

      expect(computeCount, 1);
      expect(container.read(async).valueOrNull, 42);

      cancel();
      container.dispose();
    });
  });

  group('EagerComputeNode', () {
    test('computes immediately on creation', () {
      final container = HoneycombContainer();
      final source = StateRef(5);
      int computeCount = 0;

      final eager = Computed.eager((watch) {
        computeCount++;
        return watch(source) * 2;
      });

      // Read triggers creation which triggers computation
      final value = container.read(eager);
      expect(value, 10);
      expect(computeCount, 1);

      container.dispose();
    });

    test('recomputes immediately when dependency changes', () {
      final container = HoneycombContainer();
      final source = StateRef(1);
      int computeCount = 0;

      final eager = Computed.eager((watch) {
        computeCount++;
        return watch(source) * 10;
      });

      container.read(eager);
      expect(computeCount, 1);

      // Even without watching, changing source should recompute
      container.write(source, 2);
      expect(computeCount, 2);

      expect(container.read(eager), 20);

      container.dispose();
    });

    test('detects circular dependency', () {
      final container = HoneycombContainer();
      late EagerComputed<int> eager;

      eager = Computed.eager((watch) {
        return watch(eager) + 1;
      });

      expect(
        () => container.read(eager),
        throwsA(isA<CircularDependencyError>()),
      );

      container.dispose();
    });

    test('markDirty triggers recomputation', () {
      final container = HoneycombContainer();
      final source = StateRef(1);
      int computeCount = 0;

      final eager = Computed.eager((watch) {
        computeCount++;
        return watch(source);
      });

      container.read(eager);
      expect(computeCount, 1);

      container.invalidate(eager);
      expect(computeCount, 2);

      container.dispose();
    });

    test('disposes correctly', () {
      final container = HoneycombContainer();
      final source = StateRef(1);

      final eager = Computed.eager((watch) {
        return watch(source) * 2;
      });

      container.read(eager);
      container.dispose();
      // Should not throw
    });

    test('value does not change when result is same', () {
      final container = HoneycombContainer();
      final source = StateRef(10);

      final eager = Computed.eager((watch) {
        return watch(source) > 5 ? 'big' : 'small';
      });

      container.read(eager);

      int notifyCount = 0;
      container.subscribe(eager, () => notifyCount++);

      // Change source but result stays same
      container.write(source, 20);
      expect(notifyCount, 0); // No notification since value is still 'big'

      container.write(source, 3);
      // This might notify since value changes to 'small'
      expect(container.read(eager), 'small');

      container.dispose();
    });
  });

  group('SafeComputeNode', () {
    test('returns success for normal computation', () {
      final container = HoneycombContainer();
      final source = StateRef(10);

      final safe = SafeComputed((watch) {
        return watch(source) * 2;
      });

      final result = container.read(safe);
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, 20);

      container.dispose();
    });

    test('captures exceptions as failure', () {
      final container = HoneycombContainer();
      final source = StateRef(-5);

      final safe = SafeComputed((watch) {
        final val = watch(source);
        if (val < 0) {
          throw ArgumentError('must be positive');
        }
        return val;
      });

      final result = container.read(safe);
      expect(result.isFailure, isTrue);
      expect(result.valueOrNull, isNull);

      container.dispose();
    });

    test('updates when dependency changes', () {
      final container = HoneycombContainer();
      final source = StateRef(5);

      final safe = SafeComputed((watch) {
        return watch(source) * 3;
      });

      expect(container.read(safe).valueOrNull, 15);

      container.write(source, 10);
      expect(container.read(safe).valueOrNull, 30);

      container.dispose();
    });

    test('transitions between success and failure', () {
      final container = HoneycombContainer();
      final source = StateRef(5);

      final safe = SafeComputed((watch) {
        final val = watch(source);
        if (val < 0) {
          throw StateError('negative');
        }
        return val * 2;
      });

      expect(container.read(safe).isSuccess, isTrue);

      container.write(source, -1);
      expect(container.read(safe).isFailure, isTrue);

      container.write(source, 10);
      expect(container.read(safe).isSuccess, isTrue);
      expect(container.read(safe).valueOrNull, 20);

      container.dispose();
    });

    test('detects circular dependency', () {
      final container = HoneycombContainer();
      late SafeComputed<int> safe;

      safe = SafeComputed((watch) {
        return watch(safe).valueOrNull ?? 0;
      });

      expect(
        () => container.read(safe),
        throwsA(isA<CircularDependencyError>()),
      );

      container.dispose();
    });

    test('markDirty triggers recomputation', () {
      final container = HoneycombContainer();
      int computeCount = 0;

      final safe = SafeComputed((watch) {
        computeCount++;
        return 42;
      });

      container.read(safe);
      expect(computeCount, 1);

      container.invalidate(safe);
      container.read(safe);
      expect(computeCount, 2);

      container.dispose();
    });

    test('disposes correctly', () {
      final container = HoneycombContainer();
      final source = StateRef(1);

      final safe = SafeComputed((watch) => watch(source));

      container.read(safe);
      container.dispose();
    });

    test('recomputes when subscribed and dirty', () {
      final container = HoneycombContainer();
      final source = StateRef(1);
      int computeCount = 0;

      final safe = SafeComputed((watch) {
        computeCount++;
        return watch(source);
      });

      int notifyCount = 0;
      container.subscribe(safe, () => notifyCount++);

      expect(computeCount, 1); // Initial compute

      container.write(source, 2);
      // Should recompute because there's a subscriber
      expect(computeCount, 2);
      expect(notifyCount, 1);

      container.dispose();
    });
  });

  group('EffectNode', () {
    test('drop strategy - emits to listeners', () async {
      final container = HoneycombContainer();
      final effect = Effect<String>(strategy: EffectStrategy.drop);
      final received = <String>[];

      container.on(effect, received.add);
      container.emit(effect, 'hello');

      await Future.delayed(Duration.zero);
      expect(received, ['hello']);

      container.dispose();
    });

    test('drop strategy - discards when no listener', () async {
      final container = HoneycombContainer();
      final effect = Effect<String>(strategy: EffectStrategy.drop);
      final received = <String>[];

      // Emit before listening
      container.emit(effect, 'lost');

      // Now listen
      container.on(effect, received.add);
      container.emit(effect, 'received');

      await Future.delayed(Duration.zero);
      expect(received, ['received']);

      container.dispose();
    });

    test('bufferN strategy - replays buffer to new listener', () {
      final container = HoneycombContainer();
      final effect = Effect<int>(
        strategy: EffectStrategy.bufferN,
        bufferSize: 3,
      );

      container.emit(effect, 1);
      container.emit(effect, 2);
      container.emit(effect, 3);
      container.emit(effect, 4);
      container.emit(effect, 5);

      final received = <int>[];
      container.on(effect, received.add);

      // Should get last 3: 3, 4, 5
      expect(received, [3, 4, 5]);

      container.dispose();
    });

    test('bufferN strategy - also emits live events', () async {
      final container = HoneycombContainer();
      final effect = Effect<int>(
        strategy: EffectStrategy.bufferN,
        bufferSize: 2,
      );

      final received = <int>[];
      container.on(effect, received.add);

      container.emit(effect, 10);
      container.emit(effect, 20);

      await Future.delayed(Duration.zero);
      expect(received, [10, 20]);

      container.dispose();
    });

    test('ttl strategy - only replays non-expired events', () async {
      final container = HoneycombContainer();
      final effect = Effect<String>(
        strategy: EffectStrategy.ttl,
        ttlDuration: const Duration(milliseconds: 50),
      );

      container.emit(effect, 'old');
      await Future.delayed(const Duration(milliseconds: 100));
      container.emit(effect, 'new');

      final received = <String>[];
      container.on(effect, received.add);

      // Only 'new' should be replayed
      expect(received, ['new']);

      container.dispose();
    });

    test('ttl strategy - emits to live listeners', () async {
      final container = HoneycombContainer();
      final effect = Effect<String>(
        strategy: EffectStrategy.ttl,
        ttlDuration: const Duration(seconds: 10),
      );

      final received = <String>[];
      container.on(effect, received.add);

      container.emit(effect, 'live');
      await Future.delayed(Duration.zero);

      expect(received, ['live']);

      container.dispose();
    });

    test('dispose clears buffers', () async {
      final container = HoneycombContainer();
      final effect = Effect<int>(
        strategy: EffectStrategy.bufferN,
        bufferSize: 5,
      );

      container.emit(effect, 1);
      container.emit(effect, 2);

      container.dispose();
      // Should not throw
    });

    test('emitting after dispose is no-op', () async {
      final container = HoneycombContainer();
      final effect = Effect<String>(strategy: EffectStrategy.bufferN);

      container.dispose();

      // Should not throw
      container.emit(effect, 'ignored');
    });

    test('multiple listeners receive same event', () async {
      final container = HoneycombContainer();
      final effect = Effect<String>(strategy: EffectStrategy.drop);

      final r1 = <String>[];
      final r2 = <String>[];

      container.on(effect, r1.add);
      container.on(effect, r2.add);

      container.emit(effect, 'broadcast');
      await Future.delayed(Duration.zero);

      expect(r1, ['broadcast']);
      expect(r2, ['broadcast']);

      container.dispose();
    });

    test('cancelling subscription stops events', () async {
      final container = HoneycombContainer();
      final effect = Effect<int>(strategy: EffectStrategy.drop);

      final received = <int>[];
      final sub = container.on(effect, received.add);

      container.emit(effect, 1);
      await Future.delayed(Duration.zero);

      sub.cancel();

      container.emit(effect, 2);
      await Future.delayed(Duration.zero);

      expect(received, [1]);

      container.dispose();
    });
  });

  group('FlutterBinding edge cases', () {
    test('reassemble does not throw', () {
      final container = HoneycombContainer();
      container.invalidateAllComputed();
      container.dispose();
    });
  });
}
