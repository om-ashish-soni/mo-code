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
  String? _currentTaskId;
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    _initConnection();
  }

  Future<void> _initConnection() async {
    await Future.delayed(const Duration(milliseconds: 500));
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    final api = context.read<OpenCodeAPI>();
    try {
      await api.connect();
      setState(() => _connected = true);
      _addLine(TerminalLine(type: TerminalLineType.text, content: 'Connected to OpenCode server'));
      
      final session = await api.createSession(title: 'Mo-Code Mobile Session');
      if (session != null) {
        _sessionId = session;
        setState(() {});
        _addLine(TerminalLine(type: TerminalLineType.text, content: 'Session created: $_sessionId'));
      }
      
      api.responses.listen(_handleResponse);
      api.messages.listen(_handleEvent);
      api.connection.listen((c) {
        setState(() => _connected = c);
        if (!c) {
          _addLine(TerminalLine(type: TerminalLineType.error, content: 'Disconnected from server'));
        }
      });
    } catch (e) {
      setState(() => _connected = false);
      _addLine(TerminalLine(type: TerminalLineType.error, content: 'Connection failed: $e'));
    }
  }

  void _handleResponse(Map<String, dynamic> response) {
    final info = response['info'] as Map<String, dynamic>?;
    final parts = response['parts'] as List<dynamic>?;
    
    if (parts != null) {
      _processParts(parts.cast<Map<String, dynamic>>());
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

  void _onSubmit(String prompt) async {
    if (_sessionId == null) {
      _addLine(TerminalLine(type: TerminalLineType.error, content: 'No session available'));
      return;
    }
    
    _addLine(TerminalLine(type: TerminalLineType.userInput, content: prompt));
    _addLine(TerminalLine(type: TerminalLineType.separator));
    
    final api = context.read<OpenCodeAPI>();
    _currentTaskId = 'task-${DateTime.now().millisecondsSinceEpoch}';
    
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
          model = 'github-copilot/claude-4.5-sonnet';
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
              disabled: _taskRunning || !_connected || _sessionId == null,
              showMic: false,
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
