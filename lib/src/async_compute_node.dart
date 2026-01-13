import 'dart:async';
import 'package:flutter/foundation.dart';

import '../honeycomb.dart';
import 'state_node.dart';
import 'compute_node.dart';

/// 管理异步计算的节点
class AsyncComputeNode<T> extends StateNode<AsyncValue<T>>
    implements Dependency {
  AsyncComputeNode(this._container, this._computeFn)
    : super(const AsyncValue.loading());

  final HoneycombContainer _container;
  final Future<T> Function(WatchFn watch) _computeFn;

  // 依赖追踪辅助
  final Set<Node> _dependencies = {};
  int _dependencyVersion = 0;
  bool _ensureStarted = false;

  /// 让节点失效并重新计算 (用于 Hot Reload)
  void invalidate() {
    _recompute();
  }

  @override
  AsyncValue<T> get value {
    if (!_ensureStarted) {
      _ensureStarted = true;
      // 使用 microtask 避免读操作直接触发副作用导致死锁或 re-entrancy 问题?
      // 或者是直接同步触发?
      // 如果是 Lazy，第一次读的时候触发。
      // 因为 _recompute 会修改 value (notifyListeners)，
      // 在 get value 中修改 value 是危险的 (e.g. build phase).
      // 但 AsyncValue 通常就是 update state.

      // 更好的方式：Schedule microtask to start computing.
      scheduleMicrotask(_recompute);
    }
    return super.value;
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (!_ensureStarted) {
      _ensureStarted = true;
      scheduleMicrotask(_recompute);
    }
  }

  @override
  void onDependencyChanged(Node dependency) {
    // 依赖变化时，标记为 loading 并重新计算
    _recompute();
  }

  void _recompute() {
    // 防抖/去重逻辑：如果已经在 loading 且是同一个触发源...
    // 这里简单处理：每次变化都重新跑一次

    // 更新状态为 Loading (保留上一次的数据作为 previous)
    value = AsyncValue.loading(previous: value.valueOrNull);

    // 增加版本号，用于丢弃过期的 Future 结果 (Race Condition 处理)
    final currentVersion = ++_dependencyVersion;

    _runCompute(currentVersion);
  }

  Future<void> _runCompute(int version) async {
    // 清理旧依赖 (Computed 逻辑)
    // 注意：这里跟 ComputeNode 很像，可能有代码复用空间
    // 但因为是 Future，执行期间可能会去读取依赖
    // Honeycomb 约定：watch 必须同步执行才能追踪？
    // AsyncComputed 的 computeFn 是 `Future<T> Function(watch)`.
    // 用户调用的 watch 必须发生在 await 之前才能被追踪到。
    // 如果用户 `await future; watch(atom);`，那么这个 watch 发生在 Future microtask 中，
    // 全局变量 `_currentlyComputingNode` 可能已经变了或空了。
    // 所以：Honeycomb 强制要求 watch 必须是同步收集。

    // 开始收集依赖
    final previousNode = ComputeNode.currentlyComputingNode;
    ComputeNode.currentlyComputingNode = this;

    // 清除旧依赖关系
    for (final dep in _dependencies) {
      dep.removeObserver(this);
    }
    _dependencies.clear();

    try {
      // 执行用户函数，得到 Future
      // 注意：这里用户函数体内的同步部分会执行，收集依赖
      final future = _computeFn(<R>(Atom<R> atom) {
        final node = _container.internalGetNode(atom);
        if (_dependencies.add(node)) {
          node.addObserver(this);
        }
        return node.value;
      });

      // 停止收集依赖（同步部分结束）
      ComputeNode.currentlyComputingNode = previousNode;

      // 等待结果
      final result = await future;

      // 如果版本号变了，说明有新计算开始了，这个结果丢弃
      if (version != _dependencyVersion) return;

      value = AsyncValue.data(result);
    } catch (e, s) {
      // 停止收集依赖 (如果在同步执行阶段抛错)
      if (ComputeNode.currentlyComputingNode == this) {
        ComputeNode.currentlyComputingNode = previousNode;
      }

      if (version != _dependencyVersion) return;

      value = AsyncValue.error(e, s);
    }
  }

  @override
  void dispose() {
    for (final dep in _dependencies) {
      dep.removeObserver(this);
    }
    _dependencies.clear();
    super.dispose();
  }
}
