import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/daemon.dart';
import '../theme/colors.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = false;
  String? _workingDir;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);

    final api = context.read<OpenCodeAPI>();
    final sessions = await api.listSessions(directory: _workingDir);

    setState(() {
      _sessions = sessions ?? [];
      _loading = false;
    });
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
          : _sessions.isEmpty
              ? _buildEmptyState()
              : _buildSessionList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.list_alt, color: AppColors.textMuted, size: 48),
          const SizedBox(height: 12),
          const Text(
            'No tasks yet',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _loadSessions,
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList() {
    return ListView.builder(
      itemCount: _sessions.length,
      itemBuilder: (context, index) {
        final session = _sessions[index];
        final title = session['title'] as String? ?? 'Untitled';
        final time = session['time'] as Map<String, dynamic>?;
        final updated = time?['updated'] as int?;
        final slug = session['slug'] as String? ?? '';

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: AppColors.panel,
          child: ListTile(
            onTap: () {
              // TODO: navigate to session detail view
            },
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.purple.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.chat_bubble, color: AppColors.purple, size: 20),
            ),
            title: Text(
              title,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Row(
              children: [
                Text(
                  slug,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
                const Text(' · ', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                Text(
                  _formatTime(updated),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ),
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
