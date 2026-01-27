import '../honeycomb.dart';
import 'state_node.dart';
import 'diagnostics.dart';

/// Global: the Computed node currently being evaluated.
/// Used to capture dependencies during `watch()`.
Dependency? _currentlyComputingNode;

/// Stack of nodes being computed (for circular dependency detection).
/// Exposed via internal getter for other compute nodes.
final Set<Dependency> _computingStack = {};

/// Get the computing stack (for EagerComputeNode, etc.).
Set<Dependency> get computingStack => _computingStack;

/// Circular dependency error.
class CircularDependencyError extends Error {
  CircularDependencyError(this.message);
  final String message;
  @override
  String toString() => 'CircularDependencyError: $message';
}

/// Derived state node.
class ComputeNode<T> extends StateNode<T> implements Dependency {
  ComputeNode(this._container, this._computeFn, {super.debugKey})
    : super.lazy() {
    _isDirty = true;
  }

  static Dependency? get currentlyComputingNode => _currentlyComputingNode;
  static set currentlyComputingNode(Dependency? node) =>
      _currentlyComputingNode = node;

  final HoneycombContainer _container;
  final T Function(WatchFn watch) _computeFn;

  /// Dependencies used in the current computation.
  final Set<Node> _dependencies = {};

  /// Dependencies that dirtied this node (for diagnostics).
  final Set<Atom> _dirtiedBy = {};

  /// Whether this node is dirty and needs recomputation.
  bool _isDirty = false;

  /// Manually mark dirty (for Hot Reload).
  void markDirty() {
    _isDirty = true;
  }

  /// Is it dirty on initialization?
  /// The super constructor already computes an initial value, so it's clean.
  /// But for lazy nodes without an initial value, we may need to handle it.
  /// `_isDirty` controls caching; we recompute on read.

  // Override value getter to implement lazy evaluation and dependency tracking.
  @override
  T get value {
    // If dirty, recompute.
    if (_isDirty) {
      _recompute();
    }

    return super.value;
  }

  // As a dependent: when an upstream node changes.
  @override
  void onDependencyChanged(Node dependency) {
    if (dependency is StateNode && dependency.debugKey is Atom) {
      _dirtiedBy.add(dependency.debugKey as Atom);
    }

    if (!_isDirty) {
      _isDirty = true;
      // Notify downstream: I may have changed (even before recompute).
      // Strategy:
      // - If I have listeners (UI), recompute immediately to check for changes.
      // - If no listeners (lazy), just mark dirty and recompute on next read.

      if (hasListeners || observers.isNotEmpty) {
        // Eager mode: must recompute to notify UI.
        _recompute();
      } else {
        // Lazy mode: mark dirty only; downstream isn't listening either.
        // Next read will see the dirty flag.
      }
    }
  }

  void _recompute() {
    // Circular dependency detection.
    if (_computingStack.contains(this)) {
      throw CircularDependencyError(
        'Detected circular dependency while computing. '
        'A Computed is watching itself directly or indirectly.',
      );
    }

    final previousNode = _currentlyComputingNode;
    _currentlyComputingNode = this;
    _computingStack.add(this);

    final stopwatch = Stopwatch()..start();

    try {
      // Prepare to collect a new set of dependencies.
      // Clear old subscriptions to avoid leaks and stale edges.
      for (final dep in _dependencies) {
        dep.removeObserver(this);
      }
      _dependencies.clear();

      // Execute compute function with a closure-based watch.
      final newValue = _computeFn(<R>(Atom<R> atom) {
        final node = _container.internalGetNode(atom);
        // Explicit dependency registration.
        if (_dependencies.add(node)) {
          node.addObserver(this);
        }
        // Return value without implicit tracking logic inside node.value.
        return node.value;
      });

      stopwatch.stop();

      // Log recompute.
      if (debugKey != null &&
          debugKey is Atom &&
          HoneycombDiagnostics.instance.enabled) {
        final changedDeps = _dirtiedBy.toList();
        HoneycombDiagnostics.instance.notifyRecompute(
          RecomputeReason(
            atom: debugKey as Atom,
            changedDependencies: changedDeps,
            duration: stopwatch.elapsed,
            newValue: newValue,
            oldValue: isInitialized ? super.value : null,
          ),
        );
      }
      _dirtiedBy.clear();

      // Computation finished; _dependencies now contains the latest deps.

      // Update value.
      if (!isInitialized || newValue != super.value) {
        super.value = newValue;
      }

      // Mark clean regardless of value change.
      _isDirty = false;
    } finally {
      _computingStack.remove(this);
      _currentlyComputingNode = previousNode;
    }
  }

  //  static T _tracker<T>(Atom<T> atom) { ... removed ... }

  @override
  void dispose() {
    // Detach all upstream dependencies.
    for (final dep in _dependencies) {
      dep.removeObserver(this);
    }
    _dependencies.clear();
    super.dispose();
  }
}
