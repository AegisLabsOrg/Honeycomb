import '../honeycomb.dart';
import 'state_node.dart';
import 'compute_node.dart';

/// 急切求值的 Computed 节点
/// 与普通 ComputeNode 不同，上游变化时立即重算，即使没有订阅者
class EagerComputeNode<T> extends StateNode<T> implements Dependency {
  EagerComputeNode(this._container, this._computeFn) : super.lazy() {
    // 立即计算初始值
    _recompute();
  }

  final HoneycombContainer _container;
  final T Function(WatchFn watch) _computeFn;

  /// 当前这一轮计算依赖的上游节点
  final Set<Node> _dependencies = {};

  /// 手动标记为脏并重算 (用于 Hot Reload)
  void markDirty() {
    _recompute();
  }

  @override
  T get value {
    // Eager 模式下值总是最新的，直接返回
    return super.value;
  }

  @override
  void onDependencyChanged(Node dependency) {
    // Eager 模式：无论是否有监听者，立即重算
    _recompute();
  }

  void _recompute() {
    // 循环依赖检测 (复用 ComputeNode 的检测机制)
    if (computingStack.contains(this)) {
      throw CircularDependencyError(
        'Detected circular dependency while computing. '
        'An EagerComputed is watching itself directly or indirectly.',
      );
    }

    final previousNode = ComputeNode.currentlyComputingNode;
    ComputeNode.currentlyComputingNode = this;
    computingStack.add(this);

    try {
      // 清理旧依赖的订阅关系
      for (final dep in _dependencies) {
        dep.removeObserver(this);
      }
      _dependencies.clear();

      // 执行计算函数
      final newValue = _computeFn(<R>(Atom<R> atom) {
        final node = _container.internalGetNode(atom);
        if (_dependencies.add(node)) {
          node.addObserver(this);
        }
        return node.value;
      });

      // 更新值并通知 (即使没人监听也要更新内部值)
      if (!isInitialized || newValue != super.value) {
        super.value = newValue;
      } else {
        // 值没变但需要标记为已初始化
        if (!isInitialized) {
          setValueSilently(newValue);
        }
      }
    } finally {
      computingStack.remove(this);
      ComputeNode.currentlyComputingNode = previousNode;
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
