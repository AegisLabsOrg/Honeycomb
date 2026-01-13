# 状态管理设计思路（设计总结）

> **状态管理 = 带一致性语义的缓存（State） + 依赖追踪（Dependency Graph） + 调度器（Scheduler） + 生命周期管理（Lifecycle） + 副作用模型（Effects） + 可观测性（Observability）**。
>
> UI 绑定（Widget/Element 生命周期）只是其中一层适配器，不应与内核耦合。

---

## 1. 核心分层（强烈建议）

### 1) 内核（UI 无关）
负责：
- 缓存最新值（replay latest）
- 派生/依赖追踪
- 一致性与调度（批处理、事务、拓扑顺序）
- 生命周期（autoDispose/keepAlive、资源回收）
- 异步竞争处理（generation/version）
- override/scope（测试/多环境）

### 2) UI 适配层（Flutter binding）
负责：
- mount 时订阅、dispose 时取消订阅
- 将“值变化”转换成局部 rebuild 或副作用回调
- 处理 `didUpdateWidget` / `didChangeDependencies` 时的订阅更新

> 结论：内核应该可在非 UI 环境复用（测试/后台任务/服务端），UI 层只是 adapter。

---

## 2. 最重要的语义分离：State vs Event/Effect

### State（可重放）
语义：任何时候订阅都能**立刻拿到最新值**；late subscriber 不需要历史通知。
- 典型用途：UI 渲染、派生计算、缓存结果
- 核心约束：订阅时必须 “emit current” 一次（replay latest）

### Event / Effect（一次性/副作用）
语义：默认**不重放**；如需重放必须显式选择策略。
- 典型用途：toast、导航、弹窗、埋点、一次性提示、命令式动作
- 建议内建策略（用类型或配置明确化）：
  - `drop`：无人订阅即丢（默认安全）
  - `bufferN`：环形缓冲 N 条
  - `ttl`：保留最近 X 秒
  - `cursor/offset`：按订阅者游标精确消费（成本最高、语义最强）

> 你之前遇到的“组件不存在时通知暂存/什么时候消费”的难题，根因通常是把 **event 当成 state**。

---

## 3. 一致性模型（决定调度器与可预测性）

建议默认：**批处理一致（batched consistency）**。

### 写入与传播
- 写入：只标记 dirty，不立即级联重算
- flush：在 microtask/frame/显式 `flush()` 时统一重算

### 推荐承诺（设计目标）
- 同一轮 flush 内读取视图一致（snapshot/version）
- 同一节点一轮最多重算一次（去重）
- 支持“事务”：多次写合并为一次传播

备选：同步一致（实现更简单，但更容易抖动/重复计算/顺序敏感）。

---

## 4. 依赖追踪（实现“最小重算集”的关键）

必须回答：

### 依赖边如何产生？
- 动态收集：在 build/compute 期间通过 `watch()` 记录依赖边
- 静态声明：通过元数据/生成方式预先声明依赖（不依赖特定技术）

### 依赖边如何维护？
- 每次 build/compute 完成，用“新依赖集”替换旧依赖集
- 解绑旧边、绑定新边（避免依赖关系漂移导致泄漏与错误传播）

### 传播规则
- 上游变更 → 下游标 dirty → 调度器统一重算（拓扑顺序）

目标：避免“全局广播”，做到**最小传播/最小重建**。

---

## 5. 生命周期（缓存与资源的边界）

### 缓存型 State
- 无人订阅时可保留 latest（更像缓存）

### 资源型节点（stream/timer/socket/db 等）
- 必须支持 `onDispose`
- autoDispose 推荐采用 **延迟 sweep**（防抖回收）
- 提供 keepAlive / 引用计数策略

实用原则：
- State 的生命周期偏“缓存”
- Effect/IO 的生命周期偏“资源”

---

## 6. Scope/Container 层级设计

### 层级关系
- **根 Container**：应用级单例，持有全局状态
- **子 Scope**：可嵌套，继承父 Scope 的状态访问能力
- **隔离边界**：子 Scope 销毁不影响父 Scope

### Override 规则
```
查找顺序：当前 Scope → 父 Scope → ... → 根 Container
Override 优先级：最近的 Scope 优先
```

典型用途：
- 测试时 mock 依赖
- 多租户/多账号场景隔离
- 页面级状态隔离（如对话框内部状态）

