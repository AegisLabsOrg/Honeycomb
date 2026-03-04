import 'dart:async';

import '../honeycomb.dart';
import 'state_node.dart';
import 'compute_node.dart';

/// Eagerly evaluated Computed node.
/// Unlike ComputeNode, it recomputes immediately on upstream changes,
/// even without subscribers.
class EagerComputeNode<T> extends StateNode<T> implements Dependency {
  EagerComputeNode(this._container, this._computeFn, {super.debugKey})
    : super.lazy() {
    // Compute initial value immediately.
    _recompute();
  }

  final HoneycombContainer _container;
  final T Function(WatchFn watch) _computeFn;

  /// Dependencies used in the current computation.
  final Set<Node> _dependencies = {};

  bool _isDirty = false;
  bool _isScheduled = false;

  /// Manually mark dirty and recompute (for Hot Reload).
  void markDirty() {
    _isDirty = true;
    _recompute();
  }

  @override
  T get value {
    if (_isDirty) {
      _recompute();
    }
    return super.value;
  }

  @override
  void onDependencyChanged(Node dependency) {
    if (!_isDirty) {
      _isDirty = true;
      // Push: Notify downstream that this node is dirty.
      notifyObservers();
      // Notify UI listeners to schedule a rebuild.
      notifyListeners();
    }

    if (!_isScheduled) {
      _isScheduled = true;
      scheduleMicrotask(() {
        if (_isDirty) {
          _recompute();
        }
        _isScheduled = false;
      });
    }
  }

  void _recompute() {
    // Circular dependency detection (reuse ComputeNode stack).
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
      // Clear old dependency subscriptions.
      for (final dep in _dependencies) {
        dep.removeObserver(this);
      }
      _dependencies.clear();

      // Execute compute function.
      final newValue = _computeFn(<R>(Atom<R> atom) {
        final node = _container.internalGetNode(atom);
        if (_dependencies.add(node)) {
          node.addObserver(this);
        }
        return node.value;
      });

      // Update value and notify (even if no listeners, keep internal value fresh).
      if (!isInitialized || newValue != super.value) {
        setValueSilently(newValue);
      } else {
        // Value unchanged but ensure initialized.
        if (!isInitialized) {
          setValueSilently(newValue);
        }
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
