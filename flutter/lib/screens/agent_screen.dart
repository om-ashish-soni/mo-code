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
  String _activeProvider = 'claude';
  bool _connected = false;
  bool _taskRunning = false;
  String? _sessionId;

  // Track subscriptions for cleanup
  StreamSubscription? _responseSub;
  StreamSubscription? _messageSub;
  StreamSubscription? _connectionSub;

  @override
  void initState() {
    super.initState();
    _initConnection();
  }

  @override
  void dispose() {
    _responseSub?.cancel();
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

      final session = await api.createSession(title: 'Mo-Code Mobile Session');
      if (!mounted) return;
      if (session != null) {
        _sessionId = session;
        setState(() {});
        _addLine(TerminalLine(type: TerminalLineType.text, content: 'Session created: $_sessionId'));
      }

      _responseSub = api.responses.listen(_handleResponse);
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

  void _handleResponse(Map<String, dynamic> response) {
    if (!mounted) return;
    final info = response['info'] as Map<String, dynamic>?;
    final parts = response['parts'] as List<dynamic>?;

    if (parts != null && parts.isNotEmpty) {
      try {
        _processParts(parts.cast<Map<String, dynamic>>());
      } catch (e) {
        debugPrint('Failed to parse response parts: $e');
      }
    }
    
    if (info != null) {
      final finish = info['finish'] as String?;
      if (finish == 'stop' || finish == 'maxTokens') {
        _addLine(TerminalLine(type: TerminalLineType.separator));
        _addLine(TerminalLine(type: TerminalLineType.text, content: 'Task completed'));
        setState(() => _taskRunning = false);
      }
    }
  }

  void _processParts(List<Map<String, dynamic>> parts) {
    for (final part in parts) {
      final partType = part['type'] as String?;
      
      switch (partType) {
        case 'text':
          final text = part['text'] as String? ?? '';
          if (text.isNotEmpty) {
            _addLine(TerminalLine(type: TerminalLineType.text, content: text));
          }
          break;
        case 'tool_use':
          final name = part['name'] as String? ?? 'unknown';
          final input = part['input'] as Map<String, dynamic>?;
          final path = input?['path'] as String?;
          _addLine(TerminalLine(
            type: TerminalLineType.toolCall, 
            content: path != null ? '$name: $path' : name,
          ));
          break;
        case 'tool_result':
          final content = part['content'] as String? ?? '';
          if (content.isNotEmpty) {
            _addLine(TerminalLine(type: TerminalLineType.text, content: content));
          }
          break;
        case 'step-start':
          _addLine(TerminalLine(type: TerminalLineType.agentThinking, content: 'Thinking...'));
          break;
        case 'step-finish':
          final tokens = part['tokens'] as Map<String, dynamic>?;
          if (tokens != null) {
            final total = tokens['total'] as int? ?? 0;
            _addLine(TerminalLine(type: TerminalLineType.tokenCount, content: '$total tokens'));
          }
          break;
      }
    }
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String? ?? '';
    
    switch (type) {
      case 'session.created':
        final id = event['sessionID'] as String?;
        if (id != null && _sessionId == null) {
          setState(() => _sessionId = id);
        }
        break;
      case 'session.done':
        _addLine(TerminalLine(type: TerminalLineType.separator));
        _addLine(TerminalLine(type: TerminalLineType.text, content: 'Task completed'));
        setState(() => _taskRunning = false);
        break;
      case 'session.error':
        final error = event['error'] ?? event['message'] ?? 'Unknown error';
        _addLine(TerminalLine(type: TerminalLineType.error, content: 'Error: $error'));
        setState(() => _taskRunning = false);
        break;
      default:
        debugPrint('Unhandled event: $type');
    }
  }

  void _addLine(TerminalLine line) {
    setState(() => _lines.add(line));
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
        _addLine(TerminalLine(type: TerminalLineType.text, content: 'Session: ${_sessionId ?? "none"}'));
        _addLine(TerminalLine(type: TerminalLineType.text, content: 'Provider: $_activeProvider'));
        _addLine(TerminalLine(type: TerminalLineType.text, content: 'Connected: $_connected'));
        return true;
      default:
        _addLine(TerminalLine(type: TerminalLineType.error, content: 'Unknown command: $command'));
        _addLine(TerminalLine(type: TerminalLineType.text, content: 'Type /skills to see available commands'));
        return true;
    }
  }

  void _handleModelCommand(String modelName) {
    if (modelName.isEmpty) {
      _addLine(TerminalLine(type: TerminalLineType.separator));
      _addLine(TerminalLine(type: TerminalLineType.text, content: 'Models for $_activeProvider:'));
      final models = _availableModels[_activeProvider] ?? [];
      for (final m in models) {
        _addLine(TerminalLine(type: TerminalLineType.planStep, content: '  $m'));
      }
      _addLine(TerminalLine(type: TerminalLineType.text, content: 'Usage: /model <name>'));
      return;
    }
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

  void _stopTask() {
    if (!_taskRunning) {
      _addLine(TerminalLine(type: TerminalLineType.text, content: 'No task running'));
      return;
    }
    final api = context.read<OpenCodeAPI>();
    if (_sessionId != null) {
      api.cancelSession(_sessionId!);
    }
    setState(() => _taskRunning = false);
    _addLine(TerminalLine(type: TerminalLineType.text, content: 'Task stopped'));
  }

  void _onSubmit(String prompt) async {
    // Handle slash commands locally (no login required)
    if (_handleSlashCommand(prompt)) return;

    if (_sessionId == null) {
      _addLine(TerminalLine(type: TerminalLineType.error, content: 'No session available'));
      return;
    }

    _addLine(TerminalLine(type: TerminalLineType.userInput, content: prompt));
    _addLine(TerminalLine(type: TerminalLineType.separator));

    final api = context.read<OpenCodeAPI>();

    try {
      String model;
      switch (_activeProvider) {
        case 'claude':
          model = 'anthropic/claude-4-sonnet';
          break;
        case 'gemini':
          model = 'google/gemini-2.5-pro';
          break;
        case 'copilot':
          model = 'github-copilot/gpt-4o';
          break;
        default:
          model = 'anthropic/claude-4-sonnet';
      }

      setState(() => _taskRunning = true);
      _addLine(TerminalLine(type: TerminalLineType.agentThinking, content: 'Processing...'));

      final result = await api.sendMessage(_sessionId!, prompt, model: model);

      if (result == null) {
        _addLine(TerminalLine(type: TerminalLineType.error, content: 'Failed to send message'));
        setState(() => _taskRunning = false);
      }
    } catch (e) {
      _addLine(TerminalLine(type: TerminalLineType.error, content: 'Error: $e'));
      setState(() => _taskRunning = false);
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
              disabled: !_connected || _sessionId == null,
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
