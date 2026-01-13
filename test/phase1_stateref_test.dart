import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_honeycomb/honeycomb.dart';

void main() {
  group('StateRef & HoneycombContainer', () {
    test('StateRef has initial value', () {
      final container = HoneycombContainer();
      final counter = StateRef(0);

      expect(container.read(counter), 0);
    });

    test('Write updates value', () {
      final container = HoneycombContainer();
      final counter = StateRef(0);

      container.write(counter, 1);
      expect(container.read(counter), 1);
    });

    test('Listeners overlap', () {
      final container = HoneycombContainer();
      final counter = StateRef(0);
      int notifyCount = 0;

      final dispose = container.subscribe(counter, () {
        notifyCount++;
      });

      container.write(counter, 1);
      expect(notifyCount, 1);

      container.write(counter, 1); // Same value, should not notify
      expect(notifyCount, 1);

      container.write(counter, 2);
      expect(notifyCount, 2);

      dispose();
      container.write(counter, 3);
      expect(notifyCount, 2); // Should not notify after dispose
    });
  });

  group('Scope & Overrides', () {
    final userToken = StateRef<String?>("guest");

    test('Child container inherits parent state', () {
      final root = HoneycombContainer();
      final child = HoneycombContainer.scoped(root);

      expect(child.read(userToken), "guest");

      // Modifying in child (which delegates to root) modifies for everyone
      child.write(userToken, "admin");
      expect(root.read(userToken), "admin");
    });

    test('Child container overrides state', () {
      final root = HoneycombContainer();
      final child = HoneycombContainer.scoped(
        root,
        overrides: [userToken.overrideWith("mock_user")],
      );

      // Root is unchanged
      expect(root.read(userToken), "guest");
      // Child has override
      expect(child.read(userToken), "mock_user");

      // Modifying child only modifies child's local state
      child.write(userToken, "mock_admin");
      expect(child.read(userToken), "mock_admin");
      expect(root.read(userToken), "guest");
    });
  });
}
