import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/daemon.dart';
import '../theme/colors.dart';
import '../models/messages.dart';
import '../widgets/terminal_output.dart';
import '../widgets/provider_switcher.dart';
import '../widgets/input_bar.dart';
import '../widgets/connection_banner.dart';
import '../widgets/shimmer_loading.dart';

class AgentScreen extends StatefulWidget {
  const AgentScreen({super.key});

  @override
  State<AgentScreen> createState() => AgentScreenState();
}

class AgentScreenState extends State<AgentScreen> {
  final List<TerminalLine> _lines = [];
  String _activeProvider = 'copilot';
  String _activeModel = 'gpt-5-mini';
  bool _connected = false;
  bool _taskRunning = false;
  String? _activeTaskId;

  // Session continuity — persists across tasks within a conversation.
  String? _sessionId;

  /// Called from MainScreen when user resumes a session from the Sessions screen.
  void resumeFromSession(String sessionId) {
    setState(() {
      _sessionId = sessionId;
      _lines.clear();
    });
    _addLine(TerminalLine(type: TerminalLineType.text, content: 'Resumed session: $sessionId'));
  }

  // Connection lifecycle
  bool _initializing = true; // true until first connect attempt finishes
  bool _reconnecting = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  static const _maxReconnectDelay = Duration(seconds: 30);

  // Bootstrap progress (shown during first launch extraction)
  String? _bootstrapMessage;
  int? _bootstrapPercent;
  Timer? _bootstrapPollTimer;

  // Degraded mode — proot is configured but non-functional (e.g. Android 15 SELinux)
  bool _prootDegraded = false;
  String? _prootDegradedError;
  bool _prootDegradedDismissed = false;

  // Track subscriptions for cleanup
  StreamSubscription? _messageSub;
  StreamSubscription? _connectionSub;

  @override
  void initState() {
    super.initState();
    _initConnection();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _bootstrapPollTimer?.cancel();
    _messageSub?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }

