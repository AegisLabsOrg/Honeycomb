# Frequently Asked Questions (FAQ)

---

## Contents

1. [Basic Concepts](#basic-concepts)
2. [Usage Questions](#usage-questions)
3. [Performance Related](#performance-related)
4. [Testing Related](#testing-related)
5. [Troubleshooting](#troubleshooting)

---

## Basic Concepts

### What is the difference between StateRef and Computed?

**StateRef** is a read-write source state:

```dart
final counter = StateRef(0);
container.write(counter, 1); // ✅ Can write
```

**Computed** is a read-only derived state:

```dart
final doubled = Computed((watch) => watch(counter) * 2);
container.write(doubled, 10); // ❌ Compilation error
```

Rule of thumb: If a value can be derived from other states, use Computed.

---

### What is the difference between Effect and StateRef?

| | StateRef | Effect |
|---|----------|--------|
| Semantics | Persistent State | One-time Event |
| Reading | Accessible anytime | No "current value" concept |
| New Subscribers | Immediately get latest value | Don't receive historical events |
| Purpose | UI rendering, caching | Toasts, navigation, analytics |

---

### When should I use EagerComputed?

When you need to **recalculate immediately even if there are no subscribers**:

```dart
// Normal Computed: only calculates when someone watches
final lazyResult = Computed((watch) => expensive(watch(source)));

// EagerComputed: calculates whenever source changes, regardless of watchers
final eagerResult = Computed.eager((watch) => expensive(watch(source)));
```

Typical scenarios:
- Background data synchronization.
- Pre-calculating popular data.
- Cache warming.

---

### What is the difference between AsyncComputed and normal async operations?

**AsyncComputed** automatically handles:

1. **Loading State** — `AsyncLoading`
2. **Success Data** — `AsyncData<T>`
3. **Error State** — `AsyncError`
4. **Race Conditions** — Old requests won't overwrite newer ones.

```dart
final userProfile = Computed.async((watch) async {
  return await api.fetchUser(watch(userId));
});

// Automatically handles all states
ref.watch(userProfile).when(
  loading: () => CircularProgressIndicator(),
  data: (user) => Text(user.name),
  error: (e, _) => Text('Error: $e'),
);
```

---

### How do I choose between the three DisposePolicy modes?

| Mode | When it's cleaned up | Use Case |
|------|----------|----------|
| `keepAlive` | Never automatically | Global state, user info |
| `autoDispose` | Immediately when no subscribers | Page-level temporary state |
| `delayed` | After a delay when no subscribers | State that might be reused soon |

```dart
// User info: kept permanently
final currentUser = StateRef<User?>(null, disposePolicy: DisposePolicy.keepAlive);

// Search query: cleared when leaving the page
final searchQuery = StateRef('', disposePolicy: DisposePolicy.autoDispose);

// Recent views: cleared after 1 minute
final recentViews = StateRef([], 
  disposePolicy: DisposePolicy.delayed,
  disposeDelay: Duration(minutes: 1),
);
```

---

## Usage Questions

### How do I use it in a StatelessWidget?

Use `HoneycombConsumer`:

```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return HoneycombConsumer(
      builder: (context, ref, child) {
        final count = ref.watch(counter);
        return Text('$count');
      },
    );
  }
}
```

Or use the Context Extension (read-only):

```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Note: This won't trigger builds! Suitable only for reading.
    final count = context.read(counter);
    return Text('$count');
  }
}
```

---

### How do I access state in initState?

```dart
class _MyState extends State<MyWidget> {
  @override
  void initState() {
    super.initState();
    
    // Ensure context is usable with addPostFrameCallback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final container = HoneycombScope.containerOf(context);
      container.write(someState, 'initial value');
    });
  }
}
```

Or use `didChangeDependencies`:

```dart
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  final container = HoneycombScope.containerOf(context);
  // ...
}
```

---

### How do I listen to state changes to perform side effects?

Use `HoneycombListener`:

```dart
HoneycombListener(
  atoms: [counter],
  listener: (context, container) {
    final count = container.read(counter);
    if (count > 10) {
      showDialog(...);
    }
  },
  child: MyWidget(),
)
```

Or listen to an Effect:

```dart
HoneycombListener(
  effects: [toastEffect],
  listener: (context, container) {
    // Use container.on to get specific events
    // or handle here
  },
  child: MyWidget(),
)
```

---

### How do I access state in non-Widget code?

Pass a Container reference:

```dart
// Business Layer
class AuthService {
  final HoneycombContainer container;
  
  AuthService(this.container);
  
  Future<void> login(String email, String password) async {
    container.write(isLoading, true);
    try {
      final user = await api.login(email, password);
      container.write(currentUser, user);
    } catch (e) {
      container.emit(authError, e.toString());
    } finally {
      container.write(isLoading, false);
    }
  }
}

// Initialization
final container = HoneycombContainer();
final authService = AuthService(container);
```

---

### How do I implement global singleton state?

```dart
// lib/global_state.dart
final globalContainer = HoneycombContainer();

// Use in main.dart
void main() {
  runApp(
    HoneycombScope(
      container: globalContainer,
      child: MyApp(),
    ),
  );
}
```

However, using the Scope hierarchy for management is recommended over global variables.

---

### How do I handle list item states?

Option 1: Manage at list level

```dart
final todoList = StateRef<List<Todo>>([]);

// Update single item
void toggleTodo(int id) {
  container.update(todoList, (list) {
    return list.map((todo) {
      if (todo.id == id) {
        return todo.copyWith(completed: !todo.completed);
      }
      return todo;
    }).toList();
  });
}
```

Option 2: Use a Map structure

```dart
final todosById = StateRef<Map<int, Todo>>({});

// Update single item
void toggleTodo(int id) {
  container.update(todosById, (map) {
    final todo = map[id]!;
    return {...map, id: todo.copyWith(completed: !todo.completed)};
  });
}

// Derived sorted list
final sortedTodos = Computed((watch) {
  return watch(todosById).values.toList()..sort((a, b) => a.id.compareTo(b.id));
});
```
