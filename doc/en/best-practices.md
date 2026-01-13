# Best Practices

This document introduces recommended patterns and anti-patterns for using Honeycomb.

---

## Contents

1. [State Design](#state-design)
2. [Naming Conventions](#naming-conventions)
3. [Component Design](#component-design)
4. [Performance Optimization](#performance-optimization)
5. [Testing Strategy](#testing-strategy)
6. [Anti-patterns](#anti-patterns)

---

## State Design

### ✅ Single Responsibility

Each Atom should be responsible for only one thing:

```dart
// ✅ Good: Clear responsibilities
final userName = StateRef('');
final userEmail = StateRef('');
final userAge = StateRef(0);

// ❌ Bad: Mixed responsibilities
final formState = StateRef({
  'name': '',
  'email': '',
  'age': 0,
  'isLoading': false,
  'error': null,
});
```

### ✅ Organize by Domain

Place related states in the same file:

```dart
// lib/features/auth/auth_state.dart

// Source state
final currentUser = StateRef<User?>(null);
final authToken = StateRef<String?>(null);

// Derived state
final isLoggedIn = Computed((watch) => watch(currentUser) != null);
final isTokenValid = Computed((watch) {
  final token = watch(authToken);
  return token != null && !_isExpired(token);
});

// Events
final authError = Effect<AuthException>();
final logoutRequested = Effect<void>();
```

### ✅ Prefer Computed

Derive whenever possible to avoid redundant state:

```dart
final items = StateRef<List<Item>>([]);

// ✅ Good: Derivation
final itemCount = Computed((watch) => watch(items).length);
final totalPrice = Computed((watch) {
  return watch(items).fold(0.0, (sum, item) => sum + item.price);
});

// ❌ Bad: Redundant state
final itemCount = StateRef(0); // Requires manual synchronization
```

### ✅ Use Immutable Data

```dart
// ✅ Good: Immutable update
container.update(todos, (list) => [...list, newTodo]);

// ❌ Bad: Direct modification
final list = container.read(todos);
list.add(newTodo); // Will not trigger an update!
container.write(todos, list);
```

Using `freezed` or `built_value` for generated immutable classes is highly recommended.

---

## Naming Conventions

### Atom Naming

| Type | Naming Pattern | Example |
|------|----------------|---------|
| StateRef | Noun/Adjective | `userName`, `isLoading`, `selectedIds` |
| Computed | Noun/Adjective | `fullName`, `filteredItems`, `isValid` |
| Effect | Verb/Event Name | `showToast`, `navigateTo`, `loginFailed` |

### File Organization

```
lib/
├── features/
│   ├── auth/
│   │   ├── auth_state.dart     # StateRef, Computed
│   │   ├── auth_effects.dart   # Effect
│   │   ├── auth_actions.dart   # Business functions
│   │   └── auth_page.dart      # UI
│   └── todo/
│       ├── todo_state.dart
│       └── todo_page.dart
├── shared/
│   ├── theme_state.dart
│   └── navigation_state.dart
└── main.dart
```

---

## Component Design

### ✅ Minimum Subscription Principle

Subscribe only to the state needed:

```dart
// ✅ Good: Subscribes only touserName
HoneycombConsumer(
  builder: (context, ref, _) {
    final name = ref.watch(userName);
    return Text(name);
  },
)

// ❌ Bad: Subscribes to the entire User object
HoneycombConsumer(
  builder: (context, ref, _) {
    final user = ref.watch(userState); // Rebuilds if any field changes
    return Text(user.name);
  },
)
```

### ✅ Precise Subscription with Selectors

```dart
// Rebuilds only when name changes
HoneycombConsumer(
  builder: (context, ref, _) {
    final name = ref.watch(userState.select((u) => u.name));
    return Text(name);
  },
)
```

### ✅ Breakdown Components

```dart
// ✅ Good: Small components
class UserAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return HoneycombConsumer(
      builder: (context, ref, _) {
        final avatar = ref.watch(userState.select((u) => u.avatarUrl));
        return CircleAvatar(backgroundImage: NetworkImage(avatar));
      },
    );
  }
}

class UserName extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return HoneycombConsumer(
      builder: (context, ref, _) {
        final name = ref.watch(userState.select((u) => u.name));
        return Text(name);
      },
    );
  }
}

// Parent component doesn't subscribe to any state
class UserProfile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        UserAvatar(),
        UserName(),
      ],
    );
  }
}
```

### ✅ Use the child Parameter

```dart
// ✅ Good: Static part doesn't rebuild
HoneycombConsumer(
  builder: (context, ref, child) {
    final count = ref.watch(counter);
    return Column(
      children: [
        Text('Count: $count'),
        child!, // Static part
      ],
    );
  },
  child: ExpensiveWidget(), // Won't rebuild
)
```

---

## Performance Optimization

### ✅ Batch Updates

```dart
// ✅ Good: Flushed once
container.batch(() {
  container.write(firstName, 'John');
  container.write(lastName, 'Doe');
  container.write(age, 30);
});

// ❌ Bad: Flushed three times
container.write(firstName, 'John');
container.write(lastName, 'Doe');
container.write(age, 30);
```

### ✅ Rational Use of autoDispose

```dart
// Page-level temporary state: use autoDispose
final searchQuery = StateRef(
  '',
  disposePolicy: DisposePolicy.autoDispose,
);

// Global persistent state: use keepAlive
final currentUser = StateRef<User?>(
  null,
  disposePolicy: DisposePolicy.keepAlive,
);

// Debounced cleanup: use delayed
final recentSearches = StateRef(
  <String>[],
  disposePolicy: DisposePolicy.delayed,
  disposeDelay: Duration(minutes: 1),
);
```

### ✅ Avoid Expensive Computed

```dart
// ❌ Bad: Creates a new object every time
final userList = Computed((watch) {
  return watch(rawUsers).map((u) => UserViewModel(u)).toList();
});

// ✅ Good: Use selector with custom comparison
final userList = rawUsers.selectMany((users) {
  return users.map((u) => UserViewModel(u)).toList();
});
```

### ✅ Warm up with EagerComputed

```dart
// Pre-calculates in background, UI gets the latest value directly when reading
final processedData = Computed.eager((watch) {
  return heavyProcess(watch(rawData));
});
```

---

## Testing Strategy

### ✅ Unit Test State Logic

```dart
void main() {
  group('AuthState', () {
    late HoneycombContainer container;

    setUp(() {
```
