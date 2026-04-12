import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/daemon.dart';
import '../theme/colors.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = false;
  String? _error;
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _listenForUpdates();
    _loadSessions();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  void _listenForUpdates() {
    final api = context.read<OpenCodeAPI>();
    _wsSub = api.messages.listen((msg) {
      final type = msg['type'] as String?;
      if (type == 'session.list_result') {
        final payload = msg['payload'];
        if (payload is List) {
          setState(() {
            _sessions = payload.cast<Map<String, dynamic>>();
            _loading = false;
            _error = null;
          });
        }
      }
    });
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final api = context.read<OpenCodeAPI>();

    if (!api.isConnected) {
      // Fall back to HTTP API.
      final sessions = await api.listSessions();
      setState(() {
        _sessions = sessions ?? [];
        _loading = false;
        if (sessions == null) _error = 'Failed to load sessions';
      });
      return;
    }

    // Request via WS.
    final id = api.requestSessionList();
    if (id == null) {
      setState(() {
        _loading = false;
        _error = 'Not connected to daemon';
      });
    }
    // Response will arrive via _listenForUpdates.
    // Add a timeout fallback.
    Future.delayed(const Duration(seconds: 5), () {
      if (_loading && mounted) {
        setState(() {
          _loading = false;
          _error = 'Request timed out';
        });
      }
    });
  }

  Future<void> _deleteSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Delete Session', style: TextStyle(color: AppColors.white)),
        content: const Text(
          'This will permanently delete this session and its conversation history.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final api = context.read<OpenCodeAPI>();
      api.deleteSession(sessionId);
      // Optimistic removal.
      setState(() {
        _sessions.removeWhere((s) => s['id'] == sessionId);
      });
    }
  }

  void _resumeSession(Map<String, dynamic> session) {
    final sessionId = session['id'] as String;
    Navigator.pop(context, {'action': 'resume', 'session_id': sessionId});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.panel,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textMuted),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Sessions',
          style: TextStyle(color: AppColors.white, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textMuted),
            onPressed: _loadSessions,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
          : _error != null
              ? _buildErrorState()
              : _sessions.isEmpty
                  ? _buildEmptyState()
                  : _buildSessionList(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: AppColors.red, size: 48),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 12),
          TextButton(onPressed: _loadSessions, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, color: AppColors.textMuted, size: 48),
          SizedBox(height: 12),
          Text(
            'No sessions yet',
            style: TextStyle(color: AppColors.textMuted, fontSize: 16),
          ),
          SizedBox(height: 6),
          Text(
            'Start a conversation in the Agent tab',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList() {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _sessions.length,
      itemBuilder: (context, index) {
        final session = _sessions[index];
        return _SessionCard(
          session: session,
          onTap: () => _showSessionDetail(session),
          onResume: () => _resumeSession(session),
          onDelete: () => _deleteSession(session['id'] as String),
        );
      },
    );
  }

  void _showSessionDetail(Map<String, dynamic> session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Provider.value(
          value: context.read<OpenCodeAPI>(),
          child: SessionDetailScreen(session: session),
        ),
      ),
    ).then((result) {
      if (result is Map && result['action'] == 'resume' && mounted) {
        Navigator.pop(context, result);
      }
    });
  }
}

