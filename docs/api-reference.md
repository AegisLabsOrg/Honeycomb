# API 参考

完整的 Honeycomb API 文档。

---

## 目录

- [原子 (Atoms)](#原子-atoms)
  - [StateRef](#stateref)
  - [Computed](#computed)
  - [EagerComputed](#eagercomputed)
  - [SafeComputed](#safecomputed)
  - [AsyncComputed](#asynccomputed)
  - [Effect](#effect)
- [容器 (Container)](#容器-container)
- [Flutter 绑定](#flutter-绑定)
- [工具类型](#工具类型)
- [诊断](#诊断)

---

## 原子 (Atoms)

### StateRef

可变状态引用。

```dart
class StateRef<T> extends Atom<T>
```

#### 构造函数

```dart
StateRef(
  T initial, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
  Duration disposeDelay = const Duration(seconds: 5),
})
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `initial` | `T` | 必需 | 初始值 |
| `disposePolicy` | `DisposePolicy` | `keepAlive` | 生命周期策略 |
| `disposeDelay` | `Duration` | `5s` | 延迟回收时间（仅 delayed 策略） |

#### 方法

##### `overrideWith`

```dart
Override overrideWith(T value)
```

创建一个覆盖配置，用于 `HoneycombScope`。

```dart
HoneycombScope(
  overrides: [counter.overrideWith(100)],
  child: ...
)
```

---

### Computed

惰性派生状态。

```dart
class Computed<T> extends Atom<T>
```

#### 构造函数

```dart
Computed(
  T Function(T Function<T>(Atom<T>) watch) compute, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
  Duration disposeDelay = const Duration(seconds: 5),
})
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `compute` | `Function` | 计算函数，通过 `watch` 读取依赖 |
| `disposePolicy` | `DisposePolicy` | 生命周期策略 |

#### 静态工厂

##### `Computed.eager`

```dart
static EagerComputed<T> eager<T>(
  T Function(T Function<T>(Atom<T>) watch) compute, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
})
```

创建急切求值的 Computed，依赖变化时立即重算。

##### `Computed.async`

```dart
static AsyncComputed<T> async<T>(
  Future<T> Function(T Function<T>(Atom<T>) watch) compute, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
})
```

创建异步 Computed，返回 `AsyncValue<T>`。

##### `Computed.safe`

```dart
static SafeComputed<T> safe<T>(
  T Function(T Function<T>(Atom<T>) watch) compute, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
})
```

创建安全 Computed，自动捕获异常返回 `Result<T>`。

---

### EagerComputed

急切派生状态。

```dart
class EagerComputed<T> extends Atom<T>
```

即使没有订阅者，依赖变化时也会立即重新计算。

#### 构造函数

```dart
EagerComputed(
  T Function(T Function<T>(Atom<T>) watch) compute, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
})
```

---

### SafeComputed

安全派生状态，自动捕获异常。

```dart
class SafeComputed<T> extends Atom<Result<T>>
```

#### 构造函数

```dart
SafeComputed(
  T Function(T Function<T>(Atom<T>) watch) compute, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
})
```

返回类型为 `Result<T>`。

---

### AsyncComputed

异步派生状态。

```dart
class AsyncComputed<T> extends Atom<AsyncValue<T>>
```

#### 构造函数

```dart
AsyncComputed(
  Future<T> Function(T Function<T>(Atom<T>) watch) compute, {
  DisposePolicy disposePolicy = DisposePolicy.keepAlive,
})
```

返回类型为 `AsyncValue<T>`。

---

### Effect

一次性事件。

```dart
class Effect<T> extends Atom<T>
```

#### 构造函数

```dart
Effect({
  EffectStrategy strategy = EffectStrategy.drop,
  int bufferSize = 10,
  Duration ttlDuration = const Duration(seconds: 30),
})
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `strategy` | `EffectStrategy` | `drop` | 无监听者时的投递策略 |
| `bufferSize` | `int` | `10` | bufferN 策略的缓冲区大小 |
| `ttlDuration` | `Duration` | `30s` | ttl 策略的过期时间 |

---

## 容器 (Container)

### HoneycombContainer

状态容器。

```dart
class HoneycombContainer
```

#### 构造函数

```dart
HoneycombContainer()
```

##### 命名构造函数

```dart
HoneycombContainer.scoped(
  HoneycombContainer parent, {
  List<Override> overrides = const [],
})
```

创建子容器，可覆盖父容器的状态。

---

#### 方法

##### `read`

```dart
T read<T>(Atom<T> atom)
```

读取原子的当前值。

```dart
final value = container.read(counter);
```

---

##### `write`

```dart
void write<T>(StateRef<T> ref, T value)
```

写入状态值。

```dart
container.write(counter, 42);
```

---

##### `update`

```dart
void update<T>(StateRef<T> ref, T Function(T current) updater)
```

基于当前值更新状态。

```dart
container.update(counter, (n) => n + 1);
```

---

##### `batch`

```dart
void batch(void Function() updates)
```

批量更新，合并所有变更通知。

```dart
container.batch(() {
  container.write(a, 1);
  container.write(b, 2);
  container.write(c, 3);
});
```

---

##### `emit`

```dart
void emit<T>(Effect<T> effect, T payload)
```

发送事件。

```dart
container.emit(toastEffect, 'Hello!');
```

---

##### `on`

```dart
StreamSubscription<T> on<T>(Effect<T> effect, void Function(T) callback)
```

监听事件。

```dart
final subscription = container.on(toastEffect, (message) {
  showToast(message);
});

// 取消监听
subscription.cancel();
```

---

##### `subscribe`

```dart
void Function() subscribe<T>(Atom<T> atom, void Function() listener)
```

订阅原子变化。返回取消订阅函数。

```dart
final unsubscribe = container.subscribe(counter, () {
  print('Counter changed!');
});

// 取消订阅
unsubscribe();
```

---

##### `invalidate`

```dart
void invalidate<T>(Atom<T> atom)
```

使原子缓存失效，下次读取时重新计算。

```dart
container.invalidate(expensiveComputed);
```

---

##### `invalidateAllComputed`

```dart
void invalidateAllComputed()
```

使所有 Computed 缓存失效。用于 Hot Reload。

```dart
container.invalidateAllComputed();
```

---

##### `keepAlive`

```dart
void keepAlive<T>(Atom<T> atom)
```

阻止自动回收。

```dart
container.keepAlive(importantState);
```

---

##### `dispose`

```dart
void dispose()
```

销毁容器及所有状态。

```dart
container.dispose();
```

---

## Flutter 绑定

### HoneycombScope

提供容器给子树。

```dart
class HoneycombScope extends InheritedWidget
```

#### 构造函数

```dart
HoneycombScope({
  Key? key,
  HoneycombContainer? container,
  List<Override> overrides = const [],
  required Widget child,
})
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `container` | `HoneycombContainer?` | 自定义容器，不传则创建新容器 |
| `overrides` | `List<Override>` | 状态覆盖列表 |
| `child` | `Widget` | 子组件 |

#### 静态方法

##### `HoneycombScope.containerOf`

```dart
static HoneycombContainer containerOf(BuildContext context)
```

获取当前 Scope 的容器。

---

### HoneycombConsumer

订阅并响应状态变化。

```dart
class HoneycombConsumer extends StatefulWidget
```

#### 构造函数

```dart
HoneycombConsumer({
  Key? key,
  required Widget Function(
    BuildContext context,
    HoneycombRef ref,
    Widget? child,
  ) builder,
  Widget? child,
})
```

#### 使用

```dart
HoneycombConsumer(
  builder: (context, ref, child) {
    final count = ref.watch(counter);
    return Text('$count');
  },
)
```

---

### HoneycombListener

监听事件和状态变化，不触发重建。

```dart
class HoneycombListener extends StatefulWidget
```

#### 构造函数

```dart
HoneycombListener({
  Key? key,
  List<Effect> effects = const [],
  List<Atom> atoms = const [],
  void Function(BuildContext context, HoneycombContainer container)? listener,
  required Widget child,
})
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `effects` | `List<Effect>` | 要监听的事件列表 |
| `atoms` | `List<Atom>` | 要监听的状态列表 |
| `listener` | `Function` | 变化时的回调 |
| `child` | `Widget` | 子组件 |

#### 使用

```dart
HoneycombListener(
  effects: [toastEffect],
  listener: (context, container) {
    // 处理事件
  },
  child: MyWidget(),
)
```

---

### HoneycombRef

状态访问接口。

```dart
class HoneycombRef
```

#### 方法

##### `watch`

```dart
T watch<T>(Atom<T> atom)
```

读取并订阅原子，变化时触发重建。

##### `read`

```dart
T read<T>(Atom<T> atom)
```

只读取，不订阅。

##### `write`

```dart
void write<T>(StateRef<T> ref, T value)
```

写入状态。

##### `emit`

```dart
void emit<T>(Effect<T> effect, T payload)
```

发送事件。

---

### Context Extensions

```dart
extension HoneycombContextExtension on BuildContext
```

#### 方法

##### `read`

```dart
T read<T>(Atom<T> atom)
```

等同于 `HoneycombScope.containerOf(this).read(atom)`。

##### `write`

```dart
void write<T>(StateRef<T> ref, T value)
```

##### `emit`

```dart
void emit<T>(Effect<T> effect, T payload)
```

---

## 工具类型

### DisposePolicy

```dart
enum DisposePolicy {
  keepAlive,    // 永不自动回收
  autoDispose,  // 无订阅时立即回收
  delayed,      // 延迟回收
}
```

---

### EffectStrategy

```dart
enum EffectStrategy {
  drop,     // 无监听者时丢弃
  bufferN,  // 缓存最近 N 条
  ttl,      // 保留指定时间内的事件
}
```

---

### AsyncValue

```dart
sealed class AsyncValue<T>
```

#### 子类

```dart
class AsyncLoading<T> extends AsyncValue<T>
class AsyncData<T> extends AsyncValue<T>
class AsyncError<T> extends AsyncValue<T>
```

#### 属性

```dart
T? get value           // 数据值（data 状态）
Object? get error      // 错误对象
StackTrace? get stackTrace  // 错误堆栈
bool get isLoading     // 是否加载中
bool get hasError      // 是否有错误
bool get hasValue      // 是否有值
```

#### 方法

##### `when`

```dart
R when<R>({
  required R Function() loading,
  required R Function(T data) data,
  required R Function(Object error, StackTrace? stackTrace) error,
})
```

模式匹配。

##### `maybeWhen`

```dart
R maybeWhen<R>({
  R Function()? loading,
  R Function(T data)? data,
  R Function(Object error, StackTrace? stackTrace)? error,
  required R Function() orElse,
})
```

可选模式匹配。

##### `map`

```dart
AsyncValue<R> map<R>(R Function(T data) mapper)
```

转换数据。

---

### Result

```dart
sealed class Result<T>
```

#### 子类

```dart
class ResultSuccess<T> extends Result<T> {
  final T value;
}

class ResultFailure<T> extends Result<T> {
  final Object error;
  final StackTrace? stackTrace;
}
```

#### 方法

##### `when`

```dart
R when<R>({
  required R Function(T value) success,
  required R Function(Object error, StackTrace? stackTrace) failure,
})
```

---

### Override

覆盖配置。

```dart
class Override {
  final Atom atom;
  final dynamic value;
}
```

通过 `atom.overrideWith(value)` 创建。

---

## 诊断

### HoneycombDiagnostics

诊断工具。

```dart
class HoneycombDiagnostics
```

#### 静态属性

##### `logger`

```dart
static HoneycombLogger logger = DeveloperLogger();
```

设置日志输出器。

##### `logLevel`

```dart
static LogLevel logLevel = LogLevel.warning;
```

设置日志级别。

#### 静态方法

##### `logStateChange`

```dart
static void logStateChange<T>(StateRef<T> ref, T oldValue, T newValue)
```

##### `logComputation`

```dart
static void logComputation<T>(Atom<T> atom, T result)
```

##### `logEffect`

```dart
static void logEffect<T>(Effect<T> effect, T payload)
```

##### `logError`

```dart
static void logError(String message, Object error, StackTrace? stackTrace)
```

---

### LogLevel

```dart
enum LogLevel {
  verbose,
  info,
  warning,
  error,
  none,
}
```

---

### HoneycombLogger

日志接口。

```dart
abstract class HoneycombLogger {
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  });
}
```

#### 内置实现

- `DeveloperLogger` — 使用 `dart:developer.log()`（默认）
- `SilentLogger` — 不输出任何日志

```dart
// 关闭日志
HoneycombDiagnostics.logger = SilentLogger();

// 只显示错误
HoneycombDiagnostics.logLevel = LogLevel.error;
```

---

## Selector 扩展

### AtomSelect Extension

```dart
extension AtomSelect<T> on Atom<T>
```

#### 方法

##### `select`

```dart
Atom<R> select<R>(
  R Function(T value) selector, {
  bool Function(R prev, R next)? equals,
})
```

选择状态的一部分。可自定义比较函数。

```dart
final userName = userState.select((u) => u.name);
```

##### `selectMany`

```dart
Atom<R> selectMany<R>(R Function(T value) selector)
```

选择集合，使用深度比较。

```dart
final todoIds = todoListState.selectMany((list) => list.map((t) => t.id).toList());
```

##### `where`

```dart
Atom<T> where(bool Function(T value) predicate)
```

过滤，只有满足条件时才更新。

```dart
final completedTodo = todoState.where((t) => t.isCompleted);
```
