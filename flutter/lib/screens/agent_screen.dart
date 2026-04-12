import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/daemon.dart';
import '../theme/colors.dart';
import '../models/messages.dart';
import '../widgets/terminal_output.dart';
import '../widgets/provider_switcher.dart';
import '../widgets/input_bar.dart';

class AgentScreen extends StatefulWidget {
  const AgentScreen({super.key});

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  final List<TerminalLine> _lines = [];
  String _activeProvider = 'copilot';
  bool _connected = false;
  bool _taskRunning = false;
  String? _activeTaskId;

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
    _messageSub?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }

  Future<void> _initConnection() async {
    await Future.delayed(const Duration(milliseconds: 500));
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    final api = context.read<OpenCodeAPI>();
    try {
      await api.connect();
      if (!mounted) return;
      setState(() => _connected = true);
      _addLine(TerminalLine(type: TerminalLineType.text, content: 'Connected to mo-code daemon'));

      _messageSub = api.messages.listen(_handleEvent);
      _connectionSub = api.connection.listen((c) {
        if (!mounted) return;
        setState(() => _connected = c);
        if (!c) {
          _addLine(TerminalLine(type: TerminalLineType.error, content: 'Disconnected from server'));
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _connected = false);
      _addLine(TerminalLine(type: TerminalLineType.error, content: 'Connection failed: $e'));
    }
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

  // --- Slash command definitions ---
  static const _availableModels = {
    'claude': ['claude-4-sonnet', 'claude-4-opus', 'claude-3.5-haiku'],
    'gemini': ['gemini-2.5-pro', 'gemini-2.5-flash'],
    'copilot': ['gpt-4o', 'claude-4-sonnet'],
  };

  static const _availableSkills = [
    '/model <name>    — switch model (e.g. /model gemini-2.5-pro)',
    '/skills          — list available slash commands',
    '/stop            — stop current task',
    '/clear           — clear terminal output',
    '/provider <name> — switch provider (claude, gemini, copilot)',
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
      _showModelPicker();
      return;
    }
    _selectModel(modelName);
  }

  void _selectModel(String modelName) {
    // Find which provider has this model
    String? resolvedProvider;
    for (final entry in _availableModels.entries) {
      if (entry.value.contains(modelName)) {
        resolvedProvider = entry.key;
        break;
      }
    }
    if (resolvedProvider != null && resolvedProvider != _activeProvider) {
      _onProviderSwitch(resolvedProvider);
    }
    _addLine(TerminalLine(type: TerminalLineType.text, content: 'Model set to: $modelName'));
  }

  void _showModelPicker() {
    final models = _availableModels[_activeProvider] ?? [];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            border: Border(
              top: BorderSide(color: AppColors.border),
              left: BorderSide(color: AppColors.border),
              right: BorderSide(color: AppColors.border),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  'Models — $_activeProvider',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
              ),
              const Divider(color: AppColors.border, height: 1),
              ...models.map((model) => InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _selectModel(model);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    model,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontFamily: 'JetBrainsMono',
                    ),
                  ),
                ),
              )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
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
    setState(() => _activeProvider = provider);
    _addLine(TerminalLine(type: TerminalLineType.text, content: 'Provider switched to $provider'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildStatusBar(),
            ProviderSwitcher(
              activeProvider: _activeProvider,
              onSwitch: _onProviderSwitch,
            ),
            Expanded(child: TerminalOutput(lines: _lines)),
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

  Widget _buildStatusBar() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'mo-code',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: _connected ? AppColors.green : AppColors.red,
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                _connected ? _activeProvider : 'disconnected',
                style: TextStyle(
                  color: _connected ? AppColors.green : AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