### 跨 Scope 依赖处理
- 子 Scope 可 watch 父 Scope 的状态（向上依赖）
- 父 Scope **不应**依赖子 Scope（避免生命周期倒挂）
- 子 Scope 销毁时，自动解绑其持有的所有订阅

### API 示例
```dart
final rootContainer = Container();

// 创建子 Scope，override 特定状态
final testScope = rootContainer.createScope(
  overrides: [
    userRepository.overrideWith(MockUserRepository()),
  ],
);

// Scope 销毁时自动清理
testScope.dispose();
```

---

## 7. 异步语义（必须从第一天就设计）

通用做法：**generation/version gating**。

- 每次触发重算生成 `generationId`
- Future/Stream 完成时仅在 generation 匹配时提交结果
- 过期结果丢弃或记录（用于诊断）

目标：消灭“旧结果覆盖新状态”的竞态。

---
## 8. 异步状态表达（AsyncValue）

异步操作天然有三态，建议内建统一类型：

```dart
sealed class AsyncValue<T> {
  const factory AsyncValue.loading() = AsyncLoading<T>;
  const factory AsyncValue.data(T value) = AsyncData<T>;
  const factory AsyncValue.error(Object error, StackTrace stackTrace) = AsyncError<T>;
}
```

### 状态转换规则
- 初始/刷新 → `loading`（可选保留旧值：`loading(previous: oldValue)`）
- 成功 → `data(value)`
- 失败 → `error(e, stackTrace)`

### 便捷方法
```dart
asyncValue.when(
  loading: () => CircularProgressIndicator(),
  data: (value) => Text(value),
  error: (e, st) => ErrorWidget(e),
);

// 或提供默认值
asyncValue.valueOrNull;
asyncValue.valueOr(defaultValue);
asyncValue.requireValue; // 无值时抛异常
```

### Computed 错误传播
- Computed 计算抛异常时，下游节点收到 `AsyncError`
- 支持 `onError` 回调或 `.catchError()` 链式处理
- 错误不应静默吞掉，至少 debug 模式要上报

---

## 9. 选择性重建（Selector）

当 State 是复杂对象时，需要支持只监听部分字段变化：

### API 设计
```dart
// 只在 user.name 变化时重建
final userName = watch(userState.select((u) => u.name));

// 多字段组合
final displayInfo = watch(userState.select((u) => (u.name, u.avatar)));

// 自定义比较器
final items = watch(listState.select(
  (list) => list.length,
  equals: (a, b) => a == b,
));
```

### 实现要点
- Selector 产出的值用 `==` 或自定义比较器判断是否变化
- 只有 selector 结果变化时才触发下游重算/重建
- Selector 应该是纯函数，无副作用

### 常见 Selector 工具
```dart
// 内置常用 selector
state.select((s) => s.field);           // 单字段
state.selectMany((s) => [s.a, s.b]);    // 多字段（任一变化触发）
state.where((s) => s.isValid);          // 条件过滤
```

---

## 10. Computed 求值策略

### 惰性求值（Lazy，推荐默认）
- 只有被 watch 时才计算
- 无人订阅时不消耗资源
- 首次读取可能有计算延迟

### 急切求值（Eager）
- 上游变化立即重算
- 适合需要"始终保持最新"的场景（如后台同步）
- 资源消耗更高

### API 示例
```dart
// 默认惰性
final total = Computed((watch) => watch(price) * watch(quantity));

// 显式急切
final alwaysFresh = Computed.eager((watch) => expensiveCalc(watch(source)));
```

### 建议
- 默认惰性，满足 90% 场景
- 提供 `.eager()` 或配置项切换
- 急切模式仍应参与批处理，避免过度计算

---

## 11. API 设计建议（最小可扩展内核）

建议至少具备：
- `State<T>`：可写、可读、replay latest
- `Computed<T>`：派生状态，带依赖追踪
- `Effect<E>`：事件流（明确投递语义）
- `Scope/Container`：缓存槽位、override、生命周期边界
- `Scheduler`：dirty 标记、flush、去重、拓扑顺序

访问语义建议明确分为三类：
- `watch`：建立依赖（用于派生与 UI 重建）
- `read`：不建依赖（一次性读取）
- `listen`：不重建，仅副作用回调

---

## 12. 可观测性（决定能否长期维护/优化）

