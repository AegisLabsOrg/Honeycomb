import 'dart:async';
import 'package:flutter/foundation.dart';

import '../honeycomb.dart';
import 'state_node.dart';
import 'compute_node.dart';

/// Node that manages async computation.
class AsyncComputeNode<T> extends StateNode<AsyncValue<T>>
    implements Dependency {
  AsyncComputeNode(this._container, this._computeFn, {super.debugKey})
    : super(const AsyncValue.loading());

  final HoneycombContainer _container;
  final Future<T> Function(WatchFn watch) _computeFn;

  // Dependency tracking helpers.
  final Set<Node> _dependencies = {};
  int _dependencyVersion = 0;
  bool _ensureStarted = false;

  /// Invalidates the node and recomputes (for Hot Reload).
  void invalidate() {
    _recompute();
  }

  @override
  AsyncValue<T> get value {
    if (!_ensureStarted) {
      _ensureStarted = true;
      // Use a microtask to avoid triggering side effects during read and
      // potential deadlocks/re-entrancy.
      // For lazy mode, trigger on first read.
      // _recompute mutates value (notifyListeners), which is risky in a getter
      // (e.g. during build).
      // Better: schedule a microtask to start computing.
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
    // When a dependency changes, mark loading and recompute.
    _recompute();
  }

  void _recompute() {
    // Debounce/dedupe logic: if already loading from the same trigger...
    // For now, simply recompute on every change.

    // Set state to Loading (keep previous value).
    value = AsyncValue.loading(previous: value.valueOrNull);

    // Bump version to drop outdated Future results (race condition handling).
    final currentVersion = ++_dependencyVersion;

    _runCompute(currentVersion);
  }

  Future<void> _runCompute(int version) async {
    // Clear old dependencies (Computed logic).
    // Note: similar to ComputeNode; could be shared.
    // Because this is Future-based, dependencies may be read during execution.
    // Honeycomb requires watch to be synchronous to be tracked.
    // Async computeFn is `Future<T> Function(watch)`.
    // watch must happen before the first await to be tracked.
    // If user does `await future; watch(atom);`, that watch runs in a microtask
    // and the global `_currentlyComputingNode` may have changed or be null.
    // Therefore: Honeycomb requires synchronous dependency collection.

    // Start dependency collection.
    final previousNode = ComputeNode.currentlyComputingNode;
    ComputeNode.currentlyComputingNode = this;

    // Clear old dependencies.
    for (final dep in _dependencies) {
      dep.removeObserver(this);
    }
    _dependencies.clear();

    try {
      // Execute user function to get a Future.
      // The synchronous part runs here and collects dependencies.
      final future = _computeFn(<R>(Atom<R> atom) {
        final node = _container.internalGetNode(atom);
        if (_dependencies.add(node)) {
          node.addObserver(this);
        }
        return node.value;
      });

      // Stop dependency collection (sync part finished).
      ComputeNode.currentlyComputingNode = previousNode;

      // Await result.
      final result = await future;

      // If version changed, a new computation started; drop this result.
      if (version != _dependencyVersion) return;

      value = AsyncValue.data(result);
    } catch (e, s) {
      // Stop dependency collection (if sync phase throws).
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
