# Getting Started

This guide will walk you through learning the Honeycomb state management library from scratch.

---

## Contents

1. [Installation](#installation)
2. [First Example: Counter](#first-example-counter)
3. [Understanding Core Concepts](#understanding-core-concepts)
4. [Using Derived State](#using-derived-state)
5. [Handling Async Data](#handling-async-data)
6. [Using Effects](#using-effects)
7. [Next Steps](#next-steps)

---

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  honeycomb: ^1.0.0
```

Then run:

```bash
flutter pub get
```

---

## First Example: Counter

Let's create a simple counter application to understand the basic usage of Honeycomb.

### Step 1: Define State

Create `lib/states.dart`:

```dart
import 'package:aegis_honeycomb/honeycomb.dart';

// Define a read-write state
final counterState = StateRef(0);
```

`StateRef` is the most basic state container in Honeycomb. It:
- Holds a value
- Returns the latest value when read
- Notifies all subscribers when the value changes

### Step 2: Setup HoneycombScope

In `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:aegis_honeycomb/honeycomb.dart';
import 'states.dart';

void main() {
  runApp(
    HoneycombScope(
      container: HoneycombContainer(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CounterPage(),
    );
  }
}
```

`HoneycombScope` passes the `HoneycombContainer` down via Flutter's InheritedWidget mechanism, allowing child components to access state.

### Step 3: Reading and Modifying State

```dart
class CounterPage extends StatelessWidget {
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Counter')),
      body: Center(
        child: HoneycombConsumer(
          builder: (context, ref, child) {
            // Use ref.watch to read state and rebuild when it changes
            final count = ref.watch(counterState);
            
            return Text(
              '$count',
              style: const TextStyle(fontSize: 48),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Get container and modify state
          final container = HoneycombScope.readOf(context);
          final current = container.read(counterState);
          container.write(counterState, current + 1);
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

**Key Points:**
- `ref.watch(atom)` — Reads the value and subscribes to changes; widget rebuilds automatically when the value changes.
- `container.read(atom)` — Read-only, no subscription.
- `container.write(stateRef, newValue)` — Writes a new value.

---

## Understanding Core Concepts

### Three Access Modes

| Method | Purpose | Subscribes? |
|------|------|---------|
| `ref.watch(atom)` | Read in UI, need to react to changes | ✅ |
| `container.read(atom)` | One-time read (e.g., event handling) | ❌ |
| `container.write(ref, value)` | Write new value | - |

### Why Separate watch and read?

```dart
// ❌ Bad: Using watch in event handlers creates unnecessary subscriptions
onPressed: () {
  final count = ref.watch(counterState); // Error!
}

// ✅ Good: Use read in event handlers
onPressed: () {
  final container = HoneycombScope.readOf(context);
  final count = container.read(counterState); // Correct
}
```

---

## Using Derived State

`Computed` is used to create values derived from other states, with automatic dependency tracking.

```dart
// states.dart
final counterState = StateRef(0);

// Derived state: Double the counter
final doubledCounter = Computed((watch) {
  return watch(counterState) * 2;
});

// Derived state: Check if even
final isEven = Computed((watch) {
  return watch(counterState) % 2 == 0;
});

// Combining multiple states
final firstName = StateRef('John');
final lastName = StateRef('Doe');

final fullName = Computed((watch) {
  return '${watch(firstName)} ${watch(lastName)}';
});
```

**Computed Features:**
- ✅ Lazy Evaluation — Only recalculated when watched.
- ✅ Auto Caching — Not recalculated if dependencies haven't changed.
- ✅ Auto Tracking — No need to manually declare dependencies.

Using in UI:

```dart
HoneycombConsumer(
  builder: (context, ref, _) {
    final count = ref.watch(counterState);
    final doubled = ref.watch(doubledCounter);
    final even = ref.watch(isEven);

    return Column(
      children: [
        Text('Count: $count'),
        Text('Doubled: $doubled'),
        Text(even ? 'Even' : 'Odd'),
      ],
    );
  },
)
```

---

## Handling Async Data

Use `Computed.async` for async operations:

```dart
final selectedUserId = StateRef(1);

final userProfile = Computed.async((watch) async {
  final userId = watch(selectedUserId);
  
  // Simulate API request
  await Future.delayed(const Duration(seconds: 1));
  
  return await api.fetchUser(userId);
});
```

`Computed.async` returns `AsyncValue<T>`, which includes three states:

```dart
HoneycombConsumer(
  builder: (context, ref, _) {
    final asyncUser = ref.watch(userProfile);

    return asyncUser.when(
      loading: () => const CircularProgressIndicator(),
      data: (user) => Text('Hello, ${user.name}'),
      error: (error, stack) => Text('Error: $error'),
    );
  },
)
```

### AsyncValue Methods

```dart
asyncValue.when(loading: ..., data: ..., error: ...);  // Pattern matching
asyncValue.valueOrNull;   // Get value or null
asyncValue.isLoading;     // Check if loading
```

---

## Using Effects

`Effect` is used for one-time events like Toasts, navigation, analytics, etc.

### Define Effects

```dart
// One-time event, dropped if no one is listening
final toastEffect = Effect<String>(strategy: EffectStrategy.drop);

// Buffered events, keeps the last N events
final notificationEffect = Effect<Notification>(
  strategy: EffectStrategy.bufferN,
  bufferSize: 10,
);
```

### Emitting Effects

```dart
// Using context extension
context.emit(toastEffect, 'Operation successful!');

// Or via container
container.emit(toastEffect, 'Hello!');
```

### Listening to Effects

Use the `HoneycombListener` Widget:

```dart
HoneycombListener<String>(
  effect: toastEffect,
  onEvent: (context, message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  },
  child: YourPageContent(),
)
```

---

## Next Steps

Congratulations! You have mastered the basics of Honeycomb. Next, you can:

- 📖 Read [Core Concepts](core-concepts.md) for deeper design philosophy.
- 🎯 Check [Best Practices](best-practices.md) for recommended patterns.
- 📚 Browse the [API Reference](api-reference.md) for the full API.
- 🔍 Run the [Example App](../example) for more use cases.

---

## Complete Example Code

```dart
import 'package:flutter/material.dart';
import 'package:aegis_honeycomb/honeycomb.dart';

// 1. Define State
final counterState = StateRef(0);
final doubledCounter = Computed((watch) => watch(counterState) * 2);
final toastEffect = Effect<String>();

void main() {
  runApp(
    // 2. Provide Container
    HoneycombScope(
      container: HoneycombContainer(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HoneycombListener<String>(
        effect: toastEffect,
        onEvent: (ctx, msg) {
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
        },
        child: const CounterPage(),
      ),
    );
  }
}

class CounterPage extends StatelessWidget {
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Honeycomb Demo')),
      body: Center(
        // 3. Use State
        child: HoneycombConsumer(
          builder: (context, ref, _) {
            final count = ref.watch(counterState);
            final doubled = ref.watch(doubledCounter);

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Count: $count', style: const TextStyle(fontSize: 32)),
                Text('Doubled: $doubled', style: const TextStyle(fontSize: 24)),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final container = HoneycombScope.readOf(context);
          container.write(counterState, container.read(counterState) + 1);
          context.emit(toastEffect, 'Counter incremented!');
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
```
