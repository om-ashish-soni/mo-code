import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/daemon.dart';
import '../theme/colors.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/connection_banner.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = false;
  bool _loadFailed = false;
  String? _loadError;
  String? _workingDir;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _loadError = null;
    });

    final api = context.read<OpenCodeAPI>();
    try {
      final sessions = await api.listSessions(directory: _workingDir);
      if (!mounted) return;
      setState(() {
        _sessions = sessions ?? [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
        _loadError = e.toString();
      });
    }
  }

  String _formatTime(int? timestamp) {
    if (timestamp == null) return 'Unknown';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.panel,
        title: const Text(
          'Tasks',
          style: TextStyle(color: AppColors.white, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textMuted),
            onPressed: _loadSessions,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open, color: AppColors.textMuted),
            onPressed: _showDirectoryPicker,
            tooltip: 'Change directory',
          ),
        ],
      ),
      body: SelectionArea(
        child: Column(
          children: [
            if (_workingDir != null) _buildDirectoryBanner(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectoryBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppColors.panel,
      child: Row(
        children: [
          const Icon(Icons.folder, color: AppColors.amber, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _workingDir!,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() => _workingDir = null);
              _loadSessions();
            },
            child: const Icon(Icons.close, color: AppColors.textMuted, size: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && _sessions.isEmpty) {
      return _buildLoadingSkeleton();
    }

    if (_loadFailed) {
      return ErrorStateWidget(
        message: 'Failed to load tasks',
        detail: _loadError,
        onRetry: _loadSessions,
      );
    }

    if (_sessions.isEmpty) return _buildEmptyState();

    return RefreshIndicator(
      onRefresh: _loadSessions,
      color: AppColors.purple,
      backgroundColor: AppColors.panel,
      child: _buildSessionList(),
    );
  }

  Widget _buildLoadingSkeleton() {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: SkeletonCardList(itemCount: 6),
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
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.list_alt, color: AppColors.textMuted, size: 32),
          ),
          const SizedBox(height: 16),
          const Text(
            'No tasks yet',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tasks will appear here when you send prompts\nto the agent.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadSessions,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: _sessions.length,
      itemBuilder: (context, index) {
        final session = _sessions[index];
        return _TaskCard(
          session: session,
          formatTime: _formatTime,
        );
      },
    );
  }

  void _showDirectoryPicker() {
    showDialog(
      context: context,
      builder: (context) => DirectoryPickerDialog(
        onSelect: (dir) {
          setState(() => _workingDir = dir);
          _loadSessions();
        },
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final String Function(int?) formatTime;

  const _TaskCard({required this.session, required this.formatTime});

  @override
  Widget build(BuildContext context) {
    final title = session['title'] as String? ?? 'Untitled';
    final time = session['time'] as Map<String, dynamic>?;
    final updated = time?['updated'] as int?;
    final state = session['state'] as String? ?? '';
    final provider = session['provider'] as String?;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border, width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: _StateIcon(state: state),
        title: Text(
          title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            if (provider != null) ...[
              _ProviderBadge(provider: provider),
              const SizedBox(width: 6),
            ],
            if (state.isNotEmpty) ...[
              _StateBadge(state: state),
              const SizedBox(width: 6),
            ],
            Text(
              formatTime(updated),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
        onTap: () {
          // TODO: navigate to session detail view
        },
      ),
    );
  }
}

class _StateIcon extends StatelessWidget {
  final String state;
  const _StateIcon({required this.state});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (state) {
      'active' || 'running' => (Icons.play_circle, AppColors.green),
      'completed' || 'done' => (Icons.check_circle, AppColors.blue),
      'failed' || 'error' => (Icons.error, AppColors.red),
      'canceled' || 'cancelled' => (Icons.cancel, AppColors.amber),
      _ => (Icons.chat_bubble, AppColors.purple),
    };

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _StateBadge extends StatelessWidget {
  final String state;
  const _StateBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final Color color = switch (state) {
      'active' || 'running' => AppColors.green,
      'completed' || 'done' => AppColors.blue,
      'failed' || 'error' => AppColors.red,
      'canceled' || 'cancelled' => AppColors.amber,
      _ => AppColors.textMuted,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        state,
        style: TextStyle(color: color, fontSize: 10),
      ),
    );
  }
}

class _ProviderBadge extends StatelessWidget {
  final String provider;
  const _ProviderBadge({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.purple.withAlpha(20),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        provider,
        style: const TextStyle(color: AppColors.purple, fontSize: 10),
      ),
    );
  }
}

class DirectoryPickerDialog extends StatefulWidget {
  final Function(String) onSelect;

  const DirectoryPickerDialog({super.key, required this.onSelect});

  @override
  State<DirectoryPickerDialog> createState() => _DirectoryPickerDialogState();
}

class _DirectoryPickerDialogState extends State<DirectoryPickerDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: const Text('Working Directory', style: TextStyle(color: AppColors.white)),
      content: TextField(
        controller: _controller,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: const InputDecoration(
          hintText: '/path/to/project',
          filled: true,
          fillColor: AppColors.background,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSelect(_controller.text);
            Navigator.pop(context);
          },
          child: const Text('Select'),
        ),
      ],
    );
  }
}
