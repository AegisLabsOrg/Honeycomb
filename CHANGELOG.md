## 1.0.2

- **Feature**: Enhanced Observability completely instrumented.
  - `StateRef`, `Computed`, `Effect` now report detailed lifecycle events to `HoneycombDiagnostics`.
  - Added `debugKey` to internal nodes to allow identifying Atoms in logs.
  - `recompute` logs now include execution duration and the dependency that triggered the update.
  - `emit` logs added for Effects.

## 1.0.1

- **Refactor**: `HoneycombScope` is now backed by a `StatefulWidget`. This ensures the `HoneycombContainer` instance persists correctly across widget tree rebuilds (e.g. parent updates, route changes), preventing accidental state loss.
- **Optimization**: `HoneycombConsumer` now performs precise dependency tracking, automatically cleaning up subscriptions for atoms not accessed during the current build.
- **Improvement**: Enhanced Hot Reload support for `Computed` values in the widget tree.

## 1.0.0

### 🎉 Initial Release

#### Core Features
- **StateRef** - Mutable state atoms with auto-dispose policies
- **Computed** - Derived state with automatic dependency tracking
- **EagerComputed** - Immediately recomputes when dependencies change
- **SafeComputed** - Captures exceptions as `Result<T>` instead of throwing
- **AsyncComputed** - Async state management with `AsyncValue<T>`
- **Effect** - One-time events with drop/bufferN/ttl strategies

#### Flutter Integration
- **HoneycombScope** - Widget tree state container with override support
- **HoneycombConsumer** - Builder widget for watching state
- **HoneycombListener** - Side-effect listener for effects
- **Context extensions** - `context.read()`, `context.watch()`, `context.listen()`

#### Advanced Features
- Batch updates for performance optimization
- Scope/Override mechanism for dependency injection
- Hot reload support with `reassemble()`
- Pluggable diagnostics and logging system
- Multiple dispose policies: `keepAlive`, `autoDispose`, `delayed`

