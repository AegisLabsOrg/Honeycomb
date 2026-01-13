import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honeycomb/honeycomb.dart';
import 'package:honeycomb/src/compute_node.dart';

void main() {
  group('Improvements', () {
    group('Circular Dependency Detection', () {
      test('Detects self-referencing Computed', () {
        final container = HoneycombContainer();

        late Computed<int> selfRef;
        selfRef = Computed((watch) => watch(selfRef) + 1);

        expect(
          () => container.read(selfRef),
          throwsA(isA<CircularDependencyError>()),
        );
      });

      test('Detects indirect circular dependency (A -> B -> A)', () {
        final container = HoneycombContainer();

        late Computed<int> a;
        late Computed<int> b;

        a = Computed((watch) => watch(b) + 1);
        b = Computed((watch) => watch(a) + 1);

        expect(
          () => container.read(a),
          throwsA(isA<CircularDependencyError>()),
        );
      });
    });

    group('Batch Updates', () {
      test('Multiple writes trigger single notification', () {
        final container = HoneycombContainer();
        final a = StateRef(0);
        final b = StateRef(0);

        int notifyCount = 0;
        container.subscribe(a, () => notifyCount++);
        container.subscribe(b, () => notifyCount++);

        container.batch(() {
          container.write(a, 1);
          container.write(a, 2);
          container.write(b, 10);
        });

        // 每个 node 只通知一次
        expect(notifyCount, 2);
      });

      test('Computed sees final values after batch', () {
        final container = HoneycombContainer();
        final a = StateRef(0);
        final b = StateRef(0);
        final sum = Computed((watch) => watch(a) + watch(b));

        container.batch(() {
          container.write(a, 5);
          container.write(b, 10);
        });

        expect(container.read(sum), 15);
      });

      test('Nested batch works correctly', () {
        final container = HoneycombContainer();
        final x = StateRef(0);

        int count = 0;
        container.subscribe(x, () => count++);

        container.batch(() {
          container.write(x, 1);
          container.batch(() {
            container.write(x, 2);
          });
          container.write(x, 3);
        });

        // 嵌套 batch 时，内层不会提前 flush
        expect(count, 1);
        expect(container.read(x), 3);
      });
    });

    group('HoneycombListener', () {
      testWidgets('Listens to Effect events', (tester) async {
        final navEffect = Effect<String>(name: 'nav');
        final received = <String>[];

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: HoneycombScope(
              child: HoneycombListener<String>(
                effect: navEffect,
                onEvent: (ctx, payload) => received.add(payload),
                child: Builder(
                  builder: (context) {
                    return GestureDetector(
                      onTap: () => context.emit(navEffect, '/home'),
                      child: const Text('Tap'),
                    );
                  },
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Tap'));
        await tester.pump();

        expect(received, ['/home']);
      });
    });

    group('Context batch Extension', () {
      testWidgets('context.batch works', (tester) async {
        final a = StateRef(0);
        final b = StateRef(0);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: HoneycombScope(
              child: Builder(
                builder: (context) {
                  return GestureDetector(
                    onTap: () {
                      context.batch(() {
                        HoneycombScope.readOf(context).write(a, 1);
                        HoneycombScope.readOf(context).write(b, 2);
                      });
                    },
                    child: HoneycombConsumer(
                      builder: (ctx, ref, _) {
                        return Text('${ref.watch(a)}-${ref.watch(b)}');
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        );

        expect(find.text('0-0'), findsOneWidget);

        await tester.tap(find.byType(GestureDetector));
        await tester.pump();

        expect(find.text('1-2'), findsOneWidget);
      });
    });
  });
}
