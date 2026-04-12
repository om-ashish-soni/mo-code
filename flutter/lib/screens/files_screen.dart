import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/daemon.dart';
import '../theme/colors.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _selectedFile;
  String? _fileContent;
  bool _loading = false;
  String? _workingDir;
  Timer? _debounce;

  // Content search mode
  bool _searchContent = false;
  List<Map<String, dynamic>> _contentResults = [];

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (_searchContent) {
        _searchInFiles(query);
      } else {
        _searchFiles(query);
      }
    });
  }

  Future<void> _searchFiles(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _selectedFile = null;
        _fileContent = null;
      });
      return;
    }

    setState(() => _loading = true);

    final api = context.read<OpenCodeAPI>();
    final results = await api.findFiles(query, directory: _workingDir);

    if (!mounted) return;
    setState(() {
      _searchResults = results ?? [];
      _contentResults = [];
      _loading = false;
    });
  }

  Future<void> _searchInFiles(String query) async {
    if (query.isEmpty) {
      setState(() {
        _contentResults = [];
        _searchResults = [];
      });
      return;
    }

    setState(() => _loading = true);

    final api = context.read<OpenCodeAPI>();
    final results = await api.findInFiles(query, directory: _workingDir);

    if (!mounted) return;
    setState(() {
      _contentResults = results ?? [];
      _searchResults = [];
      _loading = false;
    });
  }

  Future<void> _loadFileContent(String path) async {
    setState(() => _loading = true);

    final api = context.read<OpenCodeAPI>();
    final content = await api.getFileContent(path, directory: _workingDir);

    if (!mounted) return;
    setState(() {
      _fileContent = content?['content'] as String? ?? 'No content';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.panel,
        title: const Text(
          'Files',
          style: TextStyle(color: AppColors.white, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _searchContent ? Icons.text_snippet : Icons.insert_drive_file_outlined,
              color: _searchContent ? AppColors.purple : AppColors.textMuted,
            ),
            onPressed: () {
              setState(() {
                _searchContent = !_searchContent;
                _searchResults = [];
                _contentResults = [];
              });
              if (_searchController.text.isNotEmpty) {
                _onSearchChanged(_searchController.text);
              }
            },
            tooltip: _searchContent ? 'Search by filename' : 'Search file contents',
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
            _buildSearchBar(),
            if (_workingDir != null) _buildDirectoryBanner(),
            if (_searchContent) _buildSearchModeBanner(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
                  : _searchContent
                      ? _contentResults.isEmpty
                          ? _buildEmptyState()
                          : _buildContentResults()
                      : _searchResults.isEmpty
                          ? _buildEmptyState()
                          : _buildFileList(),
            ),
            if (_selectedFile != null && _fileContent != null)
              Expanded(child: _buildFileViewer()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppColors.panel,
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: _searchContent ? 'Search in file contents...' : 'Search files by name...',
          prefixIcon: Icon(
            _searchContent ? Icons.search : Icons.filter_list,
            color: AppColors.textMuted,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: AppColors.textMuted),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
        onChanged: _onSearchChanged,
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
            onTap: () => setState(() => _workingDir = null),
            child: const Icon(Icons.close, color: AppColors.textMuted, size: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchModeBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: AppColors.purple.withAlpha(15),
      child: const Row(
        children: [
          Icon(Icons.text_snippet, color: AppColors.purple, size: 14),
          SizedBox(width: 6),
          Text(
            'Searching file contents (regex supported)',
            style: TextStyle(color: AppColors.purple, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchContent ? Icons.text_snippet_outlined : Icons.search,
            color: AppColors.textMuted,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            _searchController.text.isEmpty
                ? _searchContent
                    ? 'Search in file contents'
                    : 'Search for files by name'
                : 'No results found',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          if (_searchController.text.isEmpty && !_searchContent)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Try *.go, main.dart, or any filename',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final file = _searchResults[index];
        final path = file['path'] as String? ?? '';
        final name = path.split('/').last;
        final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';

        return ListTile(
          leading: _FileIcon(extension: ext),
          title: Text(
            name,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
          subtitle: Text(
            path,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _ExtBadge(ext: ext),
          onTap: () {
            setState(() => _selectedFile = file);
            _loadFileContent(path);
          },
        );
      },
    );
  }

  Widget _buildContentResults() {
    return ListView.builder(
      itemCount: _contentResults.length,
      itemBuilder: (context, index) {
        final match = _contentResults[index];
        final path = match['file'] as String? ?? match['path'] as String? ?? '';
        final line = match['line'] as int?;
        final content = match['content'] as String? ?? match['text'] as String? ?? '';
        final name = path.split('/').last;

        return ListTile(
          leading: const Icon(Icons.code, color: AppColors.textMuted, size: 20),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (line != null) ...[
                const SizedBox(width: 4),
                Text(
                  ':$line',
                  style: const TextStyle(color: AppColors.amber, fontSize: 12),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                path,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
              if (content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    content.trim(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          onTap: () {
            setState(() => _selectedFile = {'path': path});
            _loadFileContent(path);
          },
        );
      },
    );
  }

  Widget _buildFileViewer() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Icon(
                  _getFileIcon(_selectedFile?['path'] ?? ''),
                  color: AppColors.textMuted,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedFile?['path'] ?? '',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textMuted, size: 18),
                  onPressed: () {
                    setState(() {
                      _selectedFile = null;
                      _fileContent = null;
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _fileContent ?? '',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' => Icons.flutter_dash,
      'go' => Icons.code,
      'ts' || 'tsx' || 'js' || 'jsx' => Icons.javascript,
      'json' => Icons.data_object,
      'md' => Icons.description,
      'yaml' || 'yml' => Icons.settings,
      'png' || 'jpg' || 'jpeg' || 'gif' => Icons.image,
      _ => Icons.insert_drive_file,
    };
  }

  void _showDirectoryPicker() {
    showDialog(
      context: context,
      builder: (context) => _DirectoryPickerDialog(
        onSelect: (dir) {
          setState(() => _workingDir = dir);
          if (_searchController.text.isNotEmpty) {
            _onSearchChanged(_searchController.text);
          }
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// File type visual indicators
// ---------------------------------------------------------------------------

class _FileIcon extends StatelessWidget {
  final String extension;
  const _FileIcon({required this.extension});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (extension) {
      'dart' => (Icons.flutter_dash, AppColors.blue),
      'go' => (Icons.code, AppColors.blue),
      'ts' || 'tsx' => (Icons.javascript, AppColors.blue),
      'js' || 'jsx' => (Icons.javascript, AppColors.amber),
      'py' => (Icons.code, AppColors.green),
      'json' => (Icons.data_object, AppColors.amber),
      'md' => (Icons.description, AppColors.textMuted),
      'yaml' || 'yml' => (Icons.settings, AppColors.purple),
      'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' => (Icons.image, AppColors.green),
      'sh' || 'bash' => (Icons.terminal, AppColors.green),
      _ => (Icons.insert_drive_file, AppColors.textMuted),
    };
    return Icon(icon, color: color, size: 22);
  }
}

class _ExtBadge extends StatelessWidget {
  final String ext;
  const _ExtBadge({required this.ext});

  @override
  Widget build(BuildContext context) {
    if (ext.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '.$ext',
        style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Directory picker dialog
// ---------------------------------------------------------------------------

class _DirectoryPickerDialog extends StatefulWidget {
  final Function(String) onSelect;
  const _DirectoryPickerDialog({required this.onSelect});

  @override
  State<_DirectoryPickerDialog> createState() => _DirectoryPickerDialogState();
}

class _DirectoryPickerDialogState extends State<_DirectoryPickerDialog> {
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
