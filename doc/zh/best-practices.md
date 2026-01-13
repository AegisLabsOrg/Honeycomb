# 最佳实践

本文档介绍 Honeycomb 的推荐模式和反模式。

---

## 目录

1. [状态设计](#状态设计)
2. [命名规范](#命名规范)
3. [组件设计](#组件设计)
4. [性能优化](#性能优化)
5. [测试策略](#测试策略)
6. [反模式](#反模式)

---

## 状态设计

### ✅ 单一职责

每个 Atom 只负责一件事：

```dart
// ✅ Good: 职责清晰
final userName = StateRef('');
final userEmail = StateRef('');
final userAge = StateRef(0);

// ❌ Bad: 职责混杂
final formState = StateRef({
  'name': '',
  'email': '',
  'age': 0,
  'isLoading': false,
  'error': null,
});
```

### ✅ 按域组织

将相关状态放在同一文件：

```dart
// lib/features/auth/auth_state.dart

// 源状态
final currentUser = StateRef<User?>(null);
final authToken = StateRef<String?>(null);

// 派生状态
final isLoggedIn = Computed((watch) => watch(currentUser) != null);
final isTokenValid = Computed((watch) {
  final token = watch(authToken);
  return token != null && !_isExpired(token);
});

// 事件
final authError = Effect<AuthException>();
final logoutRequested = Effect<void>();
```

### ✅ 优先使用 Computed

能派生就派生，避免冗余状态：

```dart
final items = StateRef<List<Item>>([]);

// ✅ Good: 派生
final itemCount = Computed((watch) => watch(items).length);
final totalPrice = Computed((watch) {
  return watch(items).fold(0.0, (sum, item) => sum + item.price);
});

// ❌ Bad: 冗余状态
final itemCount = StateRef(0); // 需要手动同步
```

### ✅ 使用不可变数据

```dart
// ✅ Good: 不可变更新
container.update(todos, (list) => [...list, newTodo]);

// ❌ Bad: 直接修改
final list = container.read(todos);
list.add(newTodo); // 不会触发更新！
container.write(todos, list);
```

推荐使用 `freezed` 或 `built_value` 生成不可变类。

---

## 命名规范

### Atom 命名

| 类型 | 命名模式 | 示例 |
|------|----------|------|
| StateRef | 名词/形容词 | `userName`, `isLoading`, `selectedIds` |
| Computed | 名词/形容词 | `fullName`, `filteredItems`, `isValid` |
| Effect | 动词/事件名 | `showToast`, `navigateTo`, `loginFailed` |

### 文件组织

```
lib/
├── features/
│   ├── auth/
│   │   ├── auth_state.dart     # StateRef, Computed
│   │   ├── auth_effects.dart   # Effect
│   │   ├── auth_actions.dart   # 业务函数
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

## 组件设计

### ✅ 最小订阅原则

只订阅需要的状态：

```dart
// ✅ Good: 只订阅 userName
HoneycombConsumer(
  builder: (context, ref, _) {
    final name = ref.watch(userName);
    return Text(name);
  },
)

// ❌ Bad: 订阅整个 User 对象
HoneycombConsumer(
  builder: (context, ref, _) {
    final user = ref.watch(userState); // 任何字段变化都会重建
    return Text(user.name);
  },
)
```

### ✅ 使用 Selector 精细订阅

```dart
// 只在 name 变化时重建
HoneycombConsumer(
  builder: (context, ref, _) {
    final name = ref.watch(userState.select((u) => u.name));
    return Text(name);
  },
)
```

### ✅ 拆分组件

```dart
// ✅ Good: 拆分成小组件
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

// 父组件不订阅任何状态
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

### ✅ 使用 child 参数

```dart
// ✅ Good: 静态部分不重建
HoneycombConsumer(
  builder: (context, ref, child) {
    final count = ref.watch(counter);
    return Column(
      children: [
        Text('Count: $count'),
        child!, // 静态部分
      ],
    );
  },
  child: ExpensiveWidget(), // 不会重建
)
```

---

## 性能优化

### ✅ 批量更新

```dart
// ✅ Good: 一次 flush
container.batch(() {
  container.write(firstName, 'John');
  container.write(lastName, 'Doe');
  container.write(age, 30);
});

// ❌ Bad: 三次 flush
container.write(firstName, 'John');
container.write(lastName, 'Doe');
container.write(age, 30);
```

### ✅ 合理使用 autoDispose

```dart
// 页面级临时状态：使用 autoDispose
final searchQuery = StateRef(
  '',
  disposePolicy: DisposePolicy.autoDispose,
);

// 全局持久状态：使用 keepAlive
final currentUser = StateRef<User?>(
  null,
  disposePolicy: DisposePolicy.keepAlive,
);

// 防抖回收：使用 delayed
final recentSearches = StateRef(
  <String>[],
  disposePolicy: DisposePolicy.delayed,
  disposeDelay: Duration(minutes: 1),
);
```

### ✅ 避免昂贵的 Computed

```dart
// ❌ Bad: 每次都创建新对象
final userList = Computed((watch) {
  return watch(rawUsers).map((u) => UserViewModel(u)).toList();
});

// ✅ Good: 使用 selector 配合自定义比较
final userList = rawUsers.selectMany((users) {
  return users.map((u) => UserViewModel(u)).toList();
});
```

### ✅ 使用 EagerComputed 预热

```dart
// 后台预计算，UI 读取时直接拿到最新值
final processedData = Computed.eager((watch) {
  return heavyProcess(watch(rawData));
});
```

---

## 测试策略

### ✅ 单元测试状态逻辑

```dart
void main() {
  group('AuthState', () {
    late HoneycombContainer container;

    setUp(() {
      container = HoneycombContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('isLoggedIn is true when user exists', () {
      container.write(currentUser, User(name: 'Test'));
      expect(container.read(isLoggedIn), true);
    });

    test('isLoggedIn is false when user is null', () {
      container.write(currentUser, null);
      expect(container.read(isLoggedIn), false);
    });
  });
}
```

### ✅ 使用 Override 隔离测试

```dart
testWidgets('shows user name', (tester) async {
  await tester.pumpWidget(
    HoneycombScope(
      overrides: [
        currentUser.overrideWith(User(name: 'Test User')),
        apiClient.overrideWith(MockApiClient()),
      ],
      child: MaterialApp(home: UserProfile()),
    ),
  );

  expect(find.text('Test User'), findsOneWidget);
});
```

### ✅ 测试 Effect

```dart
test('emits toast on error', () async {
  final container = HoneycombContainer();
  final toasts = <String>[];

  container.on(toastEffect, toasts.add);

  // 触发错误逻辑
  container.write(formError, 'Invalid input');

  // 验证 Effect 被发送
  expect(toasts, contains('Invalid input'));
});
```

### ✅ 测试异步 Computed

```dart
test('userProfile loads user data', () async {
  final container = HoneycombContainer.scoped(
    HoneycombContainer(),
    overrides: [
      apiClient.overrideWith(MockApiClient()),
    ],
  );

  container.write(userId, '123');

  // 等待异步完成
  await Future.delayed(Duration(milliseconds: 100));

  final result = container.read(userProfile);
  expect(result, isA<AsyncData<User>>());
});
```

---

## 反模式

### ❌ 在 build 中写入状态

```dart
// ❌ Bad: 会导致无限循环
@override
Widget build(BuildContext context) {
  context.write(counter, context.read(counter) + 1); // 危险！
  return Text('...');
}
```

### ❌ 在 Computed 中产生副作用

```dart
// ❌ Bad: Computed 应该是纯函数
final badComputed = Computed((watch) {
  final value = watch(source);
  api.trackEvent('read'); // 副作用！
  return value;
});

// ✅ Good: 使用 Effect 处理副作用
final trackingEffect = Effect<String>();
container.on(trackingEffect, (event) => api.trackEvent(event));
```

### ❌ 过深的 Computed 链

```dart
// ❌ Bad: 链太长，调试困难
final a = Computed((w) => w(source) + 1);
final b = Computed((w) => w(a) * 2);
final c = Computed((w) => w(b) - 3);
final d = Computed((w) => w(c) / 4);
final e = Computed((w) => w(d) + 5);

// ✅ Good: 合并相关逻辑
final result = Computed((w) {
  final x = w(source);
  return ((x + 1) * 2 - 3) / 4 + 5;
});
```

### ❌ 在 Computed 中监听可选依赖

```dart
// ❌ Bad: 条件外的 watch
final bad = Computed((watch) {
  final showB = watch(showBState);
  final b = watch(bState); // 即使 showB=false 也会订阅
  
  if (showB) {
    return b;
  }
  return 'default';
});

// ✅ Good: watch 在条件内
final good = Computed((watch) {
  if (watch(showBState)) {
    return watch(bState);
  }
  return 'default';
});
```

### ❌ 将 Effect 当作 State 使用

```dart
// ❌ Bad: 查询 Effect 的"当前值"
final lastToast = container.read(toastEffect); // 错误！

// ✅ Good: Effect 是事件流，使用 on 监听
container.on(toastEffect, (message) {
  // 处理事件
});
```

### ❌ 忘记取消订阅

```dart
// ❌ Bad: 内存泄漏
class _MyState extends State<MyWidget> {
  @override
  void initState() {
    super.initState();
    container.on(effect, handleEffect); // 没有保存 subscription
  }
}

// ✅ Good: 保存并取消
class _MyState extends State<MyWidget> {
  late StreamSubscription _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = container.on(effect, handleEffect);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
```

---

## 检查清单

在提交代码前检查：

- [ ] 所有 StateRef 都有清晰的命名
- [ ] 没有冗余状态（能派生的已派生）
- [ ] Computed 是纯函数
- [ ] Effect 只用于一次性事件
- [ ] 使用了 batch 合并多个写入
- [ ] 组件只订阅需要的状态
- [ ] 订阅都有正确取消
- [ ] 有对应的单元测试
- [ ] 临时状态使用了 autoDispose

---

## 下一步

- 查看 [常见问题](faq.md) 解决常见疑惑
- 阅读 [与其他库对比](comparison.md) 了解技术选型
