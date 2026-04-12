import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/daemon.dart';
import '../theme/colors.dart';
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _selectedFile;
  String? _fileContent;
  bool _loading = false;
  String? _workingDir;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

    setState(() {
      _searchResults = results ?? [];
      _loading = false;
    });
  }

  Future<void> _loadFileContent(String path) async {
    setState(() => _loading = true);

    final api = context.read<OpenCodeAPI>();
    final content = await api.getFileContent(path, directory: _workingDir);

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
            icon: const Icon(Icons.folder_open, color: AppColors.textMuted),
            onPressed: _showDirectoryPicker,
            tooltip: 'Change directory',
          ),
        ],
      ),
      body: SelectionArea(child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.panel,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search files...',
                prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.textMuted),
                        onPressed: () {
                          _searchController.clear();
                          _searchFiles('');
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
              onChanged: _searchFiles,
            ),
          ),
          if (_workingDir != null)
            Container(
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
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
                : _searchResults.isEmpty
                    ? _buildEmptyState()
                    : _buildFileList(),
          ),
          if (_selectedFile != null && _fileContent != null)
            Expanded(child: _buildFileViewer()),
        ],
      )),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search, color: AppColors.textMuted, size: 48),
          const SizedBox(height: 12),
          Text(
            _searchController.text.isEmpty
                ? 'Search for files'
                : 'No files found',
            style: const TextStyle(color: AppColors.textMuted),
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

        return ListTile(
          leading: Icon(
            _getFileIcon(name),
            color: AppColors.textMuted,
          ),
          title: Text(
            name,
            style: const TextStyle(color: AppColors.textPrimary),
          ),
          subtitle: Text(
            path,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            setState(() => _selectedFile = file);
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
    switch (ext) {
      case 'dart':
        return Icons.flutter_dash;
      case 'go':
        return Icons.code;
      case 'ts':
      case 'tsx':
      case 'js':
      case 'jsx':
        return Icons.javascript;
      case 'json':
        return Icons.data_object;
      case 'md':
        return Icons.description;
      case 'yaml':
      case 'yml':
        return Icons.settings;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  void _showDirectoryPicker() {
    showDialog(
      context: context,
      builder: (context) => DirectoryPickerDialog(
        onSelect: (dir) {
          setState(() => _workingDir = dir);
          _searchFiles(_searchController.text);
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
