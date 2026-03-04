# 🍯 Honeycomb

[English](./README.md) | [简体中文](./README_zh.md)

[![Pub Version](https://img.shields.io/pub/v/honeycomb)](https://pub.dev/packages/honeycomb)
[![Flutter](https://img.shields.io/badge/Flutter-3.27+-blue.svg)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**简洁、类型安全、无需代码生成的 Flutter 状态管理库**

Honeycomb 提供清晰的 **State（状态）** 与 **Effect（事件）** 语义分离，自动依赖追踪，以及强大的 Scope/Override 机制。

---

## ✨ 特性

- 🎯 **脱离 Context 使用** — 全局容器支持，可在纯 Dart 逻辑（Service/Repository）中读写状态
- ⚡ **自动依赖追踪** — Computed 自动追踪 watch 的依赖，从不手动订阅
- 📡 **State vs Effect** — 明确区分可重放状态和一次性事件
- 🎭 **Scope/Override** — 灵活的依赖注入和局部覆盖
- 🔄 **无需 Codegen** — 纯 Dart，无需 build_runner
- 🔒 **类型安全** — 完整的泛型支持
- 🧪 **易于测试** — 状态逻辑与 UI 解耦

---

## 📦 安装

```yaml
dependencies:
  honeycomb: ^1.0.0
```

```bash
flutter pub get
```

---

## 🚀 快速开始

### 1. 定义状态

```dart
import 'package:aegis_honeycomb/honeycomb.dart';

// 可读写的状态
final counterState = StateRef(0);

// 派生状态 (自动追踪依赖)
final doubledCounter = Computed((watch) => watch(counterState) * 2);

// 异步状态
final userProfile = Computed.async((watch) async {
  final userId = watch(currentUserId);
  return await api.fetchUser(userId);
});

// 一次性事件
final toastEffect = Effect<String>();
```

### 2. 提供容器

```dart
// 如果不想依赖 BuildContext，也可以使用全局容器
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

### 3. 在 UI 中使用

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

## 📚 文档

| 文档 | 描述 |
|------|------|
| [新手入门](doc/zh/getting-started.md) | 从零开始学习 Honeycomb |
| [核心概念](doc/zh/core-concepts.md) | 深入理解设计思想 |
| [API 参考](doc/zh/api-reference.md) | 完整 API 文档 |
| [最佳实践](doc/zh/best-practices.md) | 推荐的使用模式 |
| [对比其他库](doc/zh/comparison.md) | 与 Provider/Riverpod/Bloc 对比 |
| [常见问题](doc/zh/faq.md) | FAQ |

---

## 🎯 核心概念速览

### State vs Effect

```dart
// State: 可重放，任何时候读取都能拿到最新值
final userName = StateRef('Guest');

// Effect: 一次性事件，不存储历史
final showToast = Effect<String>(strategy: EffectStrategy.drop);
```

### 依赖追踪

```dart
final fullName = Computed((watch) {
  // 自动追踪 firstName 和 lastName
  return '${watch(firstName)} ${watch(lastName)}';
});
// firstName 或 lastName 变化时，fullName 自动重算
```

### Scope Override

`HoneycombScope` 支持通过 `overrides` 参数在子树中覆盖状态的值。这对于测试（Mock数据）或参数化子组件非常有用。

**工作原理：** 当查找某个 Atom 时，容器会优先使用 `overrides` 中提供的值；如果没找到，再向上查找父容器；最后才根据默认逻辑创建新节点。

```dart
// 局部覆盖状态 (如测试或主题切换)
HoneycombScope(
  overrides: [
    // 强制把 themeState 的值锁定为 dark
    themeState.overrideWith(ThemeData.dark()),
    
    // Or override an async state with mock data
    userProfile.overrideWith(AsyncValue.data(MockUser())),
  ],
  child: DarkModePage(),
)
```

### 处理集合类型 (List / Map) 的不可变更新

在 Honeycomb（以及绝大多数现代响应式框架中），更新 `List` 或 `Map` 等集合类型时，**不要原地修改**（例如 `list.add()`），因为这不会改变对象的内存引用（`oldValue != newValue` 判定为 `false`），从而导致 UI 无法触发更新。

**正确姿势：** 应该通过复制创建全新的集合，推荐使用 `container.update` 语法糖与 Spread（扩展）操作符 `...`：

```dart
// ❌ 错误示范：原地修改（引用未变，不会触发更新）
final currentTodos = container.read(todosRef);
currentTodos.add(newTodo);
container.write(todosRef, currentTodos);

// ✅ 正确示范：使用 update 与 ... 操作符实现不可变更新
container.update(todosRef, (todos) => [...todos, newTodo]); // 增
container.update(todosRef, (todos) => todos.where((e) => e.id != id).toList()); // 删

// Map 更新也是同理：
container.update(userRolesRef, (roles) => {
  ...roles,
  'admin': true, // 新增或覆盖 key
});
```

### 架构解析：一次状态更新的完整生命周期

Honeycomb 采用 **Push-Pull（推拉结合）** 的响应式模型，并运用了多种经典设计模式。当执行如 `container.write(stateRef, 1)`（状态由 0 变 1）时，发生了以下 5 个阶段：

1. **触发更新与享元模式 (Flyweight)**：调用 `write` 时，容器在内部 `_nodes` 字典中查找 Atom 对应的 `StateNode` 实例。这保证了相同的定义始终命中同一个状态节点（享元缓存）。
2. **节点创建与访问者模式 (Visitor)**：如果节点尚未创建，容器通过 `_NodeCreator` 执行 **访问者模式** 双重分派（`Atom.accept(visitor)`）。底层无需繁复的类型判断，直接为 `StateRef` 映射新建 `StateNode`。
3. **推阶段 (Push - Observer)**：节点值更新后，通过 **观察者模式** 遍历所有依赖它的子节点（`ComputeNode` 或 UI 订阅者），向它们发送 `markDirty()` 信号。此处**只标脏，不计算**，彻底解决了菱形依赖（Diamond Dependency）带来的冗余计算问题。
4. **UI 桥接 (Adapter)**：`HoneycombConsumer` 作为订阅者收到脏信号，通过适配器桥接触发自身的 `setState(() {})`，通知 Flutter 引擎在该局部作用域发起重绘排期。
5. **拉阶段 (Pull - Lazy Evaluation)**：Flutter 在下一帧触发 build，UI 调用 `watch(state)` 获取新值。遇到脏标记的节点时，此时才真正进行**惰性求值 (Pull)** 和依赖关系的重新收集。

### 在业务逻辑中使用 (脱离 Context)

有时需要在 Repository、Service 或纯 Dart 逻辑中操作状态。

**1. 创建全局容器实例** (建议放在 `app_globals.dart`)

```dart
// 全局单例容器
final appContainer = HoneycombContainer();
```

**2. 在 Service 中直接使用**

```dart
class AuthService {
  void logout() {
    // 读取状态
    final currentUser = appContainer.read(userState);
    
    // 修改状态
    appContainer.write(userState, null);
    
    // 发送事件 (如通知 UI 跳转)
    appContainer.emit(navigationEffect, '/login');
  }
}
```

**3. 注入到 UI 树**

```dart
void main() {
  runApp(
    HoneycombScope(
      container: appContainer, // 必须注入同一个实例，UI 才能自动响应变化
      child: MyApp(),
    ),
  );
}
```

---

## 🧪 测试

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

## 📊 与其他库对比

| 特性 | Honeycomb | Provider | Riverpod | Bloc |
|------|-----------|----------|----------|------|
| 无 Codegen | ✅ | ✅ | ❌ | ✅ |
| 自动依赖追踪 | ✅ | ❌ | ✅ | ❌ |
| State/Effect 分离 | ✅ | ❌ | ❌ | ✅ |
| Scope Override | ✅ | ✅ | ✅ | ❌ |
| 批量更新 | ✅ | ❌ | ❌ | ✅ |
| 学习曲线 | 低 | 低 | 中 | 高 |

---

## 🤝 贡献

欢迎贡献！请查看 [CONTRIBUTING.md](CONTRIBUTING.md)。

---

## 📄 License

MIT License - 查看 [LICENSE](LICENSE) 文件
