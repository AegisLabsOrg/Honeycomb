import '../honeycomb.dart';
import 'state_node.dart';
import 'compute_node.dart';

/// Safe Computed node; exceptions are captured and wrapped as Result.failure.
class SafeComputeNode<T> extends StateNode<Result<T>> implements Dependency {
  SafeComputeNode(this._container, this._computeFn, {super.debugKey})
    : super.lazy() {
    _isDirty = true;
  }

  final HoneycombContainer _container;
  final T Function(WatchFn watch) _computeFn;

  final Set<Node> _dependencies = {};
  bool _isDirty = false;

  /// Manually mark dirty (for Hot Reload).
  void markDirty() {
    _isDirty = true;
  }

  @override
  Result<T> get value {
    if (_isDirty) {
      _recompute();
    }
    return super.value;
  }

  @override
  void onDependencyChanged(Node dependency) {
    if (!_isDirty) {
      _isDirty = true;
      if (hasListeners || observers.isNotEmpty) {
        _recompute();
      }
    }
  }

  void _recompute() {
    if (computingStack.contains(this)) {
      throw CircularDependencyError(
        'Detected circular dependency in SafeComputed.',
      );
    }

    final previousNode = ComputeNode.currentlyComputingNode;
    ComputeNode.currentlyComputingNode = this;
    computingStack.add(this);

    try {
      for (final dep in _dependencies) {
        dep.removeObserver(this);
      }
      _dependencies.clear();

      // Capture exceptions.
      Result<T> newValue;
      try {
        final computed = _computeFn(<R>(Atom<R> atom) {
          final node = _container.internalGetNode(atom);
          if (_dependencies.add(node)) {
            node.addObserver(this);
          }
          return node.value;
        });
        newValue = Result.success(computed);
      } catch (e, st) {
        newValue = Result.failure(e, st);
      }

      if (!isInitialized || newValue != super.value) {
        super.value = newValue;
      }

      _isDirty = false;
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
