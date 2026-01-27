import 'package:flutter/foundation.dart';
import 'diagnostics.dart';
import '../honeycomb.dart' show Atom;

/// Base class for the dependency system, used to build the reactive graph.
abstract class Node {
  /// Downstream dependents to notify when this node changes.
  final Set<Dependency> _observers = {};

  // _observers is protected so subclasses can access it.
  @protected
  Set<Dependency> get observers => _observers;

  void addObserver(Dependency observer) {
    _observers.add(observer);
  }

  void removeObserver(Dependency observer) {
    _observers.remove(observer);
  }

  /// Notify all observers of a change (or version change even if value same).
  void notifyObservers() {
    // Copy to avoid concurrent modification during graph changes.
    final listeners = _observers.toList();
    for (final observer in listeners) {
      observer.onDependencyChanged(this);
    }
  }
}

/// Interface for downstream dependents.
abstract class Dependency {
  /// Called when an upstream dependency changes.
  void onDependencyChanged(Node dependency);
}

/// Internal state node that holds data and listeners.
class StateNode<T> extends Node {
  StateNode(this._value, {this.debugKey});

  /// For subclasses with lazy initialization.
  StateNode.lazy({this.debugKey}) : _isInitialized = false;

  final Object? debugKey;
  late T _value;
  bool _isInitialized = true;

  bool get isInitialized => _isInitialized;

  final Set<VoidCallback> _listeners = {};

  T get value {
    if (!_isInitialized) {
      // Subclasses (e.g. ComputeNode) should override value getter for lazy init
      // or ensure it is assigned before use.
      throw StateError('StateNode accessed before initialization');
    }
    return _value;
  }

  set value(T newValue) {
    if (!_isInitialized || _value != newValue) {
      final oldValue = _isInitialized ? _value : null;
      _value = newValue;
      _isInitialized = true;

      if (debugKey != null &&
          debugKey is Atom &&
          HoneycombDiagnostics.instance.enabled) {
        HoneycombDiagnostics.instance.notifyStateChange(
          StateChangeEvent(
            atom: debugKey as Atom,
            oldValue: oldValue,
            newValue: newValue,
            timestamp: DateTime.now(),
          ),
        );
      }

      notifyListeners();
      notifyObservers();
    }
  }

  /// Set value silently without notifications (for batch mode).
  void setValueSilently(T newValue) {
    _value = newValue;
    _isInitialized = true;
  }

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  bool get hasListeners => _listeners.isNotEmpty;

  /// Whether there are downstream observers (public access).
  bool get hasObservers => _observers.isNotEmpty;

  void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  void dispose() {
    _listeners.clear();
    _observers.clear();
  }
}
