# 新手入门

本指南将带你从零开始学习 Honeycomb 状态管理库。

---

## 目录

1. [安装](#安装)
2. [第一个示例：计数器](#第一个示例计数器)
3. [理解核心概念](#理解核心概念)
4. [使用派生状态](#使用派生状态)
5. [处理异步数据](#处理异步数据)
6. [使用事件](#使用事件)
7. [下一步](#下一步)

---

## 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  honeycomb: ^1.0.0
```

然后运行：

```bash
flutter pub get
```

---

## 第一个示例：计数器

让我们创建一个简单的计数器应用来理解 Honeycomb 的基本用法。

### Step 1: 定义状态

创建 `lib/states.dart`：

```dart
import 'package:honeycomb/honeycomb.dart';

// 定义一个可读写的状态
final counterState = StateRef(0);
```

`StateRef` 是 Honeycomb 中最基础的状态容器。它：
- 持有一个值
- 任何时候读取都能拿到最新值
- 值变化时通知所有订阅者

### Step 2: 设置 HoneycombScope

在 `lib/main.dart` 中：

```dart
import 'package:flutter/material.dart';
import 'package:honeycomb/honeycomb.dart';
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

`HoneycombScope` 通过 Flutter 的 InheritedWidget 机制向下传递 `HoneycombContainer`，让子组件可以访问状态。

### Step 3: 读取和修改状态

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
            // 使用 ref.watch 读取状态，并在变化时重建
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
          // 获取容器并修改状态
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

**关键点：**
- `ref.watch(atom)` — 读取值并订阅变化，值变化时 Widget 自动重建
- `container.read(atom)` — 只读取值，不订阅
- `container.write(stateRef, newValue)` — 写入新值

---

## 理解核心概念

### 三种访问模式

| 方法 | 用途 | 是否订阅 |
|------|------|---------|
| `ref.watch(atom)` | 在 UI 中读取，需要响应变化 | ✅ |
| `container.read(atom)` | 一次性读取（如事件处理） | ❌ |
| `container.write(ref, value)` | 写入新值 | - |

### 为什么分开 watch 和 read？

```dart
// ❌ 不好：在事件处理中用 watch 会导致不必要的订阅
onPressed: () {
  final count = ref.watch(counterState); // 错误！
}

// ✅ 好：事件处理中用 read
onPressed: () {
  final container = HoneycombScope.readOf(context);
  final count = container.read(counterState); // 正确
}
```

---

## 使用派生状态

`Computed` 用于创建从其他状态派生的值，并自动追踪依赖。

```dart
// states.dart
final counterState = StateRef(0);

// 派生状态：计数器的两倍
final doubledCounter = Computed((watch) {
  return watch(counterState) * 2;
});

// 派生状态：是否为偶数
final isEven = Computed((watch) {
  return watch(counterState) % 2 == 0;
});

// 组合多个状态
final firstName = StateRef('John');
final lastName = StateRef('Doe');

final fullName = Computed((watch) {
  return '${watch(firstName)} ${watch(lastName)}';
});
```

**Computed 的特点：**
- ✅ 惰性求值 — 只有被 watch 时才计算
- ✅ 自动缓存 — 依赖不变时不重算
- ✅ 自动追踪 — 不需要手动声明依赖

在 UI 中使用：

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

## 处理异步数据

使用 `Computed.async` 处理异步操作：

```dart
final selectedUserId = StateRef(1);

final userProfile = Computed.async((watch) async {
  final userId = watch(selectedUserId);
  
  // 模拟 API 请求
  await Future.delayed(const Duration(seconds: 1));
  
  return await api.fetchUser(userId);
});
```

`Computed.async` 返回 `AsyncValue<T>`，包含三种状态：

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

### AsyncValue 方法

```dart
asyncValue.when(loading: ..., data: ..., error: ...);  // 模式匹配
asyncValue.valueOrNull;   // 获取值或 null
asyncValue.isLoading;     // 是否加载中
```

---

## 使用事件

`Effect` 用于一次性事件，如 Toast、导航、埋点等。

### 定义事件

```dart
// 一次性事件，无人监听时丢弃
final toastEffect = Effect<String>(strategy: EffectStrategy.drop);

// 带缓冲区的事件，保留最近 N 条
final notificationEffect = Effect<Notification>(
  strategy: EffectStrategy.bufferN,
  bufferSize: 10,
);
```

### 发送事件

```dart
// 使用 context 扩展
context.emit(toastEffect, 'Operation successful!');

// 或者通过容器
container.emit(toastEffect, 'Hello!');
```

### 监听事件

使用 `HoneycombListener` Widget：

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

## 下一步

恭喜！你已经掌握了 Honeycomb 的基础用法。接下来可以：

- 📖 阅读 [核心概念](core-concepts.md) 深入理解设计思想
- 🎯 查看 [最佳实践](best-practices.md) 了解推荐的使用模式
- 📚 浏览 [API 参考](api-reference.md) 了解完整 API
- 🔍 运行 [示例应用](../example) 查看更多用例

---

## 完整示例代码

```dart
import 'package:flutter/material.dart';
import 'package:honeycomb/honeycomb.dart';

// 1. 定义状态
final counterState = StateRef(0);
final doubledCounter = Computed((watch) => watch(counterState) * 2);
final toastEffect = Effect<String>();

void main() {
  runApp(
    // 2. 提供容器
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
        // 3. 使用状态
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
