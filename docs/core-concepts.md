# 核心概念

本文档深入解释 Honeycomb 的设计理念和核心概念。

---

## 目录

1. [设计哲学](#设计哲学)
2. [State vs Effect](#state-vs-effect)
3. [原子 (Atom)](#原子-atom)
4. [容器 (Container)](#容器-container)
5. [依赖追踪](#依赖追踪)
6. [Scope 与 Override](#scope-与-override)
7. [生命周期管理](#生命周期管理)
8. [一致性模型](#一致性模型)

---

## 设计哲学

Honeycomb 的核心理念：

> **状态管理 = 带一致性语义的缓存（State） + 依赖追踪（Dependency Graph） + 调度器（Scheduler） + 副作用模型（Effects）**

我们认为：

1. **UI 绑定只是适配层** — 内核应该能在非 UI 环境复用（测试、后台任务）
2. **State 和 Effect 必须分离** — 它们有本质不同的语义
3. **依赖追踪应该自动化** — 手动声明依赖容易出错
4. **测试友好性优先** — 状态逻辑应该易于单元测试

---

## State vs Effect

这是 Honeycomb 最重要的设计决策。

### State（状态）

**语义**：任何时候订阅都能立刻拿到最新值。

```dart
final userName = StateRef('Guest');

// 无论何时读取，都能拿到当前值
container.read(userName); // 'Guest'

// 修改后立即生效
container.write(userName, 'Alice');
container.read(userName); // 'Alice'
```

**特点**：
- ✅ Replay Latest — 新订阅者立即拿到当前值
- ✅ 用于 UI 渲染、派生计算、缓存
- ✅ 有历史概念（可以知道"现在是什么"）

### Effect（事件）

**语义**：一次性触发，默认不重放历史。

```dart
final toastEffect = Effect<String>(strategy: EffectStrategy.drop);

// 发送事件
container.emit(toastEffect, 'Hello!');

// 如果没有监听者，事件被丢弃 (drop 策略)
```

**特点**：
- ✅ 无状态 — 不存储"当前值"
- ✅ 用于 Toast、导航、埋点、一次性提示
- ✅ 明确的投递策略（drop / bufferN / ttl）

### 为什么要分离？

很多 bug 来自于把 Event 当作 State 处理：

```dart
// ❌ 错误：用 State 存储事件
final toastMessage = StateRef<String?>(null);

// 问题1：新订阅者会收到上一条 toast
// 问题2：需要手动重置为 null
// 问题3：组件不存在时事件存储在哪里？

// ✅ 正确：使用 Effect
final toastEffect = Effect<String>(strategy: EffectStrategy.drop);
```

### Effect 投递策略

| 策略 | 说明 | 用途 |
|------|------|------|
| `drop` | 无人监听时丢弃 | Toast、临时提示 |
| `bufferN` | 缓存最近 N 条 | 通知中心、消息队列 |
| `ttl` | 保留最近 X 时间 | 限时活动提示 |

```dart
// 丢弃策略（默认）
final toast = Effect<String>(strategy: EffectStrategy.drop);

// 缓冲策略
final notifications = Effect<Notification>(
  strategy: EffectStrategy.bufferN,
  bufferSize: 20,
);

// TTL 策略
final flashSale = Effect<Sale>(
  strategy: EffectStrategy.ttl,
  ttlDuration: Duration(minutes: 5),
);
```

---

## 原子 (Atom)

`Atom<T>` 是所有状态/计算/事件的基类。

### 类型层级

```
Atom<T>
├── StateRef<T>       // 可读写状态
├── Computed<T>       // 惰性派生
├── EagerComputed<T>  // 急切派生
├── AsyncComputed<T>  // 异步派生 (返回 AsyncValue<T>)
├── SafeComputed<T>   // 安全派生 (返回 Result<T>)
└── Effect<T>         // 一次性事件
```

### StateRef

最基础的状态容器：

```dart
// 创建
final counter = StateRef(0);
final user = StateRef(User.empty());

// 读取
container.read(counter); // 0

// 写入
container.write(counter, 1);

// 带 autoDispose
final tempData = StateRef(null, disposePolicy: DisposePolicy.autoDispose);
```

### Computed

派生状态，自动追踪依赖：

```dart
final price = StateRef(100);
final quantity = StateRef(2);

final total = Computed((watch) {
  return watch(price) * watch(quantity);
});

// total 会在 price 或 quantity 变化时自动重算
```

**惰性求值**：只有被 watch 时才计算

```dart
final expensive = Computed((watch) {
  return heavyCalculation(watch(source));
});

// 没人 watch expensive 时，heavyCalculation 不会执行
```

### EagerComputed

急切派生，上游变化时立即重算（即使没有订阅者）：

```dart
final alwaysFresh = Computed.eager((watch) {
  return processData(watch(source));
});
```

**用途**：后台同步、预计算

### AsyncComputed

异步派生，返回 `AsyncValue<T>`：

```dart
final userProfile = Computed.async((watch) async {
  final id = watch(userId);
  return await api.fetchUser(id);
});

// 使用
ref.watch(userProfile).when(
  loading: () => ...,
  data: (user) => ...,
  error: (e, st) => ...,
);
```

**特性**：
- 自动处理 loading/data/error 状态
- 依赖变化时自动重新请求
- 内置竞态处理（旧请求结果不会覆盖新请求）

### SafeComputed

自动捕获异常的派生，返回 `Result<T>`：

```dart
final validated = SafeComputed((watch) {
  final email = watch(emailInput);
  if (!email.contains('@')) {
    throw FormatException('Invalid email');
  }
  return email;
});

// 使用
ref.watch(validated).when(
  success: (email) => Text(email),
  failure: (error, _) => Text('Error: $error'),
);
```

---

## 容器 (Container)

`HoneycombContainer` 是状态的存储和管理中心。

### 创建

```dart
// 根容器
final container = HoneycombContainer();

// 子容器（Scope）
final scopedContainer = HoneycombContainer.scoped(
  container,
  overrides: [
    themeState.overrideWith(ThemeData.dark()),
  ],
);
```

### 核心方法

```dart
// 读取
T read<T>(Atom<T> atom);

// 写入
void write<T>(StateRef<T> ref, T value);

// 批量更新
void batch(void Function() updates);

// 发送事件
void emit<T>(Effect<T> effect, T payload);

// 监听事件
StreamSubscription<T> on<T>(Effect<T> effect, void Function(T) callback);

// 订阅变化
void Function() subscribe<T>(Atom<T> atom, void Function() listener);
```

### 批量更新

```dart
container.batch(() {
  container.write(firstName, 'John');
  container.write(lastName, 'Doe');
  container.write(age, 30);
});
// 所有变更只触发一次重算/重建
```

---

## 依赖追踪

Honeycomb 使用动态依赖收集机制。

### 工作原理

```dart
final a = StateRef(1);
final b = StateRef(2);

final sum = Computed((watch) {
  // 调用 watch 时，依赖关系被自动记录
  return watch(a) + watch(b);
});
```

当 `sum` 被求值时：
1. 全局设置 `currentlyComputingNode = sum`
2. 执行计算函数
3. `watch(a)` 被调用，记录 `sum → a` 依赖
4. `watch(b)` 被调用，记录 `sum → b` 依赖
5. 计算完成，清除 `currentlyComputingNode`

### 条件依赖

```dart
final showDetails = StateRef(false);
final details = StateRef('...');

final display = Computed((watch) {
  if (watch(showDetails)) {
    return watch(details);  // 只有 showDetails=true 时才依赖 details
  }
  return 'Hidden';
});
```

依赖是动态的：
- `showDetails = false` 时，`display` 只依赖 `showDetails`
- `showDetails = true` 时，`display` 依赖 `showDetails` 和 `details`

### 循环依赖检测

```dart
final a = Computed((watch) => watch(b) + 1);
final b = Computed((watch) => watch(a) + 1);

// 抛出 CircularDependencyError
container.read(a);
```

---

## Scope 与 Override

### 层级关系

```
Root Container
    │
    ├── App Scope
    │       │
    │       ├── Page A Scope (override userTheme)
    │       │
    │       └── Page B Scope
    │               │
    │               └── Dialog Scope (override translations)
```

### 查找规则

```
当前 Scope → 父 Scope → ... → 根 Container
```

优先使用最近的 Scope 中的值。

### Override 示例

```dart
// 全局主题
final themeState = StateRef(ThemeData.light());

// 根 Scope
HoneycombScope(
  container: HoneycombContainer(),
  child: MaterialApp(
    home: HoneycombConsumer(
      builder: (_, ref, __) {
        // 使用全局主题: light
        final theme = ref.watch(themeState);
        ...
      },
    ),
  ),
)

// 局部 Override
HoneycombScope(
  overrides: [themeState.overrideWith(ThemeData.dark())],
  child: DarkModePage(), // 这里的主题是 dark
)
```

### 测试中的 Override

```dart
testWidgets('shows user name', (tester) async {
  await tester.pumpWidget(
    HoneycombScope(
      overrides: [
        userState.overrideWith(User(name: 'Test User')),
        apiClient.overrideWith(MockApiClient()),
      ],
      child: MyApp(),
    ),
  );
  
  expect(find.text('Test User'), findsOneWidget);
});
```

---

## 生命周期管理

### DisposePolicy

```dart
enum DisposePolicy {
  keepAlive,    // 永不自动回收（默认）
  autoDispose,  // 无人订阅时立即回收
  delayed,      // 延迟回收（防抖）
}

final tempData = StateRef(
  null,
  disposePolicy: DisposePolicy.autoDispose,
);
```

### 手动 keepAlive

```dart
// 阻止自动回收
container.keepAlive(someAtom);
```

### Container 销毁

```dart
// 销毁容器及其所有状态
container.dispose();
```

---

## 一致性模型

### 批处理一致

Honeycomb 默认使用批处理一致性模型：

```dart
container.batch(() {
  container.write(a, 1);
  container.write(b, 2);
  container.write(c, 3);
});
// 所有下游 Computed 只重算一次
// 所有 UI 只重建一次
```

### 保证

1. **同一轮 flush 内视图一致** — 不会看到"半更新"状态
2. **同一节点最多重算一次** — 即使多个依赖变化
3. **拓扑顺序** — 上游先于下游重算

### 异步一致性

```dart
final userProfile = Computed.async((watch) async {
  final id = watch(userId);
  return await api.fetchUser(id);
});
```

当 `userId` 快速变化时（1 → 2 → 3）：
- 每次变化都触发新请求
- 只有最新请求的结果会被采用
- 旧请求的结果被丢弃（version gating）

---

## 下一步

- 查看 [API 参考](api-reference.md) 了解完整 API
- 阅读 [最佳实践](best-practices.md) 学习推荐模式
- 查看 [常见问题](faq.md) 解决常见疑惑
