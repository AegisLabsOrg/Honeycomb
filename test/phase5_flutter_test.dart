import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_honeycomb/honeycomb.dart';

void main() {
  group('Honeycomb Flutter Bindings', () {
    testWidgets('HoneycombConsumer updates when StateRef changes', (
      tester,
    ) async {
      final counter = StateRef(0);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: HoneycombConsumer(
              builder: (context, ref, _) {
                final count = ref.watch(counter);
                return Text('Count: $count');
              },
            ),
          ),
        ),
      );

      expect(find.text('Count: 0'), findsOneWidget);

      final container = HoneycombScope.readOf(
        tester.element(find.byType(HoneycombConsumer)),
      );
      container.write(counter, 1);

      await tester.pump();
      expect(find.text('Count: 1'), findsOneWidget);
    });

    testWidgets('Scope overrides work', (tester) async {
      final counter = StateRef(10);
      final overrideVal = 99;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            overrides: [counter.overrideWith(overrideVal)],
            child: HoneycombConsumer(
              builder: (context, ref, _) {
                final count = ref.watch(counter);
                return Text('$count');
              },
            ),
          ),
        ),
      );

      expect(find.text('99'), findsOneWidget);
    });

    testWidgets('Nested Scopes isolation', (tester) async {
      final score = StateRef(0);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HoneycombScope(
            child: Column(
              children: [
                HoneycombConsumer(
                  builder: (ctx, ref, _) => Text('Root: ${ref.watch(score)}'),
                ),
                HoneycombScope(
                  overrides: [score.overrideWith(100)],
                  child: HoneycombConsumer(
                    builder: (ctx, ref, _) =>
                        Text('Nested: ${ref.watch(score)}'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Root: 0'), findsOneWidget);
      expect(find.text('Nested: 100'), findsOneWidget);

      // Write to root
      final rootCtx = tester.element(find.text('Root: 0'));
      rootCtx.read(score); // Just checking ext
      rootCtx.emit(Effect(name: 'noop'), null); // Just checking ext

      HoneycombScope.readOf(rootCtx).write(score, 1);

      await tester.pump();

      expect(find.text('Root: 1'), findsOneWidget);
      expect(find.text('Nested: 100'), findsOneWidget); // Isolate
    });

    testWidgets('Context Extension read', (tester) async {
      final ref = StateRef('hello');
      await tester.pumpWidget(
        HoneycombScope(
          child: Builder(
            builder: (context) {
              final val = context.read(ref);
              return Text(val, textDirection: TextDirection.ltr);
            },
          ),
        ),
      );
      expect(find.text('hello'), findsOneWidget);
    });
  });
}
