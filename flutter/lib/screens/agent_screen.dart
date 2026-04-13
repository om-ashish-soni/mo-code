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
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  final List<TerminalLine> _lines = [];
  String _activeProvider = 'copilot';
  String _activeModel = 'gpt-4o';
  bool _connected = false;
  bool _taskRunning = false;
  String? _activeTaskId;

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

  void _handleEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['type'] as String? ?? '';
    final payload = event['payload'];

    switch (type) {
      case 'agent.stream':
        // Streaming content from the agent
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
        setState(() {
          _taskRunning = false;
          _activeTaskId = null;
        });
        break;
      case 'task.failed':
        if (payload is Map<String, dynamic>) {
          final error = payload['error'] as String? ?? 'Unknown error';
          _addLine(TerminalLine(type: TerminalLineType.error, content: 'Task failed: $error'));
        } else {
          _addLine(TerminalLine(type: TerminalLineType.error, content: 'Task failed'));
        }
        setState(() {
          _taskRunning = false;
          _activeTaskId = null;
        });
        break;
      case 'error':
        if (payload is Map<String, dynamic>) {
          final message = payload['message'] as String? ?? 'Unknown error';
          _addLine(TerminalLine(type: TerminalLineType.error, content: message));
        }
        setState(() {
          _taskRunning = false;
          _activeTaskId = null;
        });
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
    '/provider <name> — switch provider (copilot, claude, gemini)',
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
        setState(() => _lines.clear());
        return true;
      case '/provider':
        if (arg.isNotEmpty && ['claude', 'gemini', 'copilot'].contains(arg.toLowerCase())) {
          _onProviderSwitch(arg.toLowerCase());
        } else {
          _addLine(TerminalLine(type: TerminalLineType.text, content: 'Active: $_activeProvider'));
          _addLine(TerminalLine(type: TerminalLineType.text, content: 'Usage: /provider <claude|gemini|copilot>'));
        }
        return true;
      case '/session':
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
      // List available models for current provider.
      final models = switch (_activeProvider) {
        'copilot' => copilotModels,
        'claude' => claudeModels,
        'gemini' => geminiModels,
        _ => <dynamic>[],
      };
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

    _addLine(TerminalLine(type: TerminalLineType.userInput, content: prompt));
    _addLine(TerminalLine(type: TerminalLineType.separator));

    final api = context.read<OpenCodeAPI>();

    setState(() => _taskRunning = true);
    _addLine(TerminalLine(type: TerminalLineType.agentThinking, content: 'Processing...'));

    final taskId = api.startTask(prompt, provider: _activeProvider);

    if (taskId == null) {
      _addLine(TerminalLine(type: TerminalLineType.error, content: 'Failed to send task (no WebSocket connection)'));
      setState(() => _taskRunning = false);
    } else {
      _activeTaskId = taskId;
    }
  }

  void _onProviderSwitch(String provider) {
    // Set default model for the new provider.
    final defaultModel = switch (provider) {
      'copilot' => 'gpt-4o',
      'claude' => 'claude-sonnet-4-20250514',
      'gemini' => 'gemini-2.5-flash',
      _ => 'gpt-4o',
    };

    final api = context.read<OpenCodeAPI>();
    api.sendWsMessage({
      'type': 'provider.switch',
      'id': 'sw-${DateTime.now().millisecondsSinceEpoch}',
      'payload': {'provider': provider},
    });

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
            ),
          ],
        ),
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
              '${_bootstrapPercent}%',
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
          Text(
            'mo-code',
            style: AppTheme.uiFont(
              fontSize: 13,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
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