class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final VoidCallback onTap;
  final VoidCallback onResume;
  final VoidCallback onDelete;

  const _SessionCard({
    required this.session,
    required this.onTap,
    required this.onResume,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final title = session['title'] as String? ?? 'Untitled';
    final provider = session['provider'] as String? ?? '';
    final state = session['state'] as String? ?? 'active';
    final messageCount = session['message_count'] as int? ?? 0;
    final updatedAt = session['updated_at'] as String?;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: AppColors.panel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _stateIcon(state),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: AppColors.textMuted, size: 18),
                    color: AppColors.panel,
                    onSelected: (value) {
                      if (value == 'resume') onResume();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'resume',
                        child: Row(
                          children: [
                            Icon(Icons.play_arrow, color: AppColors.green, size: 18),
                            SizedBox(width: 8),
                            Text('Resume', style: TextStyle(color: AppColors.textPrimary)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: AppColors.red, size: 18),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: AppColors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _providerBadge(provider),
                  const SizedBox(width: 8),
                  _stateBadge(state),
                  const Spacer(),
                  Text(
                    '$messageCount msgs',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                  if (updatedAt != null) ...[
                    const Text(' \u00b7 ', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    Text(
                      _formatTime(updatedAt),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stateIcon(String state) {
    final (IconData icon, Color color) = switch (state) {
      'active' => (Icons.play_circle_filled, AppColors.amber),
      'completed' => (Icons.check_circle, AppColors.green),
      'failed' => (Icons.error, AppColors.red),
      'canceled' => (Icons.cancel, AppColors.textMuted),
      _ => (Icons.circle, AppColors.textMuted),
    };
    return Icon(icon, color: color, size: 24);
  }

  Widget _providerBadge(String provider) {
    if (provider.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.purple.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        provider,
        style: const TextStyle(color: AppColors.purple, fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _stateBadge(String state) {
    final (String label, Color color) = switch (state) {
      'active' => ('Running', AppColors.amber),
      'completed' => ('Done', AppColors.green),
      'failed' => ('Failed', AppColors.red),
      'canceled' => ('Canceled', AppColors.textMuted),
      _ => (state, AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }

  String _formatTime(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }
}

// ---------------------------------------------------------------------------
// Session detail screen — shows conversation history and allows resume
// ---------------------------------------------------------------------------

class SessionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  Map<String, dynamic>? _fullSession;
  bool _loading = true;
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _listenForSession();
    _loadFullSession();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  void _listenForSession() {
    final api = context.read<OpenCodeAPI>();
    _wsSub = api.messages.listen((msg) {
      final type = msg['type'] as String?;
      if (type == 'session.get_result') {
        final payload = msg['payload'];
        if (payload is Map<String, dynamic>) {
          setState(() {
            _fullSession = payload;
            _loading = false;
          });
        }
      }
    });
  }

  void _loadFullSession() {
    final api = context.read<OpenCodeAPI>();
    final sessionId = widget.session['id'] as String;
    api.requestSessionGet(sessionId);

    // Timeout fallback.
    Future.delayed(const Duration(seconds: 5), () {
      if (_loading && mounted) {
        setState(() {
          _loading = false;
          // Use the summary data we already have.
          _fullSession = widget.session;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.session['title'] as String? ?? 'Session';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.panel,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textMuted),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: const TextStyle(color: AppColors.white, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow, color: AppColors.green),
            onPressed: () => _showResumeDialog(),
            tooltip: 'Resume session',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
          : _buildConversation(),
    );
  }

  Widget _buildConversation() {
    final messages = _fullSession?['messages'] as List? ?? [];
    if (messages.isEmpty) {
      return const Center(
        child: Text('No messages in this session', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index] as Map<String, dynamic>;
        return _MessageBubble(message: msg);
      },
    );
  }

  void _showResumeDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Resume Session', style: TextStyle(color: AppColors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.textPrimary),
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Continue with a new prompt...',
            filled: true,
            fillColor: AppColors.background,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final prompt = controller.text.trim();
              if (prompt.isNotEmpty) {
                Navigator.pop(ctx); // close dialog
                Navigator.pop(context, {
                  'action': 'resume',
                  'session_id': widget.session['id'],
                  'prompt': prompt,
                });
              }
            },
            child: const Text('Resume'),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final role = message['role'] as String? ?? 'unknown';
    final content = message['content'] as String? ?? '';
    final toolCalls = message['tool_calls'] as List?;

    final isUser = role == 'user';
    final isAssistant = role == 'assistant';
    final isTool = role == 'tool';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUser
            ? AppColors.green.withAlpha(15)
            : isTool
                ? AppColors.amber.withAlpha(15)
                : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isUser
              ? AppColors.green.withAlpha(40)
              : isTool
                  ? AppColors.amber.withAlpha(40)
                  : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _roleLabel(role),
                style: TextStyle(
                  color: isUser ? AppColors.green : isAssistant ? AppColors.purple : AppColors.amber,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isTool) ...[
                const SizedBox(width: 6),
                Text(
                  message['tool_call_id'] as String? ?? '',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (content.isNotEmpty)
            SelectableText(
              content.length > 500 ? '${content.substring(0, 500)}...' : content,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          if (toolCalls != null && toolCalls.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final tc in toolCalls)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.purple.withAlpha(20),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'tool: ${(tc as Map)['name'] ?? 'unknown'}',
                  style: const TextStyle(color: AppColors.purple, fontSize: 11),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _roleLabel(String role) {
    return switch (role) {
      'user' => '\$ user',
      'assistant' => '> assistant',
      'tool' => '~ tool result',
      'system' => '# system',
      _ => role,
    };
  }
}
