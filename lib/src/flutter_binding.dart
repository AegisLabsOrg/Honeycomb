import 'dart:async';
import 'package:flutter/widgets.dart';
import '../honeycomb.dart';

/// 用于在 Widget 树中向下传递 [HoneycombContainer]
class HoneycombScope extends InheritedWidget {
  HoneycombScope({
    super.key,
    required super.child,
    this.overrides = const [],
    HoneycombContainer? container,
  }) : container =
           container ??
           HoneycombContainer.scoped(
             HoneycombContainer(), // Default root container
             overrides: overrides,
           );

  final List<Override> overrides;
  final HoneycombContainer container;

  static HoneycombContainer of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HoneycombScope>();
    if (scope == null) {
      throw StateError(
        'No HoneycombScope found in context. Wrap your app in HoneycombScope.',
      );
    }
    return scope.container;
  }

  /// 仅获取 Container 而不订阅 (用于 read/emit)
  static HoneycombContainer readOf(BuildContext context) {
    // getInheritedWidgetOfExactType (O(1)) vs dependOn... (Register dependency)
    // 我们只需要查找，不需要 InheritedWidget 本身的更新通知
    final element = context
        .getElementForInheritedWidgetOfExactType<HoneycombScope>();
    if (element == null) {
      throw StateError(
        'No HoneycombScope found in context. Wrap your app in HoneycombScope.',
      );
    }
    return (element.widget as HoneycombScope).container;
  }

  @override
  bool updateShouldNotify(HoneycombScope oldWidget) {
    // Container 实例通常不变，变的是里面的 Atom
    // 但如果 overrides 变了（比如热重载），我们可能需要替换 Container？
    // 为了简单起见 Phase 5 暂时认为 Container 引用不变
    return container != oldWidget.container;
  }
}

/// 暴露给 Widget 的交互接口
abstract class WidgetRef {
  /// 监听 Atom 并在变化时重建 Widget
  T watch<T>(Atom<T> atom);

  /// 读取 Atom 的值 (不监听)
  T read<T>(Atom<T> atom);

  /// 发送效果事件
  void emit<T>(Effect<T> effect, T payload);

  /// 订阅效果事件 (通常在 StatefulWidget 的 initState/dispose 中管理，或者在 build 中使用副作用钩子)
  /// 注意：在 build 中直接 listen 并不安全，因为每次 build 都会触发。
  /// 所以这里暂时不暴露 listen，建议使用 HoneycombListener Widget。
}

/// 类似 Consumer 或 Builder，提供 WidgetRef
class HoneycombConsumer extends StatefulWidget {
  const HoneycombConsumer({super.key, required this.builder, this.child});

  final Widget Function(BuildContext context, WidgetRef ref, Widget? child)
  builder;
  final Widget? child;

  @override
  State<HoneycombConsumer> createState() => _HoneycombConsumerState();
}

class _HoneycombConsumerState extends State<HoneycombConsumer>
    implements WidgetRef {
  late final HoneycombContainer _container;

  // 维护当前 Widget 依赖的 Atom 集合，用于清理旧订阅
  final Set<Atom> _dependencies = {};
  // 记录清理回调
  final Map<Atom, VoidCallback> _disposers = {};

  // 用来标记是否在 build 阶段
  bool _isBuilding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 获取最近的 Container
    _container = HoneycombScope.of(context);
  }

  /// Hot Reload 支持：重新收集依赖
  @override
  void reassemble() {
    super.reassemble();
    // Hot Reload 时重新订阅所有依赖
    // 因为 Computed 的计算函数可能变了
    _invalidateAllComputedDependencies();
  }

  /// 让所有 Computed 类型的依赖重新计算
  void _invalidateAllComputedDependencies() {
    // 标记需要重建
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _unsubscribeAll();
    super.dispose();
  }

  void _unsubscribeAll() {
    for (final dispose in _disposers.values) {
      dispose();
    }
    _disposers.clear();
    _dependencies.clear();
  }

  @override
  T read<T>(Atom<T> atom) {
    return _container.read(atom);
  }

  @override
  void emit<T>(Effect<T> effect, T payload) {
    _container.emit(effect, payload);
  }

  @override
  T watch<T>(Atom<T> atom) {
    // 只能在 build 期间调用
    // 或者我们放宽限制，允许在 didChangeDependencies 等调用?
    // 通常 watch 是为了 build 使用的。

    // 1. 注册依赖
    if (!_dependencies.contains(atom)) {
      // 这是一个新依赖
      _dependencies.add(atom);

      // 建立订阅
      // 注意：StateNode 也是 Dependency，但这里我们是 Widget State。
      // HoneycombContainer.subscribe 返回的是 cancel callback。
      final cancel = _container.subscribe(atom, _onDependencyChanged);
      _disposers[atom] = cancel;
    }

    // 2. 返回值
    return _container.read(atom);
  }

  void _onDependencyChanged() {
    // 当依赖变化时回调
    // 如果已经在 build 中 (极其罕见，除非同步副作用)，忽略或排队
    if (_isBuilding) {
      return;
    }

    setState(() {
      // 触发重建
    });
  }

  @override
  Widget build(BuildContext context) {
    _isBuilding = true;

    // 我们需要一种机制来检测“移除的依赖”。
    // 简单的做法：每次 build 前清空依赖？
    // 不，那样会导致频繁 subscribe/unsubscribe。
    // 更好的做法：使用两套 Set (oldDependencies, newDependencies)

    // 由于我们是在 builder 函数执行过程中同步收集 watch，
    // 我们可以记录本次 build 用到的 keys。

    // 备份旧的依赖列表
    final previousDependencies = _dependencies.toSet();
    // 清空当前依赖列表 (watch 会重新填充它)
    _dependencies.clear();
    // 注意：_disposers 我们先不动，等 build 完再清理多余的。

    Widget? result;
    try {
      result = widget.builder(context, this, widget.child);
    } finally {
      _isBuilding = false;

      // 清理不再使用的依赖
      for (final atom in previousDependencies) {
        if (!_dependencies.contains(atom)) {
          // 这个 Atom 本次 build 没用到，取消订阅
          final cancel = _disposers.remove(atom);
          cancel?.call();
        }
      }
    }
    return result;
  }
}

/// BuildContext 扩展，提供快捷访问
extension HoneycombContextExtension on BuildContext {
  /// 读取值 (不监听)
  T read<T>(Atom<T> atom) {
    return HoneycombScope.readOf(this).read(atom);
  }

  /// 发送事件
  void emit<T>(Effect<T> effect, T payload) {
    HoneycombScope.readOf(this).emit(effect, payload);
  }

  /// 批量更新
  void batch(void Function() updates) {
    HoneycombScope.readOf(this).batch(updates);
  }
}

/// 用于监听 Effect 的 Widget
class HoneycombListener<T> extends StatefulWidget {
  const HoneycombListener({
    super.key,
    required this.effect,
    required this.onEvent,
    required this.child,
  });

  final Effect<T> effect;
  final void Function(BuildContext context, T payload) onEvent;
  final Widget child;

  @override
  State<HoneycombListener<T>> createState() => _HoneycombListenerState<T>();
}

class _HoneycombListenerState<T> extends State<HoneycombListener<T>> {
  StreamSubscription<T>? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  @override
  void didUpdateWidget(HoneycombListener<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effect != widget.effect) {
      _unsubscribe();
      _subscribe();
    }
  }

  void _subscribe() {
    final container = HoneycombScope.readOf(context);
    _subscription = container.on(widget.effect, (payload) {
      widget.onEvent(context, payload);
    });
  }

  void _unsubscribe() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
