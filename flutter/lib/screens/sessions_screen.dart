import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
        title: Text('Delete Session', style: AppTheme.uiFont(fontSize: 18, color: AppColors.white, fontWeight: FontWeight.w600)),
        content: Text(
          'This will permanently delete this session and its conversation history.',
          style: AppTheme.uiFont(fontSize: 14, color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppTheme.uiFont(fontSize: 14, color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: AppTheme.uiFont(fontSize: 14, color: AppColors.red, fontWeight: FontWeight.w600)),
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
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textMuted),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Sessions',
          style: AppTheme.uiFont(fontSize: 18, color: AppColors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textMuted),
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
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.redDim,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 32),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(_error!, style: AppTheme.uiFont(fontSize: 14, color: AppColors.textMuted)),
          const SizedBox(height: AppSpacing.md),
          TextButton(onPressed: _loadSessions, child: Text('Retry', style: AppTheme.uiFont(fontSize: 14, color: AppColors.purple, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: const Icon(Icons.history_rounded, color: AppColors.textMuted, size: 32),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'No sessions yet',
            style: AppTheme.uiFont(fontSize: 16, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Start a conversation in the Agent tab',
            style: AppTheme.uiFont(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList() {
    return ListView.builder(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
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
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      color: AppColors.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: const BorderSide(color: AppColors.border, width: 0.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _stateIcon(state),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      title,
                      style: AppTheme.uiFont(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted, size: 18),
                    color: AppColors.panel,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
                    onSelected: (value) {
                      HapticFeedback.selectionClick();
                      if (value == 'resume') onResume();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'resume',
                        child: Row(
                          children: [
                            const Icon(Icons.play_arrow_rounded, color: AppColors.green, size: 18),
                            const SizedBox(width: AppSpacing.sm),
                            Text('Resume', style: AppTheme.uiFont(fontSize: 14, color: AppColors.textPrimary)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline_rounded, color: AppColors.red, size: 18),
                            const SizedBox(width: AppSpacing.sm),
                            Text('Delete', style: AppTheme.uiFont(fontSize: 14, color: AppColors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  _providerBadge(provider),
                  const SizedBox(width: AppSpacing.sm),
                  _stateBadge(state),
                  const Spacer(),
                  Text(
                    '$messageCount msgs',
                    style: AppTheme.uiFont(fontSize: 11, color: AppColors.textMuted),
                  ),
                  if (updatedAt != null) ...[
                    Text(' \u00b7 ', style: AppTheme.uiFont(fontSize: 11, color: AppColors.textMuted)),
                    Text(
                      _formatTime(updatedAt),
                      style: AppTheme.uiFont(fontSize: 11, color: AppColors.textMuted),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.purpleDim.withAlpha(60),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        provider,
        style: AppTheme.uiFont(fontSize: 10, color: AppColors.purpleLight, fontWeight: FontWeight.w500),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        label,
        style: AppTheme.uiFont(fontSize: 10, color: color, fontWeight: FontWeight.w500),
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
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textMuted),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: AppTheme.uiFont(fontSize: 16, color: AppColors.white, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded, color: AppColors.green),
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
      return Center(
        child: Text('No messages in this session', style: AppTheme.uiFont(fontSize: 14, color: AppColors.textMuted)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
        title: Text('Resume Session', style: AppTheme.uiFont(fontSize: 18, color: AppColors.white, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          style: AppTheme.uiFont(fontSize: 14, color: AppColors.textPrimary),
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Continue with a new prompt...',
            hintStyle: AppTheme.uiFont(fontSize: 14, color: AppColors.textDisabled),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              borderSide: BorderSide.none,
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppTheme.uiFont(fontSize: 14, color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final prompt = controller.text.trim();
              if (prompt.isNotEmpty) {
                Navigator.pop(ctx);
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

    final roleColor = isUser ? AppColors.green : isAssistant ? AppColors.purple : AppColors.amber;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isUser
            ? AppColors.green.withAlpha(8)
            : isTool
                ? AppColors.amber.withAlpha(8)
                : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: isUser
              ? AppColors.green.withAlpha(25)
              : isTool
                  ? AppColors.amber.withAlpha(25)
                  : AppColors.border.withAlpha(80),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: roleColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  isUser ? Icons.person : isAssistant ? Icons.smart_toy_outlined : Icons.build_outlined,
                  size: 12,
                  color: roleColor,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                _roleLabel(role),
                style: AppTheme.uiFont(fontSize: 11, color: roleColor, fontWeight: FontWeight.w600),
              ),
              if (isTool) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  message['tool_call_id'] as String? ?? '',
                  style: AppTheme.codeFont(fontSize: 9, color: AppColors.textDisabled),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (content.isNotEmpty)
            SelectableText(
              content.length > 500 ? '${content.substring(0, 500)}...' : content,
              style: AppTheme.codeFont(fontSize: 12, color: AppColors.textPrimary),
            ),
          if (toolCalls != null && toolCalls.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final tc in toolCalls)
              Container(
                margin: const EdgeInsets.only(top: AppSpacing.xs),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.purple.withAlpha(10),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  'tool: ${(tc as Map)['name'] ?? 'unknown'}',
                  style: AppTheme.codeFont(fontSize: 11, color: AppColors.purple),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _roleLabel(String role) {
    return switch (role) {
      'user' => 'user',
      'assistant' => 'assistant',
      'tool' => 'tool result',
      'system' => 'system',
      _ => role,
    };
  }
}
