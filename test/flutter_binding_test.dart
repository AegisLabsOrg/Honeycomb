import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_honeycomb/honeycomb.dart';

void main() {
  group('HoneycombScope', () {
    testWidgets('of throws when no scope found', (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            // This should throw
            return const Text('test', textDirection: TextDirection.ltr);
          },
        ),
      );

      // Try to access scope outside of scope
      final context = tester.element(find.text('test'));
      expect(() => HoneycombScope.of(context), throwsStateError);
    });

    testWidgets('readOf throws when no scope found', (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            return const Text('test', textDirection: TextDirection.ltr);
          },
        ),
      );

      final context = tester.element(find.text('test'));
      expect(() => HoneycombScope.readOf(context), throwsStateError);
    });

    testWidgets('creates default container when not provided', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: Builder(
              builder: (context) {
                final container = HoneycombScope.of(context);
                expect(container, isNotNull);
                return const Text('ok');
              },
            ),
          ),
        ),
      );

      expect(find.text('ok'), findsOneWidget);
    });

    testWidgets('uses provided container', (tester) async {
      final container = HoneycombContainer();
      final ref = StateRef(42);
      container.write(ref, 100);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            container: container,
            child: HoneycombConsumer(
              builder: (context, widgetRef, _) {
                return Text('${widgetRef.read(ref)}');
              },
            ),
          ),
        ),
      );

      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('updateShouldNotify returns false for same container', (
      tester,
    ) async {
      final container = HoneycombContainer();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            container: container,
            child: const Text('test'),
          ),
        ),
      );

      // Rebuild with same container
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            container: container,
            child: const Text('test'),
          ),
        ),
      );

      // Should not throw or cause issues
      expect(find.text('test'), findsOneWidget);
    });
  });

  group('HoneycombConsumer', () {
    testWidgets('child is passed to builder', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: HoneycombConsumer(
              builder: (context, ref, child) {
                return Column(children: [child!, const Text('from builder')]);
              },
              child: const Text('static child'),
            ),
          ),
        ),
      );

      expect(find.text('static child'), findsOneWidget);
      expect(find.text('from builder'), findsOneWidget);
    });

    testWidgets('correctly unsubscribes from removed dependencies', (
      tester,
    ) async {
      final showB = StateRef(true);
      final a = StateRef('A');
      final b = StateRef('B');

      int buildCount = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: HoneycombConsumer(
              builder: (context, ref, _) {
                buildCount++;
                final show = ref.watch(showB);
                final aVal = ref.watch(a);
                if (show) {
                  final bVal = ref.watch(b);
                  return Text('$aVal-$bVal');
                }
                return Text(aVal);
              },
            ),
          ),
        ),
      );

      expect(find.text('A-B'), findsOneWidget);
      expect(buildCount, 1);

      // Hide B
      final container = HoneycombScope.readOf(
        tester.element(find.byType(HoneycombConsumer)),
      );
      container.write(showB, false);
      await tester.pump();

      expect(find.text('A'), findsOneWidget);
      expect(buildCount, 2);

      // Now changing B should NOT trigger rebuild
      container.write(b, 'NEW_B');
      await tester.pump();

      expect(buildCount, 2); // Should still be 2
    });

    testWidgets('read does not subscribe', (tester) async {
      final counter = StateRef(0);
      int buildCount = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: HoneycombConsumer(
              builder: (context, ref, _) {
                buildCount++;
                // Using read instead of watch
                final count = ref.read(counter);
                return Text('$count');
              },
            ),
          ),
        ),
      );

      expect(find.text('0'), findsOneWidget);
      expect(buildCount, 1);

      final container = HoneycombScope.readOf(
        tester.element(find.byType(HoneycombConsumer)),
      );
      container.write(counter, 999);
      await tester.pump();

      // Should NOT rebuild because we used read, not watch
      expect(buildCount, 1);
    });

    testWidgets('emit sends effect', (tester) async {
      final toast = Effect<String>();
      final received = <String>[];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: Builder(
              builder: (context) {
                final container = HoneycombScope.of(context);
                container.on(toast, received.add);
                return HoneycombConsumer(
                  builder: (ctx, ref, _) {
                    return GestureDetector(
                      onTap: () => ref.emit(toast, 'Hello!'),
                      child: const Text('Tap me'),
                    );
                  },
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap me'));
      await tester.pump();

      expect(received, contains('Hello!'));
    });
  });

  group('HoneycombListener', () {
    testWidgets('receives events', (tester) async {
      final toast = Effect<String>();
      final received = <String>[];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: HoneycombListener<String>(
              effect: toast,
              onEvent: (context, payload) {
                received.add(payload);
              },
              child: const Text('child'),
            ),
          ),
        ),
      );

      final container = HoneycombScope.readOf(
        tester.element(find.byType(HoneycombListener<String>)),
      );

      container.emit(toast, 'event1');
      await tester.pump();
      expect(received, ['event1']);

      container.emit(toast, 'event2');
      await tester.pump();
      expect(received, ['event1', 'event2']);
    });

    testWidgets('resubscribes when effect changes', (tester) async {
      final effect1 = Effect<String>(name: 'e1');
      final effect2 = Effect<String>(name: 'e2');
      final received = <String>[];

      Effect<String> currentEffect = effect1;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: StatefulBuilder(
              builder: (context, setState) {
                return HoneycombListener<String>(
                  effect: currentEffect,
                  onEvent: (context, payload) {
                    received.add(payload);
                  },
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        currentEffect = effect2;
                      });
                    },
                    child: const Text('switch'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      final container = HoneycombScope.readOf(
        tester.element(find.byType(HoneycombListener<String>)),
      );

      container.emit(effect1, 'from1');
      await tester.pump();
      expect(received, ['from1']);

      // Switch effect
      await tester.tap(find.text('switch'));
      await tester.pump();

      // Old effect should not be received
      container.emit(effect1, 'from1_again');
      await tester.pump();
      expect(received, ['from1']); // No change

      // New effect should be received
      container.emit(effect2, 'from2');
      await tester.pump();
      expect(received, ['from1', 'from2']);
    });

    testWidgets('child is rendered', (tester) async {
      final effect = Effect<int>();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: HoneycombListener<int>(
              effect: effect,
              onEvent: (_, __) {},
              child: const Text('Hello'),
            ),
          ),
        ),
      );

      expect(find.text('Hello'), findsOneWidget);
    });
  });

  group('Context Extensions', () {
    testWidgets('read extension works', (tester) async {
      final ref = StateRef('test');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: Builder(
              builder: (context) {
                final value = context.read(ref);
                return Text(value);
              },
            ),
          ),
        ),
      );

      expect(find.text('test'), findsOneWidget);
    });

    testWidgets('emit extension works', (tester) async {
      final effect = Effect<String>();
      final received = <String>[];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: Builder(
              builder: (context) {
                HoneycombScope.of(context).on(effect, received.add);
                return GestureDetector(
                  onTap: () => context.emit(effect, 'emitted'),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('tap'));
      await tester.pump();

      expect(received, ['emitted']);
    });

    testWidgets('batch extension works', (tester) async {
      final a = StateRef(0);
      final b = StateRef(0);
      int buildCount = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: HoneycombConsumer(
              builder: (context, ref, _) {
                buildCount++;
                return Text('${ref.watch(a)}-${ref.watch(b)}');
              },
            ),
          ),
        ),
      );

      expect(buildCount, 1);

      final context = tester.element(find.byType(HoneycombConsumer));
      context.batch(() {
        HoneycombScope.readOf(context).write(a, 1);
        HoneycombScope.readOf(context).write(b, 2);
      });

      await tester.pump();

      // Should only rebuild once due to batching
      expect(buildCount, 2);
      expect(find.text('1-2'), findsOneWidget);
    });
  });

  group('Computed with Flutter', () {
    testWidgets('Consumer updates when Computed changes', (tester) async {
      final a = StateRef(1);
      final b = StateRef(2);
      final sum = Computed((watch) => watch(a) + watch(b));

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: HoneycombConsumer(
              builder: (context, ref, _) {
                return Text('${ref.watch(sum)}');
              },
            ),
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);

      final container = HoneycombScope.readOf(
        tester.element(find.byType(HoneycombConsumer)),
      );
      container.write(a, 10);
      await tester.pump();

      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('AsyncComputed shows loading/data states', (tester) async {
      final userId = StateRef(1);
      final user = Computed.async((watch) async {
        final id = watch(userId);
        await Future.delayed(const Duration(milliseconds: 100));
        return 'User $id';
      });

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: HoneycombConsumer(
              builder: (context, ref, _) {
                final result = ref.watch(user);
                return result.when(
                  loading: () => const Text('loading'),
                  data: (u) => Text(u),
                  error: (e, _) => Text('error: $e'),
                );
              },
            ),
          ),
        ),
      );

      // Initially loading
      expect(find.text('loading'), findsOneWidget);

      // Wait for async to complete
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('User 1'), findsOneWidget);
    });

    testWidgets('SafeComputed shows success/failure', (tester) async {
      final input = StateRef(10);
      final validated = SafeComputed((watch) {
        final val = watch(input);
        if (val < 0) {
          throw ArgumentError('Must be positive');
        }
        return val * 2;
      });

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: HoneycombConsumer(
              builder: (context, ref, _) {
                final result = ref.watch(validated);
                return result.when(
                  success: (v) => Text('value: $v'),
                  failure: (e, _) => Text('error: $e'),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('value: 20'), findsOneWidget);

      final container = HoneycombScope.readOf(
        tester.element(find.byType(HoneycombConsumer)),
      );
      container.write(input, -5);
      await tester.pump();

      expect(find.textContaining('error:'), findsOneWidget);
    });
  });
}
