import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_honeycomb/honeycomb.dart';

void main() {
  group('Honeycomb Effect Tests', () {
    test('Basic emit and listen', () async {
      final container = HoneycombContainer();
      final myEffect = Effect<String>(name: 'nav');

      String? received;
      container.on(myEffect, (payload) {
        received = payload;
      });

      container.emit(myEffect, '/home');

      // Wait for stream event loop
      await Future.delayed(Duration.zero);

      expect(received, '/home');
    });

    test('Multiple listeners (Broadcast)', () async {
      final container = HoneycombContainer();
      final logEffect = Effect<String>(name: 'log');

      final logs1 = <String>[];
      final logs2 = <String>[];

      container.on(logEffect, (msg) => logs1.add(msg));
      container.on(logEffect, (msg) => logs2.add(msg));

      container.emit(logEffect, 'hello');

      await Future.delayed(Duration.zero);

      expect(logs1, ['hello']);
      expect(logs2, ['hello']);
    });

    test('Scope bubbling: Child emits, Parent listens', () async {
      final parent = HoneycombContainer();
      final child = HoneycombContainer.scoped(parent);

      final alertEffect = Effect<String>(name: 'alert');

      String? parentReceived;
      parent.on(alertEffect, (msg) {
        parentReceived = msg;
      });

      // Emit from child
      child.emit(alertEffect, 'Boom!');

      await Future.delayed(Duration.zero);

      expect(parentReceived, 'Boom!');
    });

    test('Dispose behavior', () async {
      final container = HoneycombContainer();
      final myEffect = Effect<int>();

      bool received = false;
      container.on(myEffect, (_) => received = true);

      container.dispose();

      // Emit after dispose should be ignored (safe)
      container.emit(myEffect, 123);

      await Future.delayed(Duration.zero);
      expect(received, false);
    });
  });
}
