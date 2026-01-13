import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_honeycomb/honeycomb.dart';

void main() {
  group('Computed', () {
    test('Basic computed value', () {
      final container = HoneycombContainer();
      final count = StateRef(1);
      final doubleCount = Computed((watch) => watch(count) * 2);

      expect(container.read(doubleCount), 2);
    });

    test('Computed updates when dependency updates', () {
      final container = HoneycombContainer();
      final count = StateRef(1);
      final doubleCount = Computed((watch) => watch(count) * 2);

      expect(container.read(doubleCount), 2);

      container.write(count, 10);
      expect(container.read(doubleCount), 20);
    });

    // 链式依赖测试
    // A -> B -> C
    test('Chained computed', () {
      final container = HoneycombContainer();
      final count = StateRef(1);
      final doubleCount = Computed((watch) => watch(count) * 2);
      final tripleDouble = Computed((watch) => watch(doubleCount) * 3);

      expect(container.read(tripleDouble), 6); // 1 * 2 * 3

      container.write(count, 2);
      expect(container.read(tripleDouble), 12); // 2 * 2 * 3
    });

    // Lazy 且 Cache 命中测试
    test('Lazy & Cache Mechanism', () {
      final container = HoneycombContainer();
      final count = StateRef(0);

      int computeCallCount = 0;
      final expensive = Computed((watch) {
        computeCallCount++;
        return watch(count) * 10;
      });

      // 1. Initial read triggers compute
      expect(container.read(expensive), 0);
      expect(computeCallCount, 1);

      // 2. Second read with same dependencies should use cache
      expect(container.read(expensive), 0);
      expect(computeCallCount, 1); // No new computation

      // 3. Update dependency
      container.write(count, 1);
      // Still lazy: not computed yet
      expect(computeCallCount, 1);

      // 4. Read triggers recompute
      expect(container.read(expensive), 10);
      expect(computeCallCount, 2);
    });

    // 动态依赖图测试 (if 分支)
    test('Dynamic dependency graph', () {
      final container = HoneycombContainer();
      final userType = StateRef('guest');
      final guestMsg = StateRef('Hello Guest');
      final adminMsg = StateRef('Hello Admin');

      int computeCount = 0;
      final message = Computed((watch) {
        computeCount++;
        if (watch(userType) == 'guest') {
          return watch(guestMsg);
        } else {
          return watch(adminMsg);
        }
      });

      // 初始：guest
      expect(container.read(message), 'Hello Guest');
      expect(computeCount, 1);

      // 修改 adminMsg，当前依赖 guestMsg，所以不应重算
      container.write(adminMsg, 'New Admin');
      // 仍然读取，确保没有变脏
      expect(container.read(message), 'Hello Guest');
      expect(computeCount, 1);

      // 切换到 admin
      container.write(userType, 'admin');
      expect(container.read(message), 'New Admin');
      expect(computeCount, 2);

      // 现在修改 guestMsg，应该不影响（因为已经在 else 分支了）
      container.write(guestMsg, 'New Guest');
      expect(container.read(message), 'New Admin');
      expect(computeCount, 2);
    });
  });
}
