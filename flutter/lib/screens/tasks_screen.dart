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
        elevation: 0,
        title: Text(
          'Tasks',
          style: AppTheme.uiFont(fontSize: 18, color: AppColors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textMuted),
            onPressed: _loadSessions,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, color: AppColors.textMuted),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      color: AppColors.panel,
      child: Row(
        children: [
          const Icon(Icons.folder_rounded, color: AppColors.amber, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _workingDir!,
              style: AppTheme.codeFont(fontSize: 12, color: AppColors.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() => _workingDir = null);
              _loadSessions();
            },
            child: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 14),
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
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: const Icon(Icons.list_alt_rounded, color: AppColors.textMuted, size: 32),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'No tasks yet',
            style: AppTheme.uiFont(fontSize: 15, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tasks will appear here when you send prompts\nto the agent.',
            style: AppTheme.uiFont(fontSize: 12, color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          ElevatedButton.icon(
            onPressed: _loadSessions,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.lg),
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
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      color: AppColors.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: const BorderSide(color: AppColors.border, width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        leading: _StateIcon(state: state),
        title: Text(
          title,
          style: AppTheme.uiFont(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            if (provider != null) ...[
              _ProviderBadge(provider: provider),
              const SizedBox(width: AppSpacing.sm),
            ],
            if (state.isNotEmpty) ...[
              _StateBadge(state: state),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(
              formatTime(updated),
              style: AppTheme.uiFont(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 18),
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
      'active' || 'running' => (Icons.play_circle_rounded, AppColors.green),
      'completed' || 'done' => (Icons.check_circle_rounded, AppColors.blue),
      'failed' || 'error' => (Icons.error_rounded, AppColors.red),
      'canceled' || 'cancelled' => (Icons.cancel_rounded, AppColors.amber),
      _ => (Icons.chat_bubble_rounded, AppColors.purple),
    };

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        state,
        style: AppTheme.uiFont(fontSize: 10, color: color, fontWeight: FontWeight.w500),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
      title: Text('Working Directory', style: AppTheme.uiFont(fontSize: 18, color: AppColors.white, fontWeight: FontWeight.w600)),
      content: TextField(
        controller: _controller,
        style: AppTheme.codeFont(fontSize: 14, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: '/path/to/project',
          hintStyle: AppTheme.codeFont(fontSize: 14, color: AppColors.textDisabled),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: AppTheme.uiFont(fontSize: 14, color: AppColors.textMuted)),
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