  Future<void> _initConnection() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _startBootstrapPolling();
    await _attemptConnect();
  }

  /// Poll the platform channel for runtime bootstrap progress.
  void _startBootstrapPolling() {
    _bootstrapPollTimer?.cancel();
    _bootstrapPollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_connected || !mounted) {
        _bootstrapPollTimer?.cancel();
        return;
      }
      final api = context.read<OpenCodeAPI>();
      final status = await api.getRuntimeStatus();
      if (!mounted || _connected) return;
      if (status != null) {
        final progress = status['progress'] as String?;
        final percent = status['progress_percent'] as int?;
        if (progress != null && progress.isNotEmpty) {
          setState(() {
            _bootstrapMessage = progress;
            _bootstrapPercent = percent;
          });
        }
      }
    });
  }

  Future<void> _attemptConnect() async {
    final api = context.read<OpenCodeAPI>();
    try {
      await api.connect();
      if (!mounted) return;
      _bootstrapPollTimer?.cancel();
      setState(() {
        _connected = true;
        _initializing = false;
        _reconnecting = false;
        _reconnectAttempt = 0;
        _bootstrapMessage = null;
        _bootstrapPercent = null;
      });
      _addLine(TerminalLine(type: TerminalLineType.text, content: 'Connected to mo-code daemon'));

      // Cancel any pending reconnect timer.
      _reconnectTimer?.cancel();

      // Check proot health in background — show degraded banner if broken.
      _checkProotHealth(api);

      // Re-subscribe to streams (cancel old ones first).
      _messageSub?.cancel();
      _connectionSub?.cancel();

      _messageSub = api.messages.listen(_handleEvent);
      _connectionSub = api.connection.listen((c) {
        if (!mounted) return;
        final wasConnected = _connected;
        setState(() => _connected = c);
        if (!c && wasConnected) {
          _addLine(TerminalLine(type: TerminalLineType.error, content: 'Disconnected from server'));
          _scheduleReconnect();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _initializing = false;
      });
      if (_reconnectAttempt == 0) {
        _addLine(TerminalLine(type: TerminalLineType.error, content: 'Connection failed: $e'));
      }
      _scheduleReconnect();
    }
  }

  /// Runs proot diagnostics after connect. Shows a degraded-mode banner when
  /// proot is configured but the echo-ok test fails (ISSUE-010 / Android 15).
  Future<void> _checkProotHealth(OpenCodeAPI api) async {
    // Only run on Android — on desktop proot is not used.
    final runtimeStatus = await api.fetchRuntimeStatus();
    if (!mounted) return;
    final prootAvailable = runtimeStatus?['available'] == true;
    if (!prootAvailable) return; // proot not configured — no banner needed

    final diag = await api.runProotDiagnostic();
    if (!mounted) return;
    if (diag == null) return; // network error — silent
    final ok = diag['ok'] == true;
    if (ok) {
      // Runtime healthy — clear any stale degraded state.
      if (_prootDegraded) {
        setState(() {
          _prootDegraded = false;
          _prootDegradedError = null;
        });
      }
      return;
    }
    final error = diag['error'] as String? ?? 'proot runtime check failed';
    setState(() {
      _prootDegraded = true;
      _prootDegradedError = error;
      _prootDegradedDismissed = false;
    });
  }

  void _scheduleReconnect() {
    if (_reconnecting) return; // already scheduled
    _reconnectTimer?.cancel();
    setState(() => _reconnecting = true);

    // Exponential backoff: 1s, 2s, 4s, 8s, ... capped at 30s.
    _reconnectAttempt++;
    final delaySec = min(pow(2, _reconnectAttempt - 1).toInt(), _maxReconnectDelay.inSeconds);
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (!mounted) return;
      _attemptConnect();
    });
  }

  void _manualRetry() {
    _reconnectTimer?.cancel();
    setState(() {
      _reconnecting = true;
      _reconnectAttempt = 0;
    });
    _attemptConnect();
  }

  void _removeThinkingLines() {
    setState(() {
      _lines.removeWhere((l) => l.type == TerminalLineType.agentThinking);
    });
  }

  void _handleEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['type'] as String? ?? '';
    final payload = event['payload'];

    switch (type) {
      case 'agent.stream':
        // Streaming content from the agent — remove "Processing..." on first content
        _removeThinkingLines();
        if (payload is Map<String, dynamic>) {
          final kind = payload['kind'] as String? ?? '';
          final content = payload['content'] as String? ?? '';
          final metadata = payload['metadata'] as Map<String, dynamic>? ?? {};
          switch (kind) {
            case 'text':
              if (content.isNotEmpty) {
                _appendText(content);
              }
              break;
            case 'tool_call':
              final toolArgs = metadata['args'] as String? ?? '';
              final display = toolArgs.isNotEmpty
                  ? '$content($toolArgs)'
                  : content;
              _addLine(TerminalLine(type: TerminalLineType.toolCall, content: display));
              break;
            case 'tool_result':
              if (content.isNotEmpty) {
                _addToolResult(content);
              }
              break;
            case 'token_usage':
              final input = metadata['input'] ?? 0;
              final output = metadata['output'] ?? 0;
              _addLine(TerminalLine(
                type: TerminalLineType.tokenCount,
                content: 'tokens: $input in / $output out',
              ));
              break;
            case 'file_create':
              _addLine(TerminalLine(type: TerminalLineType.fileCreated, content: content));
              break;
            case 'file_modify':
              _addLine(TerminalLine(type: TerminalLineType.fileModified, content: content));
              break;
            case 'plan':
              _addLine(TerminalLine(type: TerminalLineType.planStep, content: content));
              break;
            case 'status':
              _addLine(TerminalLine(type: TerminalLineType.agentThinking, content: content));
              break;
            case 'error':
              _addLine(TerminalLine(type: TerminalLineType.error, content: content));
              break;
            case 'diff':
              _handleDiffEvent(metadata);
              break;
            case 'todo_update':
              _handleTodoEvent(metadata);
              break;
            case 'done':
              // Stream is done, but task.complete will handle the UI update.
              break;
          }
        }
        break;
      case 'task.complete':
        _removeThinkingLines();
        _addLine(TerminalLine(type: TerminalLineType.separator));
        if (payload is Map<String, dynamic>) {
          final summary = payload['summary'] as String? ?? 'Task completed';
          final tokens = payload['total_tokens'] as int? ?? 0;
          _addLine(TerminalLine(type: TerminalLineType.text, content: summary));
          if (tokens > 0) {
            _addLine(TerminalLine(type: TerminalLineType.tokenCount, content: '$tokens tokens'));
          }
        } else {
          _addLine(TerminalLine(type: TerminalLineType.text, content: 'Task completed'));
        }
        // Keep _sessionId — session persists across tasks for multi-turn context.
        setState(() {
          _taskRunning = false;
          _activeTaskId = null;
        });
        break;
      case 'task.failed':
        _removeThinkingLines();
        if (payload is Map<String, dynamic>) {
          final error = payload['error'] as String? ?? 'Unknown error';
          _addLine(TerminalLine(type: TerminalLineType.error, content: 'Task failed: $error'));
        } else {
          _addLine(TerminalLine(type: TerminalLineType.error, content: 'Task failed'));
        }
        // Keep _sessionId — user can retry within same context.
        setState(() {
          _taskRunning = false;
          _activeTaskId = null;
        });
        break;
      case 'error':
        // If this error is for a pending direct_tool_call (shell bypass),
        // render it in that flow and don't touch task-running state.
        final eventId = event['id'] as String?;
        if (eventId != null && _pendingDirectCalls.remove(eventId)) {
          _removeThinkingLines();
          if (payload is Map<String, dynamic>) {
            final message = payload['message'] as String? ?? 'Unknown error';
            _addLine(TerminalLine(
              type: TerminalLineType.error,
              content: 'Shell bypass failed: $message',
            ));
          }
          break;
        }
        if (payload is Map<String, dynamic>) {
          final message = payload['message'] as String? ?? 'Unknown error';
          _addLine(TerminalLine(type: TerminalLineType.error, content: message));
        }
        setState(() {
          _taskRunning = false;
          _activeTaskId = null;
        });
        break;
      case 'direct_tool_result':
        if (payload is Map<String, dynamic>) {
          _handleDirectToolResult(event['id'] as String?, payload);
        }
        break;
      case 'config.current':
        // Config update broadcast — could refresh provider status
        break;
      case 'server.status':
        // Server status update — no UI action needed
        break;
      default:
        debugPrint('Unhandled event: $type');
    }
  }

  void _addLine(TerminalLine line) {
    setState(() => _lines.add(line));
  }

  /// Append text to the last text line (for streaming), or create a new one.
  void _appendText(String text) {
    setState(() {
      if (_lines.isNotEmpty && _lines.last.type == TerminalLineType.text) {
        _lines[_lines.length - 1] = TerminalLine(
          type: TerminalLineType.text,
          content: _lines.last.content + text,
        );
      } else {
        _lines.add(TerminalLine(type: TerminalLineType.text, content: text));
      }
    });
  }

  /// Show tool result truncated — max 6 lines, with a count if more.
  void _addToolResult(String content) {
    final lines = content.split('\n');
    const maxLines = 6;
    if (lines.length <= maxLines) {
      _addLine(TerminalLine(type: TerminalLineType.text, content: content));
    } else {
      final preview = lines.take(maxLines).join('\n');
      final hidden = lines.length - maxLines;
      _addLine(TerminalLine(type: TerminalLineType.text, content: preview));
      _addLine(TerminalLine(type: TerminalLineType.text, content: '  ... ($hidden more lines)'));
    }
  }

  void _handleDiffEvent(Map<String, dynamic> metadata) {
    final diffData = DiffFile.fromJson(metadata);
    _addLine(TerminalLine(
      type: TerminalLineType.diff,
      diffData: diffData,
    ));
  }

  void _handleTodoEvent(Map<String, dynamic> metadata) {
    final rawItems = metadata['items'] as List<dynamic>? ?? [];
    final items = rawItems
        .map((i) => TodoItem.fromJson(i as Map<String, dynamic>))
        .toList();

    // Update in-place if there's already a todo panel, otherwise add new.
    setState(() {
      final existingIdx = _lines.lastIndexWhere(
        (l) => l.type == TerminalLineType.todo,
      );
      if (existingIdx >= 0) {
        _lines[existingIdx] = TerminalLine(
          type: TerminalLineType.todo,
          todoItems: items,
        );
      } else {
        _lines.add(TerminalLine(
          type: TerminalLineType.todo,
          todoItems: items,
        ));
      }
    });
  }

  // --- Slash command definitions ---
  static const _availableSkills = [
    '/model <name>    — switch model (e.g. /model gpt-4o)',
    '/skills          — list available slash commands',
    '/stop            — stop current task',
    '/clear           — clear terminal output',
    '/provider <name> — switch provider (copilot, claude, gemini, openrouter, ollama, azure)',
    '/session         — show current session info',
  ];

  bool _handleSlashCommand(String input) {
    final trimmed = input.trim();
    if (!trimmed.startsWith('/')) return false;

    _addLine(TerminalLine(type: TerminalLineType.userInput, content: trimmed));

    final parts = trimmed.split(' ');
    final command = parts[0].toLowerCase();
    final arg = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    switch (command) {
      case '/model':
        _handleModelCommand(arg);
        return true;
      case '/skills':
      case '/help':
        _addLine(TerminalLine(type: TerminalLineType.separator));
        _addLine(TerminalLine(type: TerminalLineType.text, content: 'Available commands:'));
        for (final skill in _availableSkills) {
          _addLine(TerminalLine(type: TerminalLineType.planStep, content: skill));
        }
        return true;
      case '/stop':
        _stopTask();
        return true;
      case '/clear':
        setState(() {
          _lines.clear();
          _sessionId = null; // fresh session on next prompt
        });
        return true;
      case '/provider':
        const knownProviders = ['claude', 'gemini', 'copilot', 'openrouter', 'ollama', 'azure'];
        if (arg.isNotEmpty && knownProviders.contains(arg.toLowerCase())) {
          _onProviderSwitch(arg.toLowerCase());
        } else {
          _addLine(TerminalLine(type: TerminalLineType.text, content: 'Active: $_activeProvider'));
          _addLine(TerminalLine(type: TerminalLineType.text, content: 'Usage: /provider <${knownProviders.join('|')}>'));
        }
        return true;
      case '/session':
        _addLine(TerminalLine(type: TerminalLineType.text, content: 'Session: ${_sessionId ?? "none (new)"}'));
        _addLine(TerminalLine(type: TerminalLineType.text, content: 'Provider: $_activeProvider'));
        _addLine(TerminalLine(type: TerminalLineType.text, content: 'Model: $_activeModel'));
        _addLine(TerminalLine(type: TerminalLineType.text, content: 'Connected: $_connected'));
        _addLine(TerminalLine(type: TerminalLineType.text, content: 'Task running: $_taskRunning'));
        if (_activeTaskId != null) {
          _addLine(TerminalLine(type: TerminalLineType.text, content: 'Active task: $_activeTaskId'));
        }
        return true;
      default:
        _addLine(TerminalLine(type: TerminalLineType.error, content: 'Unknown command: $command'));
        _addLine(TerminalLine(type: TerminalLineType.text, content: 'Type /skills to see available commands'));
        return true;
    }
  }

  void _handleModelCommand(String modelName) {
    if (modelName.isEmpty) {
      final models = modelsForProvider(_activeProvider);
      _addLine(TerminalLine(type: TerminalLineType.text, content: 'Current: $_activeModel ($_activeProvider)'));
      _addLine(TerminalLine(type: TerminalLineType.text, content: 'Available models:'));
      for (final m in models) {
        final marker = m.id == _activeModel ? ' *' : '';
        _addLine(TerminalLine(type: TerminalLineType.planStep, content: '  ${m.id}$marker'));
      }
      return;
    }
    _onModelSwitch(modelName);
  }

  /// Build autocomplete suggestions for the input bar based on the current
  /// text. Returns an empty list when there's nothing useful to suggest.
  List<CommandSuggestion> _suggestFor(String text) {
    if (!text.startsWith('/')) return const [];
    final sp = text.indexOf(' ');
    final cmd = sp == -1 ? text.toLowerCase() : text.substring(0, sp).toLowerCase();
    final arg = sp == -1 ? '' : text.substring(sp + 1).trim().toLowerCase();

    if (sp == -1) {
      const cmds = [
        ('/provider', 'switch AI provider'),
        ('/model', 'switch model within provider'),
        ('/session', 'show session info'),
        ('/stop', 'stop current task'),
        ('/clear', 'clear terminal'),
        ('/skills', 'list slash commands'),
      ];
      return [
        for (final c in cmds)
          if (c.$1.startsWith(cmd))
            CommandSuggestion(display: c.$1, value: '${c.$1} ', hint: c.$2),
      ];
    }

    if (cmd == '/provider') {
      const providers = [
        ('copilot', 'Copilot subscription (device-auth)'),
        ('claude', 'Direct Anthropic API'),
        ('gemini', 'Direct Google API'),
        ('openrouter', 'Many models, pay-per-token'),
        ('ollama', 'Local models on device'),
        ('azure', 'Azure OpenAI deployment'),
      ];
      return [
        for (final p in providers)
          if (arg.isEmpty || p.$1.startsWith(arg))
            CommandSuggestion(
              display: p.$1,
              value: '/provider ${p.$1}',
              hint: p.$2,
              autoSubmit: true,
            ),
      ];
    }

    if (cmd == '/model') {
      final models = modelsForProvider(_activeProvider);
      return [
        for (final m in models)
          if (arg.isEmpty ||
              m.id.toLowerCase().contains(arg) ||
              m.label.toLowerCase().contains(arg))
            CommandSuggestion(
              display: m.id,
              value: '/model ${m.id}',
              hint: '${m.label} · ${m.description}',
              autoSubmit: true,
            ),
      ];
    }

    return const [];
  }

  /// Switch model within the current provider by sending config.set to the backend.
  void _onModelSwitch(String modelId) {
    final api = context.read<OpenCodeAPI>();
    api.sendWsMessage({
      'type': 'config.set',
      'id': 'model-${DateTime.now().millisecondsSinceEpoch}',
      'payload': {
        'key': 'providers.$_activeProvider.model',
        'value': modelId,
      },
    });
    setState(() => _activeModel = modelId);
    _addLine(TerminalLine(type: TerminalLineType.text, content: 'Model: $modelId ($_activeProvider)'));
  }

  void _stopTask() {
    if (!_taskRunning) {
      _addLine(TerminalLine(type: TerminalLineType.text, content: 'No task running'));
      return;
    }
    if (_activeTaskId != null) {
      final api = context.read<OpenCodeAPI>();
      api.cancelTask(_activeTaskId!);
    }
    setState(() {
      _taskRunning = false;
      _activeTaskId = null;
    });
    _addLine(TerminalLine(type: TerminalLineType.text, content: 'Task stopped'));
  }

  void _onSubmit(String prompt) {
    // Handle slash commands locally (no login required)
    if (_handleSlashCommand(prompt)) return;

    // `!<cmd>` shell-bypass: run the command directly via the daemon's
    // shell_exec tool, skipping the LLM entirely. Useful for debugging the
    // sandbox runtime without paying for a round-trip.
    if (prompt.startsWith('!')) {
      _handleShellBypass(prompt.substring(1));
      return;
    }

    _addLine(TerminalLine(type: TerminalLineType.userInput, content: prompt));
    _addLine(TerminalLine(type: TerminalLineType.separator));

    final api = context.read<OpenCodeAPI>();

    setState(() => _taskRunning = true);
    _addLine(TerminalLine(type: TerminalLineType.agentThinking, content: 'Processing...'));

    String? taskId;
    if (_sessionId != null) {
      // Follow-up prompt — resume existing session with full context.
      taskId = api.resumeSession(_sessionId!, prompt);
    } else {
      // First prompt — generate session ID and start new task.
      _sessionId = 'session-${DateTime.now().millisecondsSinceEpoch}';
      taskId = api.startTask(prompt, provider: _activeProvider, taskId: _sessionId);
    }

    if (taskId == null) {
      _addLine(TerminalLine(type: TerminalLineType.error, content: 'Failed to send task (no WebSocket connection)'));
      setState(() => _taskRunning = false);
    } else {
      _activeTaskId = taskId;
    }
  }

  /// `!<cmd>` shell-bypass: send a direct_tool_call for shell_exec and render
  /// the result as a chat message. No LLM, no session — just the shell.
  void _handleShellBypass(String command) {
    final cmd = command.trim();
    if (cmd.isEmpty) {
      _addLine(TerminalLine(
        type: TerminalLineType.error,
        content: 'Usage: !<shell command> — e.g. !ls -la',
      ));
      return;
    }

    // Echo the command as user input so the chat history makes sense.
    _addLine(TerminalLine(
      type: TerminalLineType.userInput,
      content: '\$ $cmd',
    ));

    final api = context.read<OpenCodeAPI>();
    final id = api.sendDirectToolCall(
      'shell_exec',
      args: {'command': cmd, 'description': 'shell bypass: $cmd'},
    );

    if (id == null) {
      _addLine(TerminalLine(
        type: TerminalLineType.error,
        content: 'Failed to send direct tool call (no WebSocket connection)',
      ));
      return;
    }

    // Mark this id so _handleEvent knows it's a shell-bypass reply.
    _pendingDirectCalls.add(id);
    _addLine(TerminalLine(
      type: TerminalLineType.agentThinking,
      content: 'Running shell (bypass)...',
    ));
  }

  /// Pending direct_tool_call IDs waiting on a direct_tool_result.
  /// Used to distinguish our bypass traffic from any other ad-hoc calls.
  final Set<String> _pendingDirectCalls = <String>{};

  /// Render a direct_tool_result message (response to `!<cmd>`).
  void _handleDirectToolResult(String? id, Map<String, dynamic> payload) {
    _removeThinkingLines();

    final tool = payload['tool'] as String? ?? 'tool';
    final output = (payload['output'] as String? ?? '').trimRight();
    final errMsg = payload['error'] as String? ?? '';
    final metadata = payload['metadata'] as Map<String, dynamic>? ?? {};
    final runtimeLabel = metadata['runtime'] as String? ?? 'unknown';
    final exitCode = metadata['exit_code'];

    // Header: clearly mark this as a bypass + show which sandbox served it.
    // This is the runtime-debug signal the beta asked for.
    final header = '[shell bypass · runtime=$runtimeLabel'
        '${exitCode != null ? ' · exit=$exitCode' : ''}]';
    _addLine(TerminalLine(
      type: TerminalLineType.toolCall,
      content: '$header $tool',
    ));

    if (output.isNotEmpty) {
      _addToolResult(output);
    }
    if (errMsg.isNotEmpty && errMsg != 'exit code 0') {
      _addLine(TerminalLine(
        type: TerminalLineType.error,
        content: errMsg,
      ));
    }
    if (output.isEmpty && errMsg.isEmpty) {
      _addLine(TerminalLine(
        type: TerminalLineType.text,
        content: '(no output)',
      ));
    }
    _addLine(TerminalLine(type: TerminalLineType.separator));

    if (id != null) {
      _pendingDirectCalls.remove(id);
    }
  }

  void _onProviderSwitch(String provider) {
    // Pick the first model from the shared catalog as the default — keeps UI
    // and backend aligned with provider_switcher.dart's source of truth.
    final catalog = modelsForProvider(provider);
    final defaultModel = catalog.isNotEmpty ? catalog.first.id : '';

    final api = context.read<OpenCodeAPI>();
    final ts = DateTime.now().millisecondsSinceEpoch;
    api.sendWsMessage({
      'type': 'provider.switch',
      'id': 'sw-$ts',
      'payload': {'provider': provider},
    });
    if (defaultModel.isNotEmpty) {
      // Also sync backend model — otherwise it sticks with the provider's
      // compiled-in default and the UI label lies.
      api.sendWsMessage({
        'type': 'config.set',
        'id': 'swm-$ts',
        'payload': {
          'key': 'providers.$provider.model',
          'value': defaultModel,
        },
      });
    }

    setState(() {
      _activeProvider = provider;
      _activeModel = defaultModel;
    });
    _addLine(TerminalLine(type: TerminalLineType.text, content: 'Provider: $provider ($defaultModel)'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildStatusBar(),
            // Connection banner — shown when disconnected (after initial connect).
            if (!_connected && !_initializing)
              ConnectionBanner(
                isReconnecting: _reconnecting,
                attemptNumber: _reconnectAttempt > 0 ? _reconnectAttempt : null,
                onRetry: _manualRetry,
              ),
            // Degraded mode banner — proot configured but non-functional.
            if (_prootDegraded && !_prootDegradedDismissed)
              _buildDegradedBanner(),
            ProviderSwitcher(
              activeProvider: _activeProvider,
              activeModel: _activeModel,
              onProviderSwitch: _onProviderSwitch,
              onModelSwitch: _onModelSwitch,
            ),
            Expanded(
              child: _initializing
                  ? _buildInitialLoading()
                  : TerminalOutput(lines: _lines),
            ),
            InputBar(
              onSubmit: _onSubmit,
              disabled: !_connected,
              showMic: false,
              taskRunning: _taskRunning,
              onStop: _stopTask,
              suggest: _suggestFor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDegradedBanner() {
    const amber = AppColors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: amber.withAlpha(20),
        border: Border(bottom: BorderSide(color: amber.withAlpha(50), width: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: amber, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _prootDegradedError != null && _prootDegradedError!.length < 80
                  ? 'Shell runtime: $_prootDegradedError'
                  : 'Shell runtime unavailable — npm, pip, shell commands may not work. '
                    'See Config › Runtime for details.',
              style: AppTheme.uiFont(fontSize: 11, color: amber),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _prootDegradedDismissed = true),
            child: Icon(Icons.close_rounded, color: amber.withAlpha(150), size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ShimmerLoading(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: const Icon(Icons.terminal, color: AppColors.purple, size: 28),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            _bootstrapMessage ?? 'Connecting to daemon...',
            style: AppTheme.uiFont(fontSize: 14, color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_bootstrapPercent != null && _bootstrapPercent! > 0 && _bootstrapPercent! < 100) ...[
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                value: _bootstrapPercent! / 100.0,
                backgroundColor: AppColors.surface,
                color: AppColors.purple,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '$_bootstrapPercent%',
              style: AppTheme.codeFont(fontSize: 11, color: AppColors.textMuted),
            ),
          ] else
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.purple),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'mo-code',
                style: AppTheme.uiFont(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              if (_sessionId != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.purpleDim,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: Text(
                    'session',
                    style: AppTheme.uiFont(fontSize: 9, color: AppColors.purple, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ],
          ),
          Row(
            children: [
              _ConnectionDot(connected: _connected, reconnecting: _reconnecting),
              const SizedBox(width: AppSpacing.sm),
              Text(
                _connected
                    ? _activeProvider
                    : _reconnecting
                        ? 'reconnecting'
                        : 'disconnected',
                style: AppTheme.uiFont(
                  fontSize: 12,
                  color: _connected
                      ? AppColors.green
                      : _reconnecting
                          ? AppColors.amber
                          : AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Animated connection dot — pulses amber when reconnecting.
class _ConnectionDot extends StatefulWidget {
  final bool connected;
  final bool reconnecting;
  const _ConnectionDot({required this.connected, required this.reconnecting});

  @override
  State<_ConnectionDot> createState() => _ConnectionDotState();
}

class _ConnectionDotState extends State<_ConnectionDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.reconnecting) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_ConnectionDot old) {
    super.didUpdateWidget(old);
    if (widget.reconnecting && !old.reconnecting) {
      _pulse.repeat(reverse: true);
    } else if (!widget.reconnecting && old.reconnecting) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.connected
        ? AppColors.green
        : widget.reconnecting
            ? AppColors.amber
            : AppColors.red;

    final dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(80),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );

    if (!widget.reconnecting) return dot;

    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
      ),
      child: dot,
    );
  }
}
