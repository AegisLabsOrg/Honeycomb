# 与其他库对比

Honeycomb 与 Flutter 主流状态管理方案的对比分析。

---

## 目录

1. [总览](#总览)
2. [vs Provider](#vs-provider)
3. [vs Riverpod](#vs-riverpod)
4. [vs Bloc](#vs-bloc)
5. [vs GetX](#vs-getx)
6. [选型建议](#选型建议)

---

## 总览

| 特性 | Honeycomb | Provider | Riverpod | Bloc |
|------|-----------|----------|----------|------|
| **State/Effect 分离** | ✅ 原生支持 | ❌ | ❌ | ⚠️ 需手动 |
| **自动依赖追踪** | ✅ | ❌ 手动声明 | ✅ | ❌ |
| **类型安全** | ✅ | ⚠️ 运行时 | ✅ 编译时 | ✅ |
| **测试友好** | ✅ | ⚠️ | ✅ | ✅ |
| **Flutter 独立内核** | ✅ | ❌ | ✅ | ✅ |
| **异步原生支持** | ✅ AsyncValue | ⚠️ | ✅ AsyncValue | ⚠️ |
| **热重载支持** | ✅ | ✅ | ✅ | ✅ |
| **学习曲线** | 中 | 低 | 中 | 高 |
| **代码量** | 少 | 少 | 中 | 多 |

---

## vs Provider

### Provider 简介

Provider 是基于 InheritedWidget 的封装，是 Flutter 官方推荐的入门级状态管理方案。

### 关键区别

#### 1. 依赖追踪

```dart
// Provider: 手动声明依赖
class Cart extends ChangeNotifier {
  final Catalog _catalog; // 必须手动传入
  
  Cart(this._catalog);
}

// 必须按顺序声明
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
// Honeycomb: 自动依赖追踪
final cartTotal = Computed((watch) {
  final catalog = watch(catalogState);
  final items = watch(cartItems);
  return items.fold(0.0, (sum, id) => sum + catalog.getPrice(id));
});

// 声明顺序无关
HoneycombScope(
  child: MyApp(),
)
```

#### 2. State vs Effect

```dart
// Provider: 没有原生 Effect 概念
// 通常用 Stream 或手动管理
class AuthNotifier extends ChangeNotifier {
  String? _error;
  
  Future<void> login() async {
    try {
      // ...
    } catch (e) {
      _error = e.toString(); // 这是 State，不是 Event
      notifyListeners();
    }
  }
}
```

```dart
// Honeycomb: 原生 Effect 支持
final authError = Effect<String>(strategy: EffectStrategy.drop);

Future<void> login(HoneycombContainer container) async {
  try {
    // ...
  } catch (e) {
    container.emit(authError, e.toString()); // 一次性事件
  }
}
```

#### 3. 测试

```dart
// Provider: 需要 Widget 环境
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
// Honeycomb: 纯 Dart 测试
test('cart total', () {
  final container = HoneycombContainer();
  container.write(cartItems, ['apple', 'banana']);
  expect(container.read(cartTotal), 5.0);
});
```

### 何时选 Provider

- ✅ 团队刚接触状态管理
- ✅ 小型项目
- ✅ 大量现有 Provider 代码

### 何时选 Honeycomb

- ✅ 需要 State/Effect 分离
- ✅ 复杂的派生状态链
- ✅ 需要纯 Dart 单元测试

---

## vs Riverpod

### Riverpod 简介

Riverpod 是 Provider 作者的"重写版"，修复了 Provider 的多数缺陷。它也是与 Honeycomb 最相似的方案。

### 关键区别

#### 1. 设计理念

```dart
// Riverpod: Provider 是单例+工厂
final userProvider = FutureProvider<User>((ref) async {
  return await api.fetchUser();
});

// Honeycomb: Atom 是描述符
final userProfile = AsyncComputed((watch) async {
  return await api.fetchUser();
});
```

两者在使用上非常相似，核心区别在于：
- Riverpod 的 Provider 是"注册工厂"
- Honeycomb 的 Atom 是"状态描述符"

#### 2. State vs Effect

```dart
// Riverpod: 也没有原生 Effect
// 文档建议用 ref.listen 或 AsyncNotifier

// Honeycomb: 原生 Effect
final toastEffect = Effect<String>(strategy: EffectStrategy.drop);

HoneycombListener(
  effects: [toastEffect],
  listener: (context, container) {
    // 处理
  },
  child: ...,
)
```

#### 3. Family Provider

Riverpod 的杀手锏：

```dart
// Riverpod: 参数化 Provider
final userProvider = FutureProvider.family<User, int>((ref, userId) {
  return api.fetchUser(userId);
});

// 使用
ref.watch(userProvider(123));
ref.watch(userProvider(456)); // 不同实例
```

```dart
// Honeycomb: 目前需要手动管理
final _userCache = <int, AsyncComputed<User>>{};

AsyncComputed<User> userProvider(int userId) {
  return _userCache.putIfAbsent(userId, () {
    return AsyncComputed((watch) => api.fetchUser(userId));
  });
}

// 使用
ref.watch(userProvider(123));
```

> ⚠️ **注意**：Family Provider 是 Riverpod 相对 Honeycomb 的主要优势。我们计划在未来版本支持。

#### 4. 代码生成

```dart
// Riverpod 2.0: 推荐用代码生成
@riverpod
Future<User> user(UserRef ref, int id) async {
  return api.fetchUser(id);
}

// Honeycomb: 纯手写，无代码生成
final userProfile = AsyncComputed((watch) async {
  return api.fetchUser(watch(userId));
});
```

### 对比表

| 特性 | Honeycomb | Riverpod |
|------|-----------|----------|
| State/Effect 分离 | ✅ 原生 | ❌ 需手动 |
| Family Provider | ❌ 手动 | ✅ 原生 |
| 代码生成 | ❌ 无需 | ✅ 推荐 |
| Effect 投递策略 | ✅ drop/bufferN/ttl | ❌ |
| SafeComputed | ✅ Result<T> | ❌ |
| 学习曲线 | 中 | 中-高 |

### 何时选 Riverpod

- ✅ 需要 Family Provider
- ✅ 团队接受代码生成
- ✅ 成熟稳定的方案

### 何时选 Honeycomb

- ✅ 需要 State/Effect 明确分离
- ✅ 需要 Effect 投递策略
- ✅ 不想使用代码生成

---

## vs Bloc

### Bloc 简介

Bloc (Business Logic Component) 是基于 Stream 的模式，强调事件驱动和可预测性。

### 关键区别

#### 1. 架构复杂度

```dart
// Bloc: 需要定义 Event、State、Bloc
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
// Honeycomb: 简洁
final counter = StateRef(0);

void increment(HoneycombContainer c) => c.update(counter, (n) => n + 1);
void decrement(HoneycombContainer c) => c.update(counter, (n) => n - 1);
```

#### 2. 可追溯性

Bloc 的优势：

```dart
// Bloc: 所有变更通过 Event，可轻松实现时间旅行调试
bloc.add(Increment());
bloc.add(Increment());
bloc.add(Decrement());
// 可以回放所有事件
```

```dart
// Honeycomb: 直接写入，需要额外中间件实现追溯
container.write(counter, 10);
```

#### 3. 派生状态

```dart
// Bloc: 通常在 Bloc 内部处理
class CartBloc extends Bloc<CartEvent, CartState> {
  // total 是 State 的一部分
  CartState get state => CartState(
    items: [...],
    total: items.fold(0, ...),
  );
}
```

```dart
// Honeycomb: 自然的派生
final cartItems = StateRef<List<Item>>([]);
final cartTotal = Computed((watch) {
  return watch(cartItems).fold(0.0, (sum, item) => sum + item.price);
});
```

### 对比表

| 特性 | Honeycomb | Bloc |
|------|-----------|------|
| 代码量 | 少 | 多 |
| 可追溯性 | ⚠️ 需中间件 | ✅ 原生 |
| 派生状态 | ✅ 自动 | ⚠️ 手动 |
| 学习曲线 | 中 | 高 |
| 测试便利性 | ✅ | ✅ |

### 何时选 Bloc

- ✅ 需要严格的事件追溯
- ✅ 大型企业项目
- ✅ 团队熟悉 Redux/事件溯源

### 何时选 Honeycomb

- ✅ 追求简洁
- ✅ 大量派生状态
- ✅ 快速迭代的项目

---

## vs GetX

### GetX 简介

GetX 是一个全功能框架，包含状态管理、路由、依赖注入等。

### 关键区别

#### 1. 哲学差异

```dart
// GetX: 魔法多，学习成本低但可预测性差
class Controller extends GetxController {
  var count = 0.obs; // 魔法 .obs
}

Obx(() => Text('${controller.count}')); // 魔法 Obx
```

```dart
// Honeycomb: 显式优于隐式
final counter = StateRef(0);

HoneycombConsumer(
  builder: (_, ref, __) => Text('${ref.watch(counter)}'),
)
```

#### 2. 可测试性

```dart
// GetX: 全局状态，测试隔离困难
Get.put(MyController());

// 不同测试间可能互相影响
```

```dart
// Honeycomb: 容器隔离
test('test 1', () {
  final container = HoneycombContainer(); // 独立实例
  // ...
});

test('test 2', () {
  final container = HoneycombContainer(); // 另一个独立实例
  // ...
});
```

### 何时选 GetX

- ✅ 快速原型
- ✅ 一个人的小项目
- ✅ 喜欢"魔法"

### 何时选 Honeycomb

- ✅ 团队项目
- ✅ 需要可测试性
- ✅ 需要可预测性

---

## 选型建议

### 项目规模

| 规模 | 推荐方案 |
|------|----------|
| 学习 Flutter | Provider |
| 小型项目 | Honeycomb / Riverpod |
| 中型项目 | Honeycomb / Riverpod / Bloc |
| 大型企业项目 | Bloc / Riverpod |

### 团队背景

| 背景 | 推荐方案 |
|------|----------|
| Flutter 新手 | Provider → Honeycomb |
| React 背景 | Riverpod（类似 Jotai） |
| Redux 背景 | Bloc |
| 追求简洁 | Honeycomb |

### 特定需求

| 需求 | 推荐方案 |
|------|----------|
| State/Effect 分离 | **Honeycomb** |
| Family Provider | Riverpod |
| 事件追溯 | Bloc |
| 最少样板代码 | Honeycomb |
| 异步处理 | Honeycomb / Riverpod |

---

## 总结

Honeycomb 的独特价值：

1. **State 与 Effect 的明确分离** — 解决"事件当状态用"的常见 bug
2. **Effect 投递策略** — drop/bufferN/ttl 满足不同场景
3. **简洁的 API** — 无需代码生成，样板代码少
4. **Flutter 独立内核** — 状态逻辑可纯 Dart 测试

如果你的项目有大量"一次性事件"（Toast、导航、埋点），Honeycomb 是理想选择。

---

## 下一步

- 阅读 [快速开始](getting-started.md) 上手使用
- 查看 [常见问题](faq.md) 解答疑惑
