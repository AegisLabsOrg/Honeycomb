import 'dart:async' as async;

import 'honeycomb.dart';
import 'src/state_node.dart';
import 'src/compute_node.dart';
import 'src/async_compute_node.dart';
import 'src/eager_compute_node.dart';
import 'src/safe_compute_node.dart';
import 'src/effect_node.dart';

// --- Visitor Implementation ---

class _NodeCreator implements AtomVisitor<StateNode> {
  _NodeCreator(this.container);
  final HoneycombContainer container;

  @override
  StateNode visitStateRef<T>(StateRef<T> atom) {
    return StateNode<T>(atom.initialValue, debugKey: atom);
  }

  @override
  StateNode visitComputed<T>(Computed<T> atom) {
    return ComputeNode<T>(container, atom.computeFn, debugKey: atom);
  }

  @override
  StateNode visitAsyncComputed<T>(AsyncComputed<T> atom) {
    // 这里 <T> 是 AsyncComputed<T> 的泛型参数 (e.g. int)
    // 返回的 StateNode 必须是 StateNode<AsyncValue<T>>
    return AsyncComputeNode<T>(container, atom.computeFn, debugKey: atom);
  }

  @override
  StateNode visitEagerComputed<T>(EagerComputed<T> atom) {
    return EagerComputeNode<T>(container, atom.computeFn, debugKey: atom);
  }

  @override
  StateNode visitSafeComputed<T>(SafeComputed<T> atom) {
    return SafeComputeNode<T>(container, atom.computeFn, debugKey: atom);
  }

  @override
  StateNode visitEffect<T>(Effect<T> atom) {
    throw UnimplementedError('Effect should not create a StateNode');
  }
}

/// 状态容器，管理所有 Atom 的实例
class HoneycombContainer {
  HoneycombContainer({this.parent});

  final HoneycombContainer? parent;
  final Map<Atom, StateNode> _nodes = {};
  final Map<Effect, EffectNode> _effectNodes = {};

  // 记录 Atom 的 DisposePolicy，用于 autoDispose 检查
  final Map<Atom, DisposePolicy> _disposePolicies = {};

  // 延迟回收定时器
  final Map<Atom, async.Timer> _disposeTimers = {};

  /// 延迟回收的等待时间 (可配置)
  static Duration delayedDisposeDelay = const Duration(seconds: 5);

  // Node Creator Visitor
  late final _NodeCreator _creator = _NodeCreator(this);

  // 处理 Override 的 map，key 是 Atom，value 是 override 的初始值
  final Map<Atom, dynamic> _overrides = {};

  // Batching 支持
  bool _isBatching = false;
  final Set<StateNode> _pendingNotifications = {};

  /// 使用 overrides 创建新的子 Container (Scope)
  factory HoneycombContainer.scoped(
    HoneycombContainer parent, {
    List<Override> overrides = const [],
  }) {
    final container = HoneycombContainer(parent: parent);
    for (var override in overrides) {
      container._overrides[override.atom] = override.value;
    }
    return container;
  }

  /// 内部获取或创建节点 (公开给 ComputeNode 使用，但标记为 internal)
  StateNode<T> internalGetNode<T>(Atom<T> atom) {
    return _getNode(atom);
  }

  /// 内部获取或创建节点
  StateNode<T> _getNode<T>(Atom<T> atom) {
    if (_nodes.containsKey(atom)) {
      return _nodes[atom] as StateNode<T>;
    }

    // 检查是否有 override
    if (_overrides.containsKey(atom)) {
      final overrideValue = _overrides[atom] as T;
      final node = StateNode<T>(overrideValue);
      _nodes[atom] = node;
      return node;
    }

    // 如果没有本地 override，且有 parent，尝试从 parent 获取
    // 注意：这里的逻辑对于 Computed 和 StateRef 可能不同。
    // 对于 StateRef，如果没有 override，我们通常希望共享 parent 的状态。
    // 但如果想实现隔离，可能需要不同的策略。
    // 这里实现默认的 "继承" 策略：如果 parent 有，就由 parent 管理。
    if (parent != null) {
      // 递归查找，如果 parent 也没有，parent 会创建吗？
      // 只要 parent 链上有 anyone 已经创建了，就用它。
      // 如果都没有，应该在哪里创建？
      // 依照 Scope 规则：
      // "查找顺序：当前 Scope → 父 Scope → ... → 根 Container"
      // 这意味着我们应该由下往上找。
      return parent!._getNode(atom);
    }

    // 到达这里说明是根 Container，或者之前的节点都没创建过。
    // 初始化新节点。
    final node = atom.accept<StateNode>(_creator);
    _nodes[atom] = node;

    // 记录 DisposePolicy
    _disposePolicies[atom] = _getDisposePolicy(atom);

    return node as StateNode<T>;
  }

  /// 获取 Atom 的 DisposePolicy
  DisposePolicy _getDisposePolicy(Atom atom) {
    if (atom is StateRef) return atom.disposePolicy;
    if (atom is Computed) return atom.disposePolicy;
    if (atom is AsyncComputed) return atom.disposePolicy;
    if (atom is EagerComputed) return atom.disposePolicy;
    if (atom is SafeComputed) return atom.disposePolicy;
    return DisposePolicy.keepAlive;
  }

