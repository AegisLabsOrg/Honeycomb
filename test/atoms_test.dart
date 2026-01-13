import 'package:flutter_test/flutter_test.dart';
import 'package:honeycomb/honeycomb.dart';

void main() {
  group('StateRef', () {
    test('has initial value and disposePolicy', () {
      final ref = StateRef(42);
      expect(ref.initialValue, 42);
      expect(ref.disposePolicy, DisposePolicy.keepAlive);

      final autoRef = StateRef(0, disposePolicy: DisposePolicy.autoDispose);
      expect(autoRef.disposePolicy, DisposePolicy.autoDispose);
    });

    test('overrideWith creates Override', () {
      final ref = StateRef(0);
      final override = ref.overrideWith(100);

      expect(override.atom, ref);
      expect(override.value, 100);
    });

    test('key is self', () {
      final ref = StateRef(0);
      expect(ref.key, ref);
    });

    test('accept calls visitStateRef', () {
      final ref = StateRef(0);
      final visitor = _TestVisitor();
      ref.accept(visitor);
      expect(visitor.visitedStateRef, isTrue);
    });
  });

  group('Computed', () {
    test('has computeFn and disposePolicy', () {
      final computed = Computed((watch) => 42);
      expect(computed.disposePolicy, DisposePolicy.keepAlive);
    });

    test('static async creates AsyncComputed', () {
      final async = Computed.async((watch) async => 42);
      expect(async, isA<AsyncComputed<int>>());
    });

    test('static eager creates EagerComputed', () {
      final eager = Computed.eager((watch) => 42);
      expect(eager, isA<EagerComputed<int>>());
    });

    test('key is self', () {
      final computed = Computed((watch) => 0);
      expect(computed.key, computed);
    });

    test('accept calls visitComputed', () {
      final computed = Computed((watch) => 0);
      final visitor = _TestVisitor();
      computed.accept(visitor);
      expect(visitor.visitedComputed, isTrue);
    });
  });

  group('AsyncComputed', () {
    test('has computeFn and disposePolicy', () {
      final async = AsyncComputed((watch) async => 42);
      expect(async.disposePolicy, DisposePolicy.keepAlive);
    });

    test('key is self', () {
      final async = AsyncComputed((watch) async => 0);
      expect(async.key, async);
    });

    test('accept calls visitAsyncComputed', () {
      final async = AsyncComputed((watch) async => 0);
      final visitor = _TestVisitor();
      async.accept(visitor);
      expect(visitor.visitedAsyncComputed, isTrue);
    });
  });

  group('EagerComputed', () {
    test('has computeFn and disposePolicy', () {
      final eager = EagerComputed((watch) => 42);
      expect(eager.disposePolicy, DisposePolicy.keepAlive);
    });

    test('key is self', () {
      final eager = EagerComputed((watch) => 0);
      expect(eager.key, eager);
    });

    test('accept calls visitEagerComputed', () {
      final eager = EagerComputed((watch) => 0);
      final visitor = _TestVisitor();
      eager.accept(visitor);
      expect(visitor.visitedEagerComputed, isTrue);
    });
  });

  group('SafeComputed', () {
    test('has computeFn and disposePolicy', () {
      final safe = SafeComputed((watch) => 42);
      expect(safe.disposePolicy, DisposePolicy.keepAlive);
    });

    test('key is self', () {
      final safe = SafeComputed((watch) => 0);
      expect(safe.key, safe);
    });

    test('accept calls visitSafeComputed', () {
      final safe = SafeComputed((watch) => 0);
      final visitor = _TestVisitor();
      safe.accept(visitor);
      expect(visitor.visitedSafeComputed, isTrue);
    });
  });

  group('Effect', () {
    test('has default strategy drop', () {
      final effect = Effect<String>();
      expect(effect.strategy, EffectStrategy.drop);
      expect(effect.bufferSize, 10);
      expect(effect.ttlDuration, const Duration(seconds: 30));
    });

    test('supports custom name and strategy', () {
      final effect = Effect<String>(
        name: 'toast',
        strategy: EffectStrategy.bufferN,
        bufferSize: 5,
      );
      expect(effect.name, 'toast');
      expect(effect.strategy, EffectStrategy.bufferN);
      expect(effect.bufferSize, 5);
    });

    test('key is self', () {
      final effect = Effect<String>();
      expect(effect.key, effect);
    });

    test('accept calls visitEffect', () {
      final effect = Effect<String>();
      final visitor = _TestVisitor();
      effect.accept(visitor);
      expect(visitor.visitedEffect, isTrue);
    });
  });

  group('Result', () {
    group('ResultSuccess', () {
      test('properties', () {
        const result = ResultSuccess(42);
        expect(result.value, 42);
        expect(result.valueOrNull, 42);
        expect(result.isSuccess, isTrue);
        expect(result.isFailure, isFalse);
        expect(result.requireValue, 42);
        expect(result.getOrElse(0), 42);
      });

      test('when calls success', () {
        const result = Result.success(42);
        final value = result.when(
          success: (v) => 'success: $v',
          failure: (e, st) => 'failure',
        );
        expect(value, 'success: 42');
      });

      test('map transforms value', () {
        const result = Result.success(21);
        final mapped = result.map((v) => v * 2);
        expect(mapped, isA<ResultSuccess<int>>());
        expect((mapped as ResultSuccess).value, 42);
      });

      test('map catches exceptions', () {
        const result = Result.success(21);
        final mapped = result.map<int>((v) => throw Exception('oops'));
        expect(mapped, isA<ResultFailure<int>>());
      });
    });

    group('ResultFailure', () {
      test('properties', () {
        final result = ResultFailure<int>(Exception('error'), StackTrace.empty);
        expect(result.valueOrNull, isNull);
        expect(result.isSuccess, isFalse);
        expect(result.isFailure, isTrue);
        expect(result.getOrElse(99), 99);
      });

      test('requireValue throws', () {
        final result = ResultFailure<int>(Exception('error'), StackTrace.empty);
        expect(() => result.requireValue, throwsException);
      });

      test('when calls failure', () {
        final result = Result<int>.failure(
          Exception('error'),
          StackTrace.empty,
        );
        final value = result.when(
          success: (v) => 'success',
          failure: (e, st) => 'failure: $e',
        );
        expect(value, contains('failure'));
      });

      test('map preserves failure', () {
        final result = Result<int>.failure(
          Exception('error'),
          StackTrace.empty,
        );
        final mapped = result.map((v) => v * 2);
        expect(mapped, isA<ResultFailure<int>>());
      });
    });
  });

  group('AsyncValue', () {
    group('AsyncLoading', () {
      test('properties', () {
        const loading = AsyncLoading<int>();
        expect(loading.valueOrNull, isNull);

        const withPrevious = AsyncLoading<int>(previous: 42);
        expect(withPrevious.valueOrNull, 42);
        expect(withPrevious.previous, 42);
      });

      test('when calls loading', () {
        const loading = AsyncValue<int>.loading();
        final result = loading.when(
          loading: () => 'loading',
          data: (d) => 'data',
          error: (e, st) => 'error',
        );
        expect(result, 'loading');
      });
    });

    group('AsyncData', () {
      test('properties', () {
        const data = AsyncData(42);
        expect(data.value, 42);
        expect(data.valueOrNull, 42);
      });

      test('when calls data', () {
        const data = AsyncValue.data(42);
        final result = data.when(
          loading: () => 'loading',
          data: (d) => 'data: $d',
          error: (e, st) => 'error',
        );
        expect(result, 'data: 42');
      });
    });

    group('AsyncError', () {
      test('properties', () {
        final error = AsyncError<int>(Exception('error'), StackTrace.empty);
        expect(error.error, isA<Exception>());
        expect(error.valueOrNull, isNull);
      });

      test('when calls error', () {
        final error = AsyncValue<int>.error(
          Exception('oops'),
          StackTrace.empty,
        );
        final result = error.when(
          loading: () => 'loading',
          data: (d) => 'data',
          error: (e, st) => 'error: $e',
        );
        expect(result, contains('error'));
      });
    });
  });

  group('Override', () {
    test('stores atom and value', () {
      final ref = StateRef(0);
      final override = Override(ref, 100);
      expect(override.atom, ref);
      expect(override.value, 100);
    });
  });

  group('DisposePolicy enum', () {
    test('has all values', () {
      expect(DisposePolicy.values, contains(DisposePolicy.keepAlive));
      expect(DisposePolicy.values, contains(DisposePolicy.autoDispose));
      expect(DisposePolicy.values, contains(DisposePolicy.delayed));
    });
  });

  group('EffectStrategy enum', () {
    test('has all values', () {
      expect(EffectStrategy.values, contains(EffectStrategy.drop));
      expect(EffectStrategy.values, contains(EffectStrategy.bufferN));
      expect(EffectStrategy.values, contains(EffectStrategy.ttl));
    });
  });

  group('AtomSelect extension', () {
    test('select creates derived Computed', () {
      final container = HoneycombContainer();
      final user = StateRef({'name': 'Alice', 'age': 30});
      final name = user.select((u) => u['name'] as String);

      expect(container.read(name), 'Alice');

      container.write(user, {'name': 'Bob', 'age': 30});
      expect(container.read(name), 'Bob');

      container.dispose();
    });

    test('select with equals uses custom comparator', () {
      final container = HoneycombContainer();
      final data = StateRef([1, 2, 3]);

      int computeCount = 0;
      final sum = data.select((list) {
        computeCount++;
        return list.reduce((a, b) => a + b);
      }, equals: (a, b) => a == b);

      expect(container.read(sum), 6);
      expect(computeCount, 1);

      // Same sum, different list
      container.write(data, [2, 2, 2]);
      container.read(sum);
      // Should recompute but return cached because equals matches
      expect(computeCount, 2);

      container.dispose();
    });

    test('selectMany creates multi-field Computed', () {
      final container = HoneycombContainer();
      final user = StateRef({'name': 'Alice', 'avatar': 'a.png'});

      final fields = user.selectMany([(u) => u['name'], (u) => u['avatar']]);

      expect(container.read(fields), ['Alice', 'a.png']);

      container.dispose();
    });

    test('where filters by predicate', () {
      final container = HoneycombContainer();
      final value = StateRef(10);
      final filtered = value.where((v) => v > 5);

      expect(container.read(filtered), 10);

      container.write(value, 3);
      expect(container.read(filtered), isNull);

      container.write(value, 8);
      expect(container.read(filtered), 8);

      container.dispose();
    });
  });
}

class _TestVisitor implements AtomVisitor<void> {
  bool visitedStateRef = false;
  bool visitedComputed = false;
  bool visitedAsyncComputed = false;
  bool visitedEagerComputed = false;
  bool visitedSafeComputed = false;
  bool visitedEffect = false;

  @override
  void visitStateRef<T>(StateRef<T> atom) => visitedStateRef = true;

  @override
  void visitComputed<T>(Computed<T> atom) => visitedComputed = true;

  @override
  void visitAsyncComputed<T>(AsyncComputed<T> atom) =>
      visitedAsyncComputed = true;

  @override
  void visitEagerComputed<T>(EagerComputed<T> atom) =>
      visitedEagerComputed = true;

  @override
  void visitSafeComputed<T>(SafeComputed<T> atom) => visitedSafeComputed = true;

  @override
  void visitEffect<T>(Effect<T> atom) => visitedEffect = true;
}
