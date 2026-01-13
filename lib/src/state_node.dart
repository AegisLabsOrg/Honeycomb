import 'package:flutter/foundation.dart';

/// 依赖系统基类，用于构建响应式图
abstract class Node {
  /// 当本节点变化时，需要通知的下游节点
  final Set<Dependency> _observers = {};

  // 这里的 _observers 是 protect 的，子类需要能访问到
  @protected
  Set<Dependency> get observers => _observers;

  void addObserver(Dependency observer) {
    _observers.add(observer);
  }

  void removeObserver(Dependency observer) {
    _observers.remove(observer);
  }

  /// 通知所有观察者我变了（或即使没变，版本号也变了）
  void notifyObservers() {
    // 拷贝一份，防止通知过程中依赖图变化导致并发修改异常
    final listeners = _observers.toList();
    for (final observer in listeners) {
      observer.onDependencyChanged(this);
    }
  }
}

/// 能够作为下游依赖者的接口
abstract class Dependency {
  /// 当上游依赖发生变化时被调用
  void onDependencyChanged(Node dependency);
}

/// 内部使用的状态节点，真实持有数据和监听器
class StateNode<T> extends Node {
  StateNode(this._value);

  /// 仅用于子类延迟初始化 (Lazy)
  StateNode.lazy() : _isInitialized = false;

  late T _value;
  bool _isInitialized = true;

  bool get isInitialized => _isInitialized;

  final Set<VoidCallback> _listeners = {};

  T get value {
    if (!_isInitialized) {
      // 子类（如 ComputeNode）应该重写 value getter 处理懒加载
      // 或者在使用前确保被赋值
      throw StateError('StateNode accessed before initialization');
    }
    return _value;
  }

  set value(T newValue) {
    if (!_isInitialized || _value != newValue) {
      _value = newValue;
      _isInitialized = true;
      notifyListeners();
      notifyObservers();
    }
  }

  /// 静默设置值，不触发通知 (用于 batch 模式)
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

  /// 是否有下游观察者（公开访问）
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
