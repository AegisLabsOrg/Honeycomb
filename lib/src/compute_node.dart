import '../honeycomb.dart';
import 'state_node.dart';

/// 全局变量：当前正在计算的 Computed 节点
/// 用于在 watch() 时捕获依赖关系
Dependency? _currentlyComputingNode;

/// 正在计算的节点栈，用于循环依赖检测
/// 使用 internal getter 让其他 compute nodes 访问
final Set<Dependency> _computingStack = {};

/// 获取计算栈 (供 EagerComputeNode 等使用)
Set<Dependency> get computingStack => _computingStack;

/// 循环依赖异常
class CircularDependencyError extends Error {
  CircularDependencyError(this.message);
  final String message;
  @override
  String toString() => 'CircularDependencyError: $message';
}

/// 派生状态节点
class ComputeNode<T> extends StateNode<T> implements Dependency {
  ComputeNode(this._container, this._computeFn) : super.lazy() {
    _isDirty = true;
  }

  static Dependency? get currentlyComputingNode => _currentlyComputingNode;
  static set currentlyComputingNode(Dependency? node) =>
      _currentlyComputingNode = node;

  final HoneycombContainer _container;
  final T Function(WatchFn watch) _computeFn;

  /// 当前这一轮计算依赖的上游节点
  final Set<Node> _dependencies = {};

  /// 是否 "脏" 了，需要重新计算
  bool _isDirty = false;

  /// 手动标记为脏 (用于 Hot Reload)
  void markDirty() {
    _isDirty = true;
  }

  /// 初始化时是脏的吗？
  /// 实际上 super 构造函数已经计算了一次初始值，所以初始是干净的。
  /// 但如果是 lazy 且没有初始值，可能需要处理。
  /// 这里通过 _isDirty 来控制缓存。实际上如果有人读，我们才重算。

  // 覆盖父类的 value getter，实现惰性求值和依赖追踪
  @override
  T get value {
    // 2. 如果脏了，重新计算
    if (_isDirty) {
      _recompute();
    }

    return super.value;
  }

  // 作为依赖者，当上游变化时
  @override
  void onDependencyChanged(Node dependency) {
    if (!_isDirty) {
      _isDirty = true;
      // 通知我的下游，我也可能变了（甚至不用重算，先标记脏）
      // 这里的策略是：
      // - 如果我有监听者 (UI)，我必须立即重算来看看值变没变，如果变了通知 UI。
      // - 如果我没人监听 (Lazy)，我就只标记 dirty，等下次有人读我。

      if (hasListeners || observers.isNotEmpty) {
        // 急切模式：为了通知 UI，必须求值
        _recompute();
      } else {
        // 惰性模式：只标记，不计算，也不用通知下游（因为下游也没人在听）
        // 等下一轮有人读我时自然会发现我是脏的。
      }
    }
  }

  void _recompute() {
    // 循环依赖检测
    if (_computingStack.contains(this)) {
      throw CircularDependencyError(
        'Detected circular dependency while computing. '
        'A Computed is watching itself directly or indirectly.',
      );
    }

    final previousNode = _currentlyComputingNode;
    _currentlyComputingNode = this;
    _computingStack.add(this);

    try {
      // 在计算前，我们要准备好收集新一轮的依赖
      // 清理旧依赖的订阅关系（避免内存泄漏和过时依赖）
      for (final dep in _dependencies) {
        dep.removeObserver(this);
      }
      _dependencies.clear();

      // 执行计算函数，传入闭包实现的 watch
      final newValue = _computeFn(<R>(Atom<R> atom) {
        final node = _container.internalGetNode(atom);
        // Explicit dependency registration
        if (_dependencies.add(node)) {
          node.addObserver(this);
        }
        // Return value without implicit tracking logic inside node.value
        return node.value;
      });

      // 计算完成了，现在 _dependencies 里是最新的依赖

      // 更新值
      if (!isInitialized || newValue != super.value) {
        super.value = newValue;
      }

      // 无论值变没变，我都干净了
      _isDirty = false;
    } finally {
      _computingStack.remove(this);
      _currentlyComputingNode = previousNode;
    }
  }

  //  static T _tracker<T>(Atom<T> atom) { ... removed ... }

  @override
  void dispose() {
    // 解除所有上游依赖
    for (final dep in _dependencies) {
      dep.removeObserver(this);
    }
    _dependencies.clear();
    super.dispose();
  }
}
