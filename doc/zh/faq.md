# 常见问题 (FAQ)

---

## 目录

1. [基础概念](#基础概念)
2. [使用问题](#使用问题)
3. [性能相关](#性能相关)
4. [测试相关](#测试相关)
5. [故障排除](#故障排除)

---

## 基础概念

### StateRef 和 Computed 有什么区别？

**StateRef** 是可读写的源状态：

```dart
final counter = StateRef(0);
container.write(counter, 1); // ✅ 可以写
```

**Computed** 是只读的派生状态：

```dart
final doubled = Computed((watch) => watch(counter) * 2);
container.write(doubled, 10); // ❌ 编译错误
```

经验法则：如果值可以从其他状态推导出来，就用 Computed。

---

### Effect 和 StateRef 有什么区别？

| | StateRef | Effect |
|---|----------|--------|
| 语义 | 持久状态 | 一次性事件 |
| 读取 | 任何时候读取都有值 | 无"当前值"概念 |
| 新订阅者 | 立即拿到最新值 | 不会收到历史事件 |
| 用途 | UI 渲染、缓存 | Toast、导航、埋点 |

---

### 什么时候用 EagerComputed？

当你需要**即使没有订阅者也立即重算**时：

```dart
// 普通 Computed：没人 watch 就不算
final lazyResult = Computed((watch) => expensive(watch(source)));

// EagerComputed：source 变了就算，不管有没有人 watch
final eagerResult = Computed.eager((watch) => expensive(watch(source)));
```

典型场景：
- 后台数据同步
- 预计算热门数据
- 缓存预热

---

### AsyncComputed 和普通异步操作的区别？

**AsyncComputed** 会自动处理：

1. **加载状态** — `AsyncLoading`
2. **成功数据** — `AsyncData<T>`
3. **错误状态** — `AsyncError`
4. **竞态条件** — 旧请求不会覆盖新请求

```dart
final userProfile = Computed.async((watch) async {
  return await api.fetchUser(watch(userId));
});

// 自动处理所有状态
ref.watch(userProfile).when(
  loading: () => CircularProgressIndicator(),
  data: (user) => Text(user.name),
  error: (e, _) => Text('Error: $e'),
);
```

---

### DisposePolicy 的三种模式怎么选？

| 模式 | 何时回收 | 适用场景 |
|------|----------|----------|
| `keepAlive` | 永不自动回收 | 全局状态、用户信息 |
| `autoDispose` | 无订阅者时立即回收 | 页面临时状态 |
| `delayed` | 无订阅者后延迟回收 | 可能很快重用的状态 |

```dart
// 用户信息：永久保持
final currentUser = StateRef<User?>(null, disposePolicy: DisposePolicy.keepAlive);

// 搜索关键词：离开页面就清理
final searchQuery = StateRef('', disposePolicy: DisposePolicy.autoDispose);

// 最近浏览：1 分钟后清理
final recentViews = StateRef([], 
  disposePolicy: DisposePolicy.delayed,
  disposeDelay: Duration(minutes: 1),
);
```

---

## 使用问题

### 如何在 StatelessWidget 中使用？

使用 `HoneycombConsumer`：

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

或者用 Context Extension（只读）：

```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // 注意：这不会自动重建！仅适合读取
    final count = context.read(counter);
    return Text('$count');
  }
}
```

---

### 如何在 initState 中访问状态？

```dart
class _MyState extends State<MyWidget> {
  @override
  void initState() {
    super.initState();
    
    // 使用 addPostFrameCallback 确保 context 可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final container = HoneycombScope.containerOf(context);
      container.write(someState, 'initial value');
    });
  }
}
```

或者使用 `didChangeDependencies`：

```dart
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  final container = HoneycombScope.containerOf(context);
  // ...
}
```

---

### 如何监听状态变化执行副作用？

使用 `HoneycombListener`：

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

或者监听 Effect：

```dart
HoneycombListener(
  effects: [toastEffect],
  listener: (context, container) {
    // 使用 container.on 获取具体事件
    // 或在这里处理
  },
  child: MyWidget(),
)
```

---

### 如何在非 Widget 代码中访问状态？

传递 Container 引用：

```dart
// 业务层
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

// 初始化
final container = HoneycombContainer();
final authService = AuthService(container);
```

---

### 如何实现全局单例状态？

```dart
// lib/global_state.dart
final globalContainer = HoneycombContainer();

// 在 main.dart 使用
void main() {
  runApp(
    HoneycombScope(
      container: globalContainer,
      child: MyApp(),
    ),
  );
}
```

但推荐使用 Scope 层级管理，而非全局变量。

---

### 如何处理列表项状态？

方法 1：在列表级别管理

```dart
final todoList = StateRef<List<Todo>>([]);

// 更新单项
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

方法 2：使用 Map 结构

```dart
final todosById = StateRef<Map<int, Todo>>({});

// 更新单项
void toggleTodo(int id) {
  container.update(todosById, (map) {
    final todo = map[id]!;
    return {...map, id: todo.copyWith(completed: !todo.completed)};
  });
}

// 派生排序列表
final sortedTodos = Computed((watch) {
  return watch(todosById).values.toList()..sort((a, b) => a.id.compareTo(b.id));
});
```

---

## 性能相关

### Computed 会重复计算吗？

不会。Computed 有缓存，只有依赖变化时才重算：

```dart
final expensive = Computed((watch) {
  print('Computing...'); // 只在依赖变化时打印
  return heavyCalculation(watch(source));
});

container.read(expensive); // Computing...
container.read(expensive); // (无输出，使用缓存)
container.read(expensive); // (无输出，使用缓存)

container.write(source, newValue); // 依赖变了

container.read(expensive); // Computing...
```

---

### 如何避免不必要的重建？

1. **使用 Selector**：

```dart
// ❌ 整个 user 变化都重建
ref.watch(userState);

// ✅ 只有 name 变化才重建
ref.watch(userState.select((u) => u.name));
```

2. **使用 child 参数**：

```dart
HoneycombConsumer(
  builder: (context, ref, child) {
    return Column(
      children: [
        Text('${ref.watch(counter)}'),
        child!, // 不会重建
      ],
    );
  },
  child: ExpensiveWidget(),
)
```

3. **拆分组件**：

```dart
// 把订阅不同状态的部分拆成不同组件
class CounterDisplay extends StatelessWidget { ... }
class NameDisplay extends StatelessWidget { ... }
```

---

### batch 能带来多大性能提升？

取决于场景。假设有 3 个 StateRef 和 5 个依赖它们的 Computed：

```dart
// 不用 batch：3 次 flush，可能触发 15 次重算
container.write(a, 1);
container.write(b, 2);
container.write(c, 3);

// 用 batch：1 次 flush，最多 5 次重算
container.batch(() {
  container.write(a, 1);
  container.write(b, 2);
  container.write(c, 3);
});
```

规则：同时更新多个状态时，始终用 batch。

---

## 测试相关

### 如何 Mock 异步 Computed？

使用 Override：

```dart
testWidgets('shows user', (tester) async {
  await tester.pumpWidget(
    HoneycombScope(
      overrides: [
        // 直接覆盖为成功状态
        userProfile.overrideWith(AsyncData(User(name: 'Test'))),
      ],
      child: MyApp(),
    ),
  );
  
  expect(find.text('Test'), findsOneWidget);
});
```

---

### 如何测试 Effect 被触发？

```dart
test('login failure emits error', () async {
  final container = HoneycombContainer();
  final errors = <String>[];
  
  container.on(authError, errors.add);
  
  // 模拟失败登录
  await login(container, 'wrong@email.com', 'wrongpass');
  
  expect(errors, isNotEmpty);
  expect(errors.first, contains('Invalid'));
});
```

---

### 如何测试 Computed 依赖关系？

```dart
test('total depends on items and prices', () {
  final container = HoneycombContainer();
  
  // 设置初始状态
  container.write(items, ['apple']);
  container.write(prices, {'apple': 1.0});
  
  expect(container.read(total), 1.0);
  
  // 改变 items
  container.write(items, ['apple', 'banana']);
  container.write(prices, {'apple': 1.0, 'banana': 2.0});
  
  expect(container.read(total), 3.0);
  
  // 只改变 prices
  container.update(prices, (p) => {...p, 'apple': 1.5});
  
  expect(container.read(total), 3.5);
});
```

---

## 故障排除

### "Cannot read atom during computation" 错误

原因：在 Computed 计算过程中尝试写入状态。

```dart
// ❌ 错误
final bad = Computed((watch) {
  container.write(otherState, 'value'); // 不能在这里写！
  return watch(source);
});

// ✅ 正确：使用 Effect 处理副作用
```

---

### "Circular dependency detected" 错误

原因：A 依赖 B，B 又依赖 A。

```dart
// ❌ 循环依赖
final a = Computed((watch) => watch(b) + 1);
final b = Computed((watch) => watch(a) + 1);

// ✅ 重构：消除循环
final source = StateRef(0);
final a = Computed((watch) => watch(source) + 1);
final b = Computed((watch) => watch(source) + 2);
```

---

### 组件没有重建

检查：

1. **是否用了 `watch`**：

```dart
// ❌ read 不会订阅
final count = ref.read(counter);

// ✅ watch 才会订阅
final count = ref.watch(counter);
```

2. **是否在正确的 Scope 内**：

```dart
// 确保组件在 HoneycombScope 子树内
HoneycombScope(
  child: MyWidget(), // ✅ 可以访问
)
```

3. **是否是不可变更新**：

```dart
// ❌ 直接修改不会触发更新
final list = container.read(items);
list.add(newItem);
container.write(items, list); // 同一个引用！

// ✅ 创建新列表
container.update(items, (list) => [...list, newItem]);
```

---

### Hot Reload 后状态丢失

Honeycomb 支持 Hot Reload，但默认不重置状态。如果需要清理：

```dart
// 在 reassemble 时清理
class _MyState extends State<MyWidget> {
  @override
  void reassemble() {
    super.reassemble();
    HoneycombScope.containerOf(context).invalidateAllComputed();
  }
}
```

---

### 内存泄漏

常见原因：

1. **没有取消 Effect 订阅**：

```dart
// ❌ 泄漏
initState() {
  container.on(effect, handler); // 没保存 subscription
}

// ✅ 正确
late StreamSubscription _sub;

initState() {
  _sub = container.on(effect, handler);
}

dispose() {
  _sub.cancel();
}
```

2. **忘记 dispose Container**：

```dart
// 如果自己创建了 Container，要记得 dispose
final container = HoneycombContainer();

// 不用时
container.dispose();
```

3. **应该用 autoDispose 但没用**：

```dart
// 页面级状态应该用 autoDispose
final pageState = StateRef(
  null,
  disposePolicy: DisposePolicy.autoDispose,
);
```

---

## 还有问题？

- 查看 [GitHub Issues](https://github.com/example/honeycomb/issues)
- 阅读 [源码](https://github.com/example/honeycomb)
- 查看 [示例项目](https://github.com/example/honeycomb/tree/main/example)
