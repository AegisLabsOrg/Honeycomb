import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_honeycomb/honeycomb.dart';

void main() {
  group('AsyncComputed', () {
    test('Initial state is loading', () {
      final container = HoneycombContainer();
      final asyncAtom = Computed.async((watch) async {
        return 42;
      });

      final value = container.read(asyncAtom);
      expect(value, isA<AsyncLoading<int>>());
    });

    test('Resolves to data', () async {
      final container = HoneycombContainer();
      final completer = Future<int>.delayed(
        const Duration(milliseconds: 50),
        () => 100,
      );
      final asyncAtom = Computed.async((watch) => completer);

      // Listen to trigger computation
      bool notified = false;
      container.subscribe(asyncAtom, () => notified = true);

      // Initial read triggers start
      var val = container.read(asyncAtom);
      expect(val, isA<AsyncLoading>());

      await Future.delayed(const Duration(milliseconds: 100));

      val = container.read(asyncAtom);
      expect(val, isA<AsyncData<int>>());
      expect((val as AsyncData).value, 100);
      expect(notified, true);
    });

    test('Handles dependency changes', () async {
      final container = HoneycombContainer();
      final id = StateRef(1);
      final derived = Computed.async((watch) async {
        final currentId = watch(id);
        await Future.delayed(const Duration(milliseconds: 10)); // Simulate net
        return 'Data $currentId';
      });

      container.subscribe(derived, () {}); // activate

      await Future.delayed(const Duration(milliseconds: 50));
      expect(container.read(derived), isA<AsyncData>());
      expect((container.read(derived) as AsyncData).value, 'Data 1');

      // Change dependency
      container.write(id, 2);

      // Immediately changes to Loading (preserving previous data logic if implemented, or just loading)
      // In current implementation: AsyncLoading(previous: 'Data 1')
      final loadingStat = container.read(derived);
      expect(loadingStat, isA<AsyncLoading>());
      expect((loadingStat as AsyncLoading).previous, 'Data 1');

      // Wait for completion
      await Future.delayed(const Duration(milliseconds: 50));
      expect((container.read(derived) as AsyncData).value, 'Data 2');
    });

    test('Handles errors', () async {
      final container = HoneycombContainer();
      final asyncError = Computed.async((watch) async {
        throw Exception('Boom');
      });

      container.subscribe(asyncError, () {});

      await Future.delayed(const Duration(milliseconds: 10));

      final val = container.read(asyncError);
      expect(val, isA<AsyncError>());
      expect((val as AsyncError).error, isA<Exception>());
    });
  });
}
