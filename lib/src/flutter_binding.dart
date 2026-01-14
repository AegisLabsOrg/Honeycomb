import 'dart:async';
import 'package:flutter/widgets.dart';
import '../honeycomb.dart';

/// App Root Container Manager.
/// Stores the [HoneycombContainer] in its State so it survives
/// rebuilds of the parent widget tree.
class HoneycombScope extends StatefulWidget {
  const HoneycombScope({
    super.key,
    required this.child,
    this.overrides = const [],
    this.parent,
    this.container,
  });

  final Widget child;
  final List<Override> overrides;
  final HoneycombContainer? parent;
  final HoneycombContainer? container;

  /// Retrieves the nearest [HoneycombContainer] from the context.
  static HoneycombContainer of(BuildContext context) {
    // 1. Try to find the nearest _HoneycombBindingScope
    final scope = context
        .dependOnInheritedWidgetOfExactType<_HoneycombBindingScope>();
    if (scope != null) return scope.container;

    // 2. Fallback: If not found, throw error
    throw StateError(
      'No HoneycombScope found in context. Wrap your app in HoneycombScope.',
    );
  }

  /// Retrieves Container without subscribing (read-only access).
  static HoneycombContainer readOf(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<_HoneycombBindingScope>();
    if (element == null) {
      throw StateError(
        'No HoneycombScope found in context. Wrap your app in HoneycombScope.',
      );
    }
    return (element.widget as _HoneycombBindingScope).container;
  }

  @override
  State<HoneycombScope> createState() => _HoneycombScopeState();
}

class _HoneycombScopeState extends State<HoneycombScope> {
  late HoneycombContainer _container;

  @override
  void initState() {
    super.initState();
    _initContainer();
  }

  void _initContainer() {
    if (widget.container != null) {
      _container = widget.container!;
    } else {
      _container = HoneycombContainer.scoped(
        widget.parent ??
            HoneycombContainer(), // Create a fresh root if no parent
        overrides: widget.overrides,
      );
    }
  }

  @override
  void didUpdateWidget(HoneycombScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.container != null && widget.container != oldWidget.container) {
      _container = widget.container!;
    }
  }

  @override
  void dispose() {
    // Future improvement: _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _HoneycombBindingScope(container: _container, child: widget.child);
  }
}

/// The actual InheritedWidget that propagates the container down the tree.
class _HoneycombBindingScope extends InheritedWidget {
  const _HoneycombBindingScope({required this.container, required super.child});

  final HoneycombContainer container;

  @override
  bool updateShouldNotify(_HoneycombBindingScope oldWidget) {
    // Container instance reference is stable in _HoneycombScopeState
    return container != oldWidget.container;
  }
}

/// Interface for Interacting with Atoms from Widgets.
abstract class WidgetRef {
  /// Watches an Atom and rebuilds the widget when it changes.
  T watch<T>(Atom<T> atom);

  /// Reads an Atom's value without subscribing.
  T read<T>(Atom<T> atom);

  /// Emits an effect payload.
  void emit<T>(Effect<T> effect, T payload);
}

/// A widget that provides a [WidgetRef] to its builder.
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
  late HoneycombContainer _container;

  // Track dependencies to unsubscribe when they are no longer used.
  final Map<Atom, VoidCallback> _subscriptions = {};
  // Track dependencies used during the current build frame.
  final Set<Atom> _dependenciesInBuild = {};

  bool _isBuilding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = HoneycombScope.of(context);
    // If container changes (rare), we might need to resubscribe everything?
    // In this implementation, container is stable provided by _HoneycombScopeState.
    // However, if HoneycombScope is rebuilt with a different container (not possible with current logic unless unmounted),
    // we assume stability.
  }

  /// Hot Reload Support
  @override
  void reassemble() {
    super.reassemble();
    // Force rebuild to refresh computed values or code changes
    setState(() {});
  }

  @override
  void dispose() {
    _unsubscribeAll();
    super.dispose();
  }

  void _unsubscribeAll() {
    for (final cancel in _subscriptions.values) {
      cancel();
    }
    _subscriptions.clear();
    _dependenciesInBuild.clear();
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
    // This method is called during the builder execution.
    // 1. Mark this atom as used in current build.
    _dependenciesInBuild.add(atom);

    // 2. If not already subscribed, subscribe.
    if (!_subscriptions.containsKey(atom)) {
      final cancel = _container.subscribe(atom, _onDependencyChanged);
      _subscriptions[atom] = cancel;
    }

    return _container.read(atom);
  }

  void _onDependencyChanged() {
    // Ignore updates during build (should not happen if pure)
    if (_isBuilding) return;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _isBuilding = true;
    _dependenciesInBuild.clear(); // Reset for this frame

    Widget? result;
    try {
      result = widget.builder(context, this, widget.child);
    } finally {
      _isBuilding = false;
      _cleanupUnusedSubscriptions();
    }
    return result!;
  }

  /// Remove subscriptions that were not accessed during the last build.
  void _cleanupUnusedSubscriptions() {
    // Identify atoms in _subscriptions that are NOT in _dependenciesInBuild
    final unused = _subscriptions.keys
        .where((atom) => !_dependenciesInBuild.contains(atom))
        .toList();

    for (final atom in unused) {
      _subscriptions[atom]?.call(); // Cancel subscription
      _subscriptions.remove(atom);
    }
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
