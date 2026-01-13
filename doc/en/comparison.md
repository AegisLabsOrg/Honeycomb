# Comparison with Other Libraries

A comparative analysis of Honeycomb and other mainstream Flutter state management solutions.

---

## Contents

1. [Overview](#overview)
2. [vs Provider](#vs-provider)
3. [vs Riverpod](#vs-riverpod)
4. [vs BLoC](#vs-bloc)
5. [vs GetX](#vs-getx)
6. [Selection Advice](#selection-advice)

---

## Overview

| Feature | Honeycomb | Provider | Riverpod | BLoC |
|------|-----------|----------|----------|------|
| **State/Effect Separation** | ✅ Native Support | ❌ | ❌ | ⚠️ Manual |
| **Auto Dependency Tracking** | ✅ | ❌ Manual | ✅ | ❌ |
| **Type Safety** | ✅ | ⚠️ Runtime | ✅ Compile-time | ✅ |
| **Testability** | ✅ | ⚠️ | ✅ | ✅ |
| **UI-independent Core** | ✅ | ❌ | ✅ | ✅ |
| **Async Native Support** | ✅ AsyncValue | ⚠️ | ✅ AsyncValue | ⚠️ |
| **Hot Reload Support** | ✅ | ✅ | ✅ | ✅ |
| **Learning Curve** | Medium | Low | Medium | High |
| **Boilerplate** | Minimal | Minimal | Medium | High |

---

## vs Provider

### Provider Overview

Provider is a wrapper around InheritedWidget and is the official Flutter recommendation for entry-level state management.

### Key Differences

#### 1. Dependency Tracking

```dart
// Provider: Manually declare dependencies
class Cart extends ChangeNotifier {
  final Catalog _catalog; // Must be manually passed
  
  Cart(this._catalog);
}

// Order matters
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => Catalog()),
    ChangeNotifierProxyProvider<Catalog, Cart>(
      create: (_) => Cart(null),
      update: (_, catalog, cart) => Cart(catalog),
    ),
  ],
)
```

```dart
// Honeycomb: Auto dependency tracking
final cartTotal = Computed((watch) {
  final catalog = watch(catalogState);
  final items = watch(cartItems);
  return items.fold(0.0, (sum, id) => sum + catalog.getPrice(id));
});

// Declaration order doesn't matter
HoneycombScope(
  child: MyApp(),
)
```

#### 2. State vs Effect

```dart
// Provider: No native Effect concept
// Usually managed via Streams or manually
class AuthNotifier extends ChangeNotifier {
  String? _error;
  
  Future<void> login() async {
    try {
      // ...
    } catch (e) {
      _error = e.toString(); // This is State, not Event
      notifyListeners();
    }
  }
}
```

```dart
// Honeycomb: Native Effect support
final authError = Effect<String>(strategy: EffectStrategy.drop);

Future<void> login(HoneycombContainer container) async {
  try {
    // ...
  } catch (e) {
    container.emit(authError, e.toString()); // One-time event
  }
}
```

#### 3. Testing

```dart
// Provider: Requires Widget environment
testWidgets('cart total', (tester) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [...],
      child: Consumer<Cart>(...),
    ),
  );
});
```

```dart
// Honeycomb: Pure Dart testing
test('cart total', () {
  final container = HoneycombContainer();
  container.write(cartItems, ['apple', 'banana']);
  expect(container.read(cartTotal), 5.0);
});
```

### When to choose Provider

- ✅ Team is new to state management.
- ✅ Small projects.
- ✅ Significant amount of existing Provider code.

### When to choose Honeycomb

- ✅ Need clear State/Effect separation.
- ✅ Complex derived state chains.
- ✅ Require pure Dart unit testing.

---

## vs Riverpod

### Riverpod Overview

Riverpod is a rewrite of Provider by its author, fixing most of Provider's flaws. It is fundamentally very similar to Honeycomb.

### Key Differences

#### 1. Design Philosophy

```dart
// Riverpod: Providers are singleton factories
final userProvider = FutureProvider<User>((ref) async {
  return await api.fetchUser();
});

// Honeycomb: Atoms are descriptors
final userProfile = AsyncComputed((watch) async {
  return await api.fetchUser();
});
```

Usage is very similar, but the core difference is:
- Riverpod's Provider is a "registration factory".
- Honeycomb's Atom is a "state descriptor".

#### 2. State vs Effect

```dart
// Riverpod: No native Effect support
// Documents suggest using ref.listen or AsyncNotifier

// Honeycomb: Native Effect
final toastEffect = Effect<String>(strategy: EffectStrategy.drop);

HoneycombListener(
  effects: [toastEffect],
  listener: (context, container) {
    // handle
  },
  child: ...,
)
```

#### 3. Family Provider

Riverpod's killer feature:

```dart
// Riverpod: Parameterized Providers
final userProvider = FutureProvider.family<User, int>((ref, userId) {
  return api.fetchUser(userId);
});

// Usage
ref.watch(userProvider(123));
ref.watch(userProvider(456)); // Different instances
```

```dart
// Honeycomb: Currently requires manual management
final _userCache = <int, AsyncComputed<User>>{};

AsyncComputed<User> userProvider(int userId) {
  return _userCache.putIfAbsent(userId, () {
    return AsyncComputed((watch) => api.fetchUser(userId));
  });
}

// Usage
ref.watch(userProvider(123));
```

> ⚠️ **Note**: Family Provider is Riverpod's main advantage over Honeycomb. We plan to support it in a future version.

#### 4. Code Generation

```dart
// Riverpod 2.0: Recommended use of code generation
@riverpod
Future<User> user(UserRef ref, int id) async {
  return api.fetchUser(id);
}

// Honeycomb: Purely manual, no code generation
final userProfile = AsyncComputed((watch) async {
  return api.fetchUser(watch(userId));
});
```

### Comparison Table

| Feature | Honeycomb | Riverpod |
|------|-----------|----------|
| State/Effect Separation | ✅ Native | ❌ Manual |
| Family Provider | ❌ Manual | ✅ Native |
| Code Generation | ❌ Not Needed | ✅ Recommended |
| Effect Strategies | ✅ drop/bufferN/ttl | ❌ |
| SafeComputed | ✅ Result<T> | ❌ |
| Learning Curve | Medium | Medium-High |

### When to choose Riverpod

- ✅ Need Family Providers out-of-the-box.
- ✅ Team is comfortable with code generation.
- ✅ Mature and stable solution.

### When to choose Honeycomb

- ✅ Clear State/Effect separation is desired.
- ✅ Need explicit Effect delivery strategies.
- ✅ Want to avoid code generation.

---

## vs BLoC

### BLoC Overview

BLoC (Business Logic Component) is a stream-based pattern emphasizing event-driven and predictable states.

### Key Differences

#### 1. Architectural Complexity

```dart
// BLoC: Requires defining Event, State, and Bloc classes
abstract class CounterEvent {}
class Increment extends CounterEvent {}
class Decrement extends CounterEvent {}

class CounterState {
  final int count;
  CounterState(this.count);
}

class CounterBloc extends Bloc<CounterEvent, CounterState> {
  CounterBloc() : super(CounterState(0)) {
    on<Increment>((event, emit) => emit(CounterState(state.count + 1)));
    on<Decrement>((event, emit) => emit(CounterState(state.count - 1)));
  }
}
```

```dart
// Honeycomb: Concise
final counter = StateRef(0);

void increment(HoneycombContainer c) => c.update(counter, (n) => n + 1);
void decrement(HoneycombContainer c) => c.update(counter, (n) => n - 1);
```

#### 2. Traceability
```
```
