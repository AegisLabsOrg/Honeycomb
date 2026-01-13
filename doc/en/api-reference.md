# API Reference

Full API documentation for Honeycomb.

---

## Contents

- [Atoms](#atoms)
  - [StateRef](#stateref)
  - [Computed](#computed)
  - [EagerComputed](#eagercomputed)
  - [SafeComputed](#safecomputed)
  - [AsyncComputed](#asynccomputed)
  - [Effect](#effect)
- [Container](#container)
- [Flutter Bindings](#flutter-bindings)
- [Utility Types](#utility-types)
- [Diagnostics](#diagnostics)

---

## Atoms

### StateRef

Mutable state reference.

```dart
class StateRef<T> extends Atom<T>
```

#### Constructor

```dart
StateRef(
  T initial, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
  Duration disposeDelay = const Duration(seconds: 5),
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `initial` | `T` | Required | Initial value |
| `disposePolicy` | `DisposePolicy` | `keepAlive` | Lifecycle policy |
| `disposeDelay` | `Duration` | `5s` | Delayed cleanup time (only for delayed policy) |

#### Methods

##### `overrideWith`

```dart
Override overrideWith(T value)
```

Creates an override configuration for `HoneycombScope`.

```dart
HoneycombScope(
  overrides: [counter.overrideWith(100)],
  child: ...
)
```

---

### Computed

Lazy derived state.

```dart
class Computed<T> extends Atom<T>
```

#### Constructor

```dart
Computed(
  T Function(T Function<T>(Atom<T>) watch) compute, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
  Duration disposeDelay = const Duration(seconds: 5),
})
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `compute` | `Function` | Computation function, reads dependencies via `watch` |
| `disposePolicy` | `DisposePolicy` | Lifecycle policy |

#### Static Factories

##### `Computed.eager`

```dart
static EagerComputed<T> eager<T>(
  T Function(T Function<T>(Atom<T>) watch) compute, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
})
```

Creates an eagerly evaluated Computed that recalculates immediately when dependencies change.

##### `Computed.async`

```dart
static AsyncComputed<T> async<T>(
  Future<T> Function(T Function<T>(Atom<T>) watch) compute, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
})
```

Creates an asynchronous Computed returning `AsyncValue<T>`.

##### `Computed.safe`

```dart
static SafeComputed<T> safe<T>(
  T Function(T Function<T>(Atom<T>) watch) compute, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
})
```

Creates a safe Computed that automatically catches exceptions and returns `Result<T>`.

---

### EagerComputed

Eager derived state.

```dart
class EagerComputed<T> extends Atom<T>
```

Recalculates immediately when dependencies change, even if there are no subscribers.

#### Constructor

```dart
EagerComputed(
  T Function(T Function<T>(Atom<T>) watch) compute, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
})
```

---

### SafeComputed

Safe derived state that automatically catches exceptions.

```dart
class SafeComputed<T> extends Atom<Result<T>>
```

#### Constructor

```dart
SafeComputed(
  T Function(T Function<T>(Atom<T>) watch) compute, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
})
```

The return type is `Result<T>`.

---

### AsyncComputed

Asynchronous derived state.

```dart
class AsyncComputed<T> extends Atom<AsyncValue<T>>
```

#### Constructor

```dart
AsyncComputed(
  Future<T> Function(T Function<T>(Atom<T>) watch) compute, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
})
```

The return type is `AsyncValue<T>`.

---

### Effect

One-time event.

```dart
class Effect<T> extends Atom<T>
```

#### Constructor

```dart
Effect({
  EffectStrategy strategy = EffectStrategy.drop,
  int bufferSize = 10,
  Duration ttlDuration = const Duration(seconds: 30),
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `strategy` | `EffectStrategy` | `drop` | Delivery strategy when no listeners exist |
| `bufferSize` | `int` | `10` | Buffer size for bufferN strategy |
| `ttlDuration` | `Duration` | `30s` | Expiration time for ttl strategy |

---

## Container

### HoneycombContainer

State container.

```dart
class HoneycombContainer
```

#### Constructor

```dart
HoneycombContainer()
```

##### Named Constructor

```dart
HoneycombContainer.scoped(
  HoneycombContainer parent, {
  List<Override> overrides = const [],
})
```

Creates a child container that can override the parent container's state.

---

#### Methods

##### `read`

```dart
T read<T>(Atom<T> atom)
```

Reads the current value of an atom.

```dart
final value = container.read(counter);
```

---

##### `write`

```dart
void write<T>(StateRef<T> ref, T value)
```

Writes a state value.

```dart
container.write(counter, 42);
```

---

##### `update`

```dart
void update<T>(StateRef<T> ref, T Function(T current) updater)
```

Updates state based on the current value.

```dart
container.update(counter, (n) => n + 1);
```

---

##### `batch`

```dart
void batch(void Function() updates)
```

Batch updates to coalecse all change notifications.

```dart
container.batch(() {
  container.write(a, 1);
```