  /// 读取 Atom 的当前值
  T read<T>(Atom<T> atom) {
    return _getNode(atom).value;
  }

  /// 使单个 Atom 失效，下次读取时重新计算
  void invalidate<T>(Atom<T> atom) {
    final node = _nodes[atom.key];
    if (node == null) return;

    if (node is ComputeNode) {
      node.markDirty();
    } else if (node is AsyncComputeNode) {
      node.invalidate();
    } else if (node is EagerComputeNode) {
      node.markDirty();
    } else if (node is SafeComputeNode) {
      node.markDirty();
    }
  }

  /// Hot Reload 支持：标记所有 Computed 为脏
  /// 调用后下次读取会重新计算
  void invalidateAllComputed() {
    for (final entry in _nodes.entries) {
      final node = entry.value;
      if (node is ComputeNode) {
        node.markDirty();
      } else if (node is AsyncComputeNode) {
        node.invalidate();
      } else if (node is EagerComputeNode) {
        node.markDirty();
      } else if (node is SafeComputeNode) {
        node.markDirty();
      }
    }
  }

  /// 写入 StateRef 的新值
  void write<T>(StateRef<T> ref, T newValue) {
    final node = _getNode(ref);
    final oldValue = node.isInitialized ? node.value : null;

    if (!node.isInitialized || oldValue != newValue) {
      // 直接设置内部值，不触发通知
      node.setValueSilently(newValue);

      if (_isBatching) {
        // 批量模式：延迟通知
        _pendingNotifications.add(node);
      } else {
        // 立即通知
        node.notifyListeners();
        node.notifyObservers();
      }
    }
  }

  /// 批量更新：在回调执行期间，所有 write 的通知会被延迟到最后一次性触发
  void batch(void Function() updates) {
    if (_isBatching) {
      // 已经在批量模式中，直接执行
      updates();
      return;
    }

    _isBatching = true;
    try {
      updates();
    } finally {
      _isBatching = false;
      // 触发所有延迟的通知
      for (final node in _pendingNotifications) {
        node.notifyListeners();
        node.notifyObservers();
      }
      _pendingNotifications.clear();
    }
  }

  /// 发送一次性事件 (Effect)
  void emit<T>(Effect<T> effect, T payload) {
    _getEffectNode(effect).emit(payload);
  }

  /// 监听一次性事件 (会重放缓冲区事件，如果策略支持)
  async.StreamSubscription<T> on<T>(
    Effect<T> effect,
    void Function(T) callback,
  ) {
    return _getEffectNode(effect).listen(callback);
  }

  EffectNode<T> _getEffectNode<T>(Effect<T> effect) {
    if (_effectNodes.containsKey(effect)) {
      return _effectNodes[effect] as EffectNode<T>;
    }
    if (parent != null) {
      return parent!._getEffectNode(effect);
    }
    final node = EffectNode<T>(effect);
    _effectNodes[effect] = node;
    return node;
  }

  /// 订阅变化
  /// 返回取消订阅的回调
  void Function() subscribe<T>(Atom<T> atom, void Function() listener) {
    final node = _getNode(atom);

    // 取消可能存在的延迟回收定时器
    _disposeTimers[atom]?.cancel();
    _disposeTimers.remove(atom);

    node.addListener(listener);
    return () {
      node.removeListener(listener);
      _tryAutoDispose(atom, node);
    };
  }

  /// 尝试自动回收节点
  void _tryAutoDispose(Atom atom, StateNode node) {
    final policy = _disposePolicies[atom] ?? DisposePolicy.keepAlive;

    if (policy == DisposePolicy.keepAlive) {
      return; // 永不自动回收
    }

    // 检查是否还有订阅者
    if (node.hasListeners || node.hasObservers) {
      return; // 还有人在用
    }

    if (policy == DisposePolicy.autoDispose) {
      // 立即回收
      _disposeNode(atom, node);
    } else if (policy == DisposePolicy.delayed) {
      // 延迟回收
      _disposeTimers[atom]?.cancel();
      _disposeTimers[atom] = async.Timer(delayedDisposeDelay, () {
        // 再次检查是否真的没人用了
        if (!node.hasListeners && !node.hasObservers) {
          _disposeNode(atom, node);
        }
        _disposeTimers.remove(atom);
      });
    }
  }

  /// 回收单个节点
  void _disposeNode(Atom atom, StateNode node) {
    node.dispose();
    _nodes.remove(atom);
    _disposePolicies.remove(atom);
  }

  /// 手动标记某个 Atom 为 keepAlive (阻止 autoDispose)
  void keepAlive(Atom atom) {
    _disposePolicies[atom] = DisposePolicy.keepAlive;
    _disposeTimers[atom]?.cancel();
    _disposeTimers.remove(atom);
  }

  void dispose() {
    // 取消所有延迟回收定时器
    for (final timer in _disposeTimers.values) {
      timer.cancel();
    }
    _disposeTimers.clear();

    for (final node in _nodes.values) {
      node.dispose();
    }
    _nodes.clear();
    _disposePolicies.clear();
    for (final node in _effectNodes.values) {
      node.dispose();
    }
    _effectNodes.clear();
  }
}
