# 🍯 Honeycomb

[English](./README.md) | [简体中文](./README_zh.md)

[![Pub Version](https://img.shields.io/pub/v/honeycomb)](https://pub.dev/packages/honeycomb)
[![Flutter](https://img.shields.io/badge/Flutter-3.27+-blue.svg)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Concise, type-safe, codegen-free state management library for Flutter.**

Honeycomb provides clear separation between **State** and **Effect** semantics, automatic dependency tracking, and a powerful Scope/Override mechanism.

---

## ✨ Features

- 🎯 **Context-Free Usage** — Access state in pure Dart logic (Services/Repositories) via Global Container.
- ⚡ **Auto Dependency Tracking** — Computed automatically tracks dependencies from `watch`.
- 📡 **State vs Effect** — Clearly distinguish between replayable state and one-time events.
- 🎭 **Scope/Override** — Flexible dependency injection and local overrides.
- 🔄 **No Codegen** — Pure Dart, no build_runner required.
- 🔒 **Type Safe** — Full generic support.
- 🧪 **Easy to Test** — Decouple state logic from UI for easy testing.

---

## 📦 Installation

```yaml
dependencies:
  honeycomb: ^1.0.0
```

```bash
flutter pub get
```

---

## 🚀 Quick Start

### 1. Define State

```dart
import 'package:aegis_honeycomb/honeycomb.dart';

// Read-write state
final counterState = StateRef(0);

// Derived state (auto dependency tracking)
final doubledCounter = Computed((watch) => watch(counterState) * 2);

// Async state
final userProfile = Computed.async((watch) async {
  final userId = watch(currentUserId);
  return await api.fetchUser(userId);
});

// One-time events
final toastEffect = Effect<String>();
```

### 2. Provide Container

```dart
// You can keep a global container if you don't want to rely on BuildContext.
final appContainer = HoneycombContainer();

void main() {
  runApp(
    HoneycombScope(
      container: appContainer,
      child: MyApp(),
    ),
  );
}
```

### 3. Use in UI

```dart
class CounterPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return HoneycombConsumer(
      builder: (context, ref, child) {
        final count = ref.watch(counterState);
        final doubled = ref.watch(doubledCounter);

        return Column(
          children: [
            Text('Count: $count'),
            Text('Doubled: $doubled'),
            ElevatedButton(
              onPressed: () {
                final container = HoneycombScope.readOf(context);
                container.write(counterState, count + 1);
              },
              child: Text('Increment'),
            ),
          ],
        );
      },
    );
  }
}
```

---

## 📚 Documentation

| Document | Description |
|------|------|
| [Getting Started](doc/en/getting-started.md) | Learn Honeycomb from scratch |
| [Core Concepts](doc/en/core-concepts.md) | Deep dive into design philosophy |
| [API Reference](doc/en/api-reference.md) | Full API documentation |
| [Best Practices](doc/en/best-practices.md) | Recommended usage patterns |
| [Comparison](doc/en/comparison.md) | Comparison with Provider/Riverpod/Bloc |
| [FAQ](doc/en/faq.md) | Frequently Asked Questions |

---

## 🎯 Core Concepts at a Glance

### State vs Effect

```dart
// State: Replayable, always returns the latest value
final userName = StateRef('Guest');

// Effect: One-time event, no historical storage
final showToast = Effect<String>(strategy: EffectStrategy.drop);
```

### Dependency Tracking

```dart
final fullName = Computed((watch) {
  // Automatically tracks firstName and lastName
  return '${watch(firstName)} ${watch(lastName)}';
});
// fullName recalculates whenever firstName or lastName changes
```

### Scope Override

`HoneycombScope` supports overriding state values in a subtree using the `overrides` parameter. This is extremely useful for testing (Mocking) or parameterizing child components.

**How it works:** When resolving an Atom, the container first checks if it's in `overrides`; if not, it looks up the parent container; finally, it creates a new node based on the default logic.

```dart
// Locally override state (e.g., for testing or theme switching)
HoneycombScope(
  overrides: [
    // Force themeState to be dark
    themeState.overrideWith(ThemeData.dark()),

    // Or override an async state with mock data
    userProfile.overrideWith(AsyncValue.data(MockUser())),
  ],
  child: DarkModePage(),
)
```

### Using in Business Logic (Outside Context)

Sometimes you need to access state in Repositories, Services, or pure Dart logic.

**1. Create a Global Container** (e.g. in `app_globals.dart`)

```dart
// Global singleton container
final appContainer = HoneycombContainer();
```

**2. Use directly in Services**

```dart
class AuthService {
  void logout() {
    // Read state
    final currentUser = appContainer.read(userState);
    
    // Write state
    appContainer.write(userState, null);
    
    // Emit event
    appContainer.emit(navigationEffect, '/login');
  }
}
```

**3. Inject into UI Tree**

```dart
void main() {
  runApp(
    HoneycombScope(
      container: appContainer, // Must inject the same instance for UI updates
      child: MyApp(),
    ),
  );
}
```

---

## 🧪 Testing

```dart
test('counter increments', () {
  final container = HoneycombContainer();
  
  expect(container.read(counterState), 0);
  
  container.write(counterState, 1);
  
  expect(container.read(counterState), 1);
  expect(container.read(doubledCounter), 2);
});
```

---

## 📊 Comparison

| Feature | Honeycomb | Provider | Riverpod | Bloc |
|------|-----------|----------|----------|------|
| No Codegen | ✅ | ✅ | ❌ | ✅ |
| Auto Tracking | ✅ | ❌ | ✅ | ❌ |
| State/Effect Separation | ✅ | ❌ | ❌ | ✅ |
| Scope Override | ✅ | ✅ | ✅ | ❌ |
| Batch Updates | ✅ | ❌ | ❌ | ✅ |
| Learning Curve | Low | Low | Medium | High |

---

## 🤝 Contributing

Contributions are welcome! Please check [CONTRIBUTING.md](CONTRIBUTING.md).

---

## 📄 License

MIT License - See the [LICENSE](LICENSE) file.
