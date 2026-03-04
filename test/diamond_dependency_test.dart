import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_honeycomb/honeycomb.dart';

void main() {
  test('Diamond dependency only evaluates terminal node once per phase', () {
    final container = HoneycombContainer();

    final stateA = StateRef(0);

    int computeBCount = 0;
    final computedB = Computed((watch) {
      computeBCount++;
      return watch(stateA) + 1;
    });

    int computeCCount = 0;
    final computedC = Computed((watch) {
      computeCCount++;
      return watch(stateA) * 2;
    });

    int computeDCount = 0;
    final computedD = Computed((watch) {
      computeDCount++;
      return watch(computedB) + watch(computedC);
    });

    // 1st calculation
    expect(container.read(computedD), 1); // B=1, C=0 => D=1
    expect(computeBCount, 1);
    expect(computeCCount, 1);
    expect(computeDCount, 1);

    // Change A from 0 to 1
    // Without push-pull and lazy eval, B updates -> D updates (D calculates 2+0=2, and D reads C).
    // And later C updates -> D updates again.
    container.write(stateA, 1);

    // Read D again to trigger calculation
    expect(container.read(computedD), 4); // B=2, C=2 => D=4
    expect(computeBCount, 2);
    expect(computeCCount, 2);

    // IF the diamond problem was NOT solved, computeDCount would be 3 here
    // IF properly solved, computeDCount should be 2.
    expect(computeDCount, 2);
  });
}
