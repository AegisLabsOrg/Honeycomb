# Core Concepts

This document explains the design philosophy and core concepts of Honeycomb in depth.

---

## Contents

1. [Design Philosophy](#design-philosophy)
2. [State vs Effect](#state-vs-effect)
3. [Atoms](#atoms)
4. [Container](#container)
5. [Dependency Tracking](#dependency-tracking)
6. [Scope and Overrides](#scope-and-overrides)
7. [Lifecycle Management](#lifecycle-management)
8. [Consistency Model](#consistency-model)

---

## Design Philosophy

Honeycomb's core philosophy:

> **State Management = Cache with Consistency Semantics (State) + Dependency Graph + Scheduler + Side-effect Model (Effects)**

We believe:

1. **UI Binding is just an adaptation layer** — The core should be reusable in non-UI environments (tests, background tasks).
2. **State and Effect must be separated** — They have fundamentally different semantics.
3. **Dependency tracking should be automated** — Manually declaring dependencies is error-prone.
4. **Testability is a priority** — State logic should be easy to unit test.

---

## State vs Effect

This is the most important design decision in Honeycomb.

### State

**Semantics**: At any time, subscribers can immediately get the latest value.

```dart
final userName = StateRef('Guest');

// Get the current value anytime
container.read(userName); // 'Guest'

// Changes take effect immediately
container.write(userName, 'Alice');
container.read(userName); // 'Alice'
```

**Features**:
- ✅ Replay Latest — New subscribers immediately receive the current value.
- ✅ Used for UI rendering, derived calculations, and caching.
- ✅ Has a concept of history (you can know "what it is now").

### Effect

**Semantics**: Triggered once, defaults to not replaying history.

```dart
final toastEffect = Effect<String>(strategy: EffectStrategy.drop);

// Emit an event
container.emit(toastEffect, 'Hello!');

// If there are no listeners, the event is discarded (with drop strategy)
```

**Features**:
- ✅ Stateless — Does not store a "current value".
- ✅ Used for Toasts, navigation, analytics, and one-time prompts.
- ✅ Explicit delivery strategies (drop / bufferN / ttl).

### Why Separate Them?

Many bugs arise from treating Events as State:

```dart
// ❌ WRONG: Storing an event in a State
final toastMessage = StateRef<String?>(null);

// Problem 1: New subscribers will receive the previous toast.
// Problem 2: Needs manual reset to null.
// Problem 3: Where is the event stored if the component doesn't exist?

// ✅ RIGHT: Using an Effect
final toastEffect = Effect<String>(strategy: EffectStrategy.drop);
```

### Effect Delivery Strategies

| Strategy | Description | Use Case |
|------|------|------|
| `drop` | Discard if no listeners | Toasts, temporary prompts |
| `bufferN` | Cache the last N items | Notification centers, message queues |
| `ttl` | Keep for the last X time | Limited-time offer prompts |

```dart
// Drop strategy (default)
final toast = Effect<String>(strategy: EffectStrategy.drop);

// Buffer strategy
final notifications = Effect<Notification>(
  strategy: EffectStrategy.bufferN,
  bufferSize: 20,
);

// TTL strategy
final flashSale = Effect<Sale>(
  strategy: EffectStrategy.ttl,
  ttlDuration: Duration(minutes: 5),
);
```

---

## Atoms

`Atom<T>` is the base class for all states, computations, and events.

### Type Hierarchy

```
Atom<T>
├── StateRef<T>       // Read-write state
├── Computed<T>       // Lazy derivation
├── EagerComputed<T>  // Eager derivation
├── AsyncComputed<T>  // Async derivation (returns AsyncValue<T>)
├── SafeComputed<T>   // Safe derivation (returns Result<T>)
└── Effect<T>         // One-time event
```

### StateRef

The most basic state container:

```dart
// Create
final counter = StateRef(0);
final user = StateRef(User.empty());

// Read
container.read(counter); // 0

// Write
container.write(counter, 1);

// With autoDispose
final tempData = StateRef(null, disposePolicy: DisposePolicy.autoDispose);
```

### Computed

Derived state with automatic dependency tracking:

```dart
final price = StateRef(100);
final quantity = StateRef(2);

final total = Computed((watch) {
  return watch(price) * watch(quantity);
});

// total will automatically recalculate when price or quantity changes
```

**Lazy Evaluation**: Only calculated when watched.

```dart
final expensive = Computed((watch) {
  return heavyCalculation(watch(source));
});

// If no one watches expensive, heavyCalculation will not execute.
```

### EagerComputed

Eager derivation, recalculates immediately when upstream changes (even with no subscribers):

```dart
final alwaysFresh = Computed.eager((watch) {
  return processData(watch(source));
});
```

**Use Case**: Background synchronization, pre-calculation.

### AsyncComputed

Asynchronous derivation, returns `AsyncValue<T>`:

```dart
final userProfile = Computed.async((watch) async {
  final id = watch(userId);
  return await api.fetchUser(id);
});

// Usage
ref.watch(userProfile).when(
  loading: () => ...,
  data: (user) => ...,
  error: (e, st) => ...,
);
```

**Features**:
- Automatically handles loading/data/error states.
- Automatically re-requests when dependencies change.
- Built-in race condition handling (old results won't overwrite new ones).

### SafeComputed

Derivation that automatically catches exceptions, returns `Result<T>`:

```dart
final validated = SafeComputed((watch) {
  final email = watch(emailInput);
  if (!email.contains('@')) {
    throw FormatException('Invalid email');
  }
  return email;
});

// Usage
ref.watch(validated).when(
  success: (email) => Text(email),
  failure: (error, _) => Text('Error: $error'),
);
```

---

## Container

`HoneycombContainer` is the central storage and management hub for state.

### Creation

```dart
// Root container
final container = HoneycombContainer();

// Scoped container
final scopedContainer = HoneycombContainer.scoped(
  container,
  overrides: [
    themeState.overrideWith(ThemeData.dark()),
  ],
);
```

### Core Methods

```dart
// Read
T read<T>(Atom<T> atom);

// Write
void write<T>(StateRef<T> ref, T value);

// Batch updates
void batch(void Function() updates);

// Emit events
void emit<T>(Effect<T> effect, T payload);

// Listen to events
StreamSubscription<T> on<T>(Effect<T> effect, void Function(T) callback);

// Subscribe to changes
void Function() subscribe<T>(Atom<T> atom, void Function() listener);
```

### Batching

```dart
container.batch(() {
  container.write(firstName, 'John');
  container.write(lastName, 'Doe');
  container.write(age, 30);
});
// All changes trigger only one recalculation/rebuild
```

---

## Dependency Tracking

Honeycomb uses a dynamic dependency collection mechanism.

### How it works

```dart
final a = StateRef(1);
final b = StateRef(2);
```
