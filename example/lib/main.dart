import 'package:aegis_honeycomb/honeycomb.dart';
import 'package:flutter/material.dart';

void main() {
  // 启用诊断日志 - 使用 PrintLogger 直接输出到终端
  HoneycombDiagnostics.instance.enableLogging(
    customLogger: PrintLogger(),
    level: LogLevel.debug,
  );

  runApp(HoneycombScope(container: HoneycombContainer(), child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Honeycomb Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🍯 Honeycomb Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          _DemoTile(
            title: 'Counter',
            subtitle: '基础 StateRef + Computed',
            icon: Icons.add_circle,
            onTap: () => _push(context, const CounterDemo()),
          ),
          _DemoTile(
            title: 'Todo List',
            subtitle: 'Selector + 批量更新',
            icon: Icons.checklist,
            onTap: () => _push(context, const TodoDemo()),
          ),
          _DemoTile(
            title: 'Async Data',
            subtitle: 'AsyncComputed + AsyncValue',
            icon: Icons.cloud_download,
            onTap: () => _push(context, const AsyncDemo()),
          ),
          _DemoTile(
            title: 'Effects',
            subtitle: 'Toast / Navigation 事件',
            icon: Icons.notifications,
            onTap: () => _push(context, const EffectDemo()),
          ),
          _DemoTile(
            title: 'Scope Override',
            subtitle: '局部状态覆盖',
            icon: Icons.layers,
            onTap: () => _push(context, const ScopeDemo()),
          ),
          _DemoTile(
            title: 'Form Validation',
            subtitle: 'SafeComputed 错误处理',
            icon: Icons.edit_note,
            onTap: () => _push(context, const FormDemo()),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

class _DemoTile extends StatelessWidget {
  const _DemoTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.amber),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

// ============================================================
// Demo 1: Counter - 基础 StateRef + Computed
// ============================================================

final counterState = StateRef(0);
final doubleCounter = Computed((watch) => watch(counterState) * 2);
final isEven = Computed((watch) => watch(counterState) % 2 == 0);

class CounterDemo extends StatelessWidget {
  const CounterDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Counter Demo')),
      body: Center(
        child: HoneycombConsumer(
          builder: (context, ref, _) {
            final count = ref.watch(counterState);
            final doubled = ref.watch(doubleCounter);
            final even = ref.watch(isEven);

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Count: $count', style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text('Doubled: $doubled', style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 8),
                Chip(
                  label: Text(even ? 'Even' : 'Odd'),
                  backgroundColor:
                      even ? Colors.green[100] : Colors.orange[100],
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'add',
            onPressed: () {
              final container = HoneycombScope.readOf(context);
              container.write(counterState, container.read(counterState) + 1);
            },
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'sub',
            onPressed: () {
              final container = HoneycombScope.readOf(context);
              container.write(counterState, container.read(counterState) - 1);
            },
            child: const Icon(Icons.remove),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Demo 2: Todo List - Selector + 批量更新
// ============================================================

class Todo {
  Todo(this.id, this.title, {this.completed = false});
  final int id;
  final String title;
  final bool completed;

  Todo copyWith({String? title, bool? completed}) {
    return Todo(
      id,
      title ?? this.title,
      completed: completed ?? this.completed,
    );
  }
}

final todosState = StateRef<List<Todo>>([
  Todo(1, 'Learn Honeycomb'),
  Todo(2, 'Build awesome app'),
  Todo(3, 'Deploy to production'),
]);

// Selector: 只监听列表长度
final todoCount = Computed((watch) => watch(todosState).length);

// Selector: 只监听完成数量
final completedCount = Computed(
  (watch) => watch(todosState).where((t) => t.completed).length,
);

class TodoDemo extends StatelessWidget {
  const TodoDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Todo Demo'),
        actions: [
          // 显示统计，使用 Selector 优化
          HoneycombConsumer(
            builder: (context, ref, _) {
              final total = ref.watch(todoCount);
              final done = ref.watch(completedCount);
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(child: Text('$done / $total')),
              );
            },
          ),
        ],
      ),
      body: HoneycombConsumer(
        builder: (context, ref, _) {
          final todos = ref.watch(todosState);

          return ListView.builder(
            itemCount: todos.length,
            itemBuilder: (context, index) {
              final todo = todos[index];
              return CheckboxListTile(
                value: todo.completed,
                title: Text(
                  todo.title,
                  style: TextStyle(
                    decoration:
                        todo.completed ? TextDecoration.lineThrough : null,
                  ),
                ),
                onChanged: (value) {
                  final container = HoneycombScope.readOf(context);
                  final newTodos =
                      todos.map((t) {
                        if (t.id == todo.id) {
                          return t.copyWith(completed: value);
                        }
                        return t;
                      }).toList();
                  container.write(todosState, newTodos);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTodo(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _addTodo(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Add Todo'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Todo title'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  final container = HoneycombScope.readOf(context);
                  final todos = container.read(todosState);
                  final newId = todos.isEmpty ? 1 : todos.last.id + 1;
                  container.write(todosState, [
                    ...todos,
                    Todo(newId, controller.text),
                  ]);
                }
                Navigator.pop(dialogContext);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================
// Demo 3: Async Data - AsyncComputed + AsyncValue
// ============================================================

final selectedUserId = StateRef(1);

final userDetail = Computed.async((watch) async {
  final userId = watch(selectedUserId);

  // 模拟网络请求
  await Future.delayed(const Duration(seconds: 1));

  // 模拟数据
  final users = {
    1: {'name': 'Alice', 'email': 'alice@example.com'},
    2: {'name': 'Bob', 'email': 'bob@example.com'},
    3: {'name': 'Charlie', 'email': 'charlie@example.com'},
  };

  if (!users.containsKey(userId)) {
    throw Exception('User not found');
  }

  return users[userId]!;
});

class AsyncDemo extends StatelessWidget {
  const AsyncDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Async Demo')),
      body: Column(
        children: [
          // User selector
          HoneycombConsumer(
            builder: (context, ref, _) {
              final currentId = ref.watch(selectedUserId);
              return Padding(
                padding: const EdgeInsets.all(16),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('User 1')),
                    ButtonSegment(value: 2, label: Text('User 2')),
                    ButtonSegment(value: 3, label: Text('User 3')),
                    ButtonSegment(value: 99, label: Text('Invalid')),
                  ],
                  selected: {currentId},
                  onSelectionChanged: (selected) {
                    HoneycombScope.readOf(
                      context,
                    ).write(selectedUserId, selected.first);
                  },
                ),
              );
            },
          ),

          const Divider(),

          // User detail with AsyncValue
          Expanded(
            child: HoneycombConsumer(
              builder: (context, ref, _) {
                final asyncUser = ref.watch(userDetail);

                return asyncUser.when(
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  data:
                      (user) => Center(
                        child: Card(
                          margin: const EdgeInsets.all(32),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person, size: 64),
                                const SizedBox(height: 16),
                                Text(
                                  user['name']!,
                                  style: const TextStyle(fontSize: 24),
                                ),
                                const SizedBox(height: 8),
                                Text(user['email']!),
                              ],
                            ),
                          ),
                        ),
                      ),
                  error:
                      (error, _) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error,
                              size: 64,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 16),
                            Text('Error: $error'),
                          ],
                        ),
                      ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Demo 4: Effects - Toast / Navigation 事件
// ============================================================

final toastEffect = Effect<String>(
  strategy: EffectStrategy.drop,
  name: 'toast',
);

final navigationEffect = Effect<String>(
  strategy: EffectStrategy.bufferN,
  bufferSize: 5,
  name: 'navigation',
);

class EffectDemo extends StatelessWidget {
  const EffectDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Effect Demo')),
      body: HoneycombListener<String>(
        effect: toastEffect,
        onEvent: (ctx, message) {
          ScaffoldMessenger.of(
            ctx,
          ).showSnackBar(SnackBar(content: Text(message)));
        },
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Effects Demo', style: TextStyle(fontSize: 24)),
              const SizedBox(height: 32),

              ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Show Success Toast'),
                onPressed: () {
                  context.emit(toastEffect, '✅ Operation successful!');
                },
              ),
              const SizedBox(height: 16),

              ElevatedButton.icon(
                icon: const Icon(Icons.warning),
                label: const Text('Show Warning Toast'),
                onPressed: () {
                  context.emit(toastEffect, '⚠️ Please be careful!');
                },
              ),
              const SizedBox(height: 16),

              ElevatedButton.icon(
                icon: const Icon(Icons.error),
                label: const Text('Show Error Toast'),
                onPressed: () {
                  context.emit(toastEffect, '❌ Something went wrong!');
                },
              ),

              const SizedBox(height: 48),
              const Text(
                'Effect with drop strategy:\nEvents are lost if no listener',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Demo 5: Scope Override - 局部状态覆盖
// ============================================================

final themeColorState = StateRef(Colors.blue);

class ScopeDemo extends StatelessWidget {
  const ScopeDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scope Override Demo')),
      body: Column(
        children: [
          // 全局主题色
          Expanded(
            child: _ColoredSection(title: 'Global Scope', showButtons: true),
          ),

          const Divider(height: 1),

          // 局部 Override - 强制红色
          Expanded(
            child: HoneycombScope(
              overrides: [themeColorState.overrideWith(Colors.red)],
              child: _ColoredSection(
                title: 'Override: Red',
                showButtons: false,
              ),
            ),
          ),

          const Divider(height: 1),

          // 局部 Override - 强制绿色
          Expanded(
            child: HoneycombScope(
              overrides: [themeColorState.overrideWith(Colors.green)],
              child: _ColoredSection(
                title: 'Override: Green',
                showButtons: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColoredSection extends StatelessWidget {
  const _ColoredSection({required this.title, required this.showButtons});

  final String title;
  final bool showButtons;

  @override
  Widget build(BuildContext context) {
    return HoneycombConsumer(
      builder: (context, ref, _) {
        final color = ref.watch(themeColorState);

        return Container(
          color: color.withAlpha(51), // 0.2 * 255 ≈ 51
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 16),
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (showButtons) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _colorButton(context, Colors.blue),
                      _colorButton(context, Colors.purple),
                      _colorButton(context, Colors.orange),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _colorButton(BuildContext context, Color color) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: IconButton(
        icon: Icon(Icons.circle, color: color),
        onPressed: () {
          HoneycombScope.readOf(context).write(themeColorState, color);
        },
      ),
    );
  }
}

// ============================================================
// Demo 6: Form Validation - SafeComputed 错误处理
// ============================================================

final emailState = StateRef('');
final passwordState = StateRef('');

// SafeComputed: 自动捕获异常
final emailValidation = SafeComputed<String>((watch) {
  final email = watch(emailState);
  if (email.isEmpty) throw FormatException('Email is required');
  if (!email.contains('@')) throw FormatException('Invalid email format');
  return email;
});

final passwordValidation = SafeComputed<String>((watch) {
  final password = watch(passwordState);
  if (password.isEmpty) {
    throw FormatException('Password is required');
  }
  if (password.length < 8) {
    throw FormatException('Password must be at least 8 characters');
  }
  return password;
});

// 表单整体是否有效
final isFormValid = Computed((watch) {
  final email = watch(emailValidation);
  final password = watch(passwordValidation);
  return email.isSuccess && password.isSuccess;
});

class FormDemo extends StatelessWidget {
  const FormDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Form Validation Demo')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('SafeComputed Demo', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 8),
            const Text(
              'Exceptions are automatically caught and wrapped in Result.failure',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),

            // Email field
            HoneycombConsumer(
              builder: (context, ref, _) {
                final validation = ref.watch(emailValidation);

                return TextField(
                  decoration: InputDecoration(
                    labelText: 'Email',
                    errorText: validation.when(
                      success: (_) => null,
                      failure:
                          (e, _) => e.toString().replaceFirst(
                            'FormatException: ',
                            '',
                          ),
                    ),
                    suffixIcon:
                        validation.isSuccess
                            ? const Icon(Icons.check, color: Colors.green)
                            : null,
                  ),
                  onChanged: (value) {
                    HoneycombScope.readOf(context).write(emailState, value);
                  },
                );
              },
            ),
            const SizedBox(height: 16),

            // Password field
            HoneycombConsumer(
              builder: (context, ref, _) {
                final validation = ref.watch(passwordValidation);

                return TextField(
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    errorText: validation.when(
                      success: (_) => null,
                      failure:
                          (e, _) => e.toString().replaceFirst(
                            'FormatException: ',
                            '',
                          ),
                    ),
                    suffixIcon:
                        validation.isSuccess
                            ? const Icon(Icons.check, color: Colors.green)
                            : null,
                  ),
                  onChanged: (value) {
                    HoneycombScope.readOf(context).write(passwordState, value);
                  },
                );
              },
            ),
            const SizedBox(height: 32),

            // Submit button
            HoneycombConsumer(
              builder: (context, ref, _) {
                final valid = ref.watch(isFormValid);

                return ElevatedButton(
                  onPressed:
                      valid
                          ? () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ Form submitted!'),
                              ),
                            );
                          }
                          : null,
                  child: const Text('Submit'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