建议内建诊断钩子（至少 debug 模式）：
- 本轮 flush 重算了哪些节点、耗时
- 某个重建/重算的原因链路（哪个依赖变了）
- dirty 传播路径
- 异步过期结果统计

> 工程上，"解释为什么更新了"往往比"更快 5%"更有价值。

---

## 13. Flutter UI 适配层细节

### 生命周期映射
| Flutter 生命周期 | 状态管理操作 |
|-----------------|-------------|
| `initState` | 初始化订阅（subscribe） |
| `didChangeDependencies` | 检查 InheritedWidget 变化，必要时重新订阅 |
| `didUpdateWidget` | 检查 widget 参数变化，必要时更新订阅 |
| `build` | 执行 watch，收集依赖 |
| `dispose` | 取消所有订阅（unsubscribe） |

### Hot Reload 处理
- Hot reload 时状态默认**保留**（不重置）
- Computed 重新收集依赖（因为计算函数可能变了）
- 提供 `debugResetOnHotReload` 开关用于调试

### 推荐 Widget 封装
```dart
class HoneycombBuilder<T> extends StatefulWidget {
  final StateRef<T> stateRef;
  final Widget Function(BuildContext context, T value) builder;
  
  // 可选：精细控制重建
  final bool Function(T prev, T next)? shouldRebuild;
}

// 或使用 Hook 风格（需 flutter_hooks）
Widget build(BuildContext context) {
  final count = useWatch(counterState);
  return Text('$count');
}
```

### Context 传递
- 通过 `InheritedWidget` 向下传递 Scope/Container
- 支持 `context.read()` / `context.watch()` 扩展方法
- 子树可通过 `HoneycombScope` 创建局部 override

---

## 14. 设计自检清单（开工前必过）

1. late subscriber 是否无需历史通知即可正确渲染？（State replay latest）
2. Event 是否有明确投递语义？（drop/buffer/ttl/cursor）
3. 是否定义了 flush 边界与一致性承诺？（batched / transaction）
4. 是否能做到最小重算集？（依赖追踪与传播）
5. 异步是否不会被过期结果污染？（generation/version）
6. 生命周期是否能稳定回收资源且不抖动？（sweep + keepAlive）
7. 是否能解释"为什么更新了"？（observability）
8. Computed 错误是否有明确处理路径？（AsyncValue/onError）
9. 复杂对象是否支持选择性重建？（Selector）
10. Scope 层级与 override 规则是否清晰？（继承/隔离）

---

## 15. 后续建议：实现路线

### Phase 0（API 验证，强烈建议）

在写代码之前，先用伪代码写出典型用例，验证 API 人体工学：

```dart
// 用例1：简单计数器
final counter = State(0);
counter.value++;
watch(counter); // 在 UI 中使用

// 用例2：异步加载列表 + 刷新
final userList = Computed.async((watch) async {
  final page = watch(currentPage);
  return await api.fetchUsers(page: page);
});
// UI 中
userList.when(
  loading: () => Spinner(),
  data: (users) => ListView(users),
  error: (e, st) => RetryButton(),
);

// 用例3：表单多字段联动校验
final email = State('');
final password = State('');
final isFormValid = Computed((watch) {
  return watch(email).contains('@') && watch(password).length >= 8;
});

// 用例4：跨页面共享 + 局部 override
// 全局
final themeState = State(ThemeMode.light);
// 某个页面局部 override
HoneycombScope(
  overrides: [themeState.overrideWith(ThemeMode.dark)],
  child: DarkPage(),
);

// 用例5：一次性 toast 事件
final toastEvent = Effect<String>(strategy: EffectStrategy.drop);
toastEvent.emit('保存成功');
// UI 中
listen(toastEvent, (msg) => showToast(msg));
```

### Phase 1-6（渐进实现）

1. 只实现 `State<T>`（replay latest）+ 订阅生命周期（subscribe/unsubscribe）
2. 加入 `Computed<T>`（依赖追踪 + dirty）
3. 引入 `Scheduler`（batching/flush 去重 + 拓扑顺序）
4. 加入 `Effect<E>`（drop 与 bufferN 至少一个）
5. 加入 async generation（Future/Stream 派生）+ `AsyncValue`
6. 做最小可观测性（recompute reason / perf）
7. Flutter UI 适配层（`HoneycombBuilder` / `HoneycombScope`）
8. Selector 支持
9. DevTools 集成（可选）
