import 'package:flutter/material.dart';
import '../models/messages.dart';
import '../theme/colors.dart';

/// Inline diff viewer that displays file diffs in the terminal output.
///
/// Renders unified-diff style with colored additions/deletions, line numbers,
/// hunk headers, and a collapsible file header with +/- summary.
class DiffViewer extends StatefulWidget {
  final DiffFile diff;
  final bool initiallyExpanded;
  final Function(String)? onFileTap;

  const DiffViewer({
    super.key,
    required this.diff,
    this.initiallyExpanded = true,
    this.onFileTap,
  });

  @override
  State<DiffViewer> createState() => _DiffViewerState();
}

class _DiffViewerState extends State<DiffViewer>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late AnimationController _iconController;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _iconController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: _expanded ? 0.5 : 0.0,
    );
  }

  @override
  void dispose() {
    _iconController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _iconController.forward();
      } else {
        _iconController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          if (_expanded) _buildHunks(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final adds = widget.diff.additions;
    final dels = widget.diff.deletions;
    final filename = widget.diff.path.split('/').last;
    final dirPath = widget.diff.path.contains('/')
        ? widget.diff.path.substring(0, widget.diff.path.lastIndexOf('/') + 1)
        : '';

    return GestureDetector(
      onTap: _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: _expanded
              ? const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd))
              : BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          children: [
            RotationTransition(
              turns: _iconController,
              child: const Icon(
                Icons.expand_more_rounded,
                size: 16,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              _fileIcon(widget.diff.path),
              size: 14,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: GestureDetector(
                onTap: () => widget.onFileTap?.call(widget.diff.path),
                child: Text.rich(
                  TextSpan(children: [
                    if (dirPath.isNotEmpty)
                      TextSpan(
                        text: dirPath,
                        style: AppTheme.codeFont(fontSize: 12, color: AppColors.textMuted),
                      ),
                    TextSpan(
                      text: filename,
                      style: AppTheme.codeFont(fontSize: 12, color: AppColors.textPrimary),
                    ),
                  ]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (adds > 0)
              Text('+$adds', style: AppTheme.codeFont(fontSize: 11, color: AppColors.green)),
            if (adds > 0 && dels > 0) const SizedBox(width: AppSpacing.sm),
            if (dels > 0)
              Text('-$dels', style: AppTheme.codeFont(fontSize: 11, color: AppColors.red)),
          ],
        ),
      ),
    );
  }

  Widget _buildHunks() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < widget.diff.hunks.length; i++) ...[
          _buildHunkHeader(widget.diff.hunks[i]),
          _buildHunkLines(widget.diff.hunks[i]),
        ],
      ],
    );
  }

  Widget _buildHunkHeader(DiffHunk hunk) {
    final header =
        '@@ -${hunk.oldStart},${hunk.oldCount} +${hunk.newStart},${hunk.newCount} @@';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      color: AppColors.purpleDim.withAlpha(30),
      child: Text(
        header,
        style: AppTheme.codeFont(fontSize: 11, color: AppColors.purple.withAlpha(180)),
      ),
    );
  }

  Widget _buildHunkLines(DiffHunk hunk) {
    int oldLine = hunk.oldStart;
    int newLine = hunk.newStart;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: hunk.lines.map((line) {
        final widget = _buildDiffLine(line, oldLine, newLine);
        switch (line.type) {
          case DiffLineType.context:
            oldLine++;
            newLine++;
          case DiffLineType.added:
            newLine++;
          case DiffLineType.removed:
            oldLine++;
        }
        return widget;
      }).toList(),
    );
  }

  Widget _buildDiffLine(DiffHunkLine line, int oldLine, int newLine) {
    Color bgColor;
    Color textColor;
    String prefix;
    String leftNum;
    String rightNum;

    switch (line.type) {
      case DiffLineType.added:
        bgColor = AppColors.green.withValues(alpha: 0.08);
        textColor = AppColors.green;
        prefix = '+';
        leftNum = '';
        rightNum = newLine.toString();
      case DiffLineType.removed:
        bgColor = AppColors.red.withValues(alpha: 0.08);
        textColor = AppColors.red;
        prefix = '-';
        leftNum = oldLine.toString();
        rightNum = '';
      case DiffLineType.context:
        bgColor = Colors.transparent;
        textColor = AppColors.textMuted;
        prefix = ' ';
        leftNum = oldLine.toString();
        rightNum = newLine.toString();
    }

    return Container(
      color: bgColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Text(
                leftNum,
                textAlign: TextAlign.right,
                style: AppTheme.codeFont(fontSize: 11, color: AppColors.textDisabled),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                rightNum,
                textAlign: TextAlign.right,
                style: AppTheme.codeFont(fontSize: 11, color: AppColors.textDisabled),
              ),
            ),
          ),
          SizedBox(
            width: 14,
            child: Text(
              prefix,
              style: AppTheme.codeFont(fontSize: 12, color: textColor, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              line.content,
              style: AppTheme.codeFont(
                fontSize: 12,
                color: line.type == DiffLineType.context
                    ? AppColors.textPrimary
                    : textColor,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  IconData _fileIcon(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return Icons.flutter_dash;
      case 'go':
        return Icons.code;
      case 'js' || 'ts' || 'jsx' || 'tsx':
        return Icons.javascript;
      case 'py':
        return Icons.code;
      case 'md':
        return Icons.description;
      case 'yaml' || 'yml' || 'json' || 'toml':
        return Icons.settings;
      case 'sh' || 'bash':
        return Icons.terminal;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}

/// A multi-file diff viewer that shows a list of changed files.
class MultiDiffViewer extends StatelessWidget {
  final List<DiffFile> diffs;
  final Function(String)? onFileTap;

  const MultiDiffViewer({
    super.key,
    required this.diffs,
    this.onFileTap,
  });

  @override
  Widget build(BuildContext context) {
    if (diffs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          'No changes',
          style: AppTheme.uiFont(fontSize: 12, color: AppColors.textMuted),
        ),
      );
    }

    final totalAdds = diffs.fold(0, (sum, d) => sum + d.additions);
    final totalDels = diffs.fold(0, (sum, d) => sum + d.deletions);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
          child: Row(
            children: [
              Text(
                '${diffs.length} file${diffs.length == 1 ? '' : 's'} changed',
                style: AppTheme.codeFont(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (totalAdds > 0)
                Text('+$totalAdds', style: AppTheme.codeFont(fontSize: 11, color: AppColors.green)),
              if (totalAdds > 0 && totalDels > 0) const SizedBox(width: AppSpacing.sm),
              if (totalDels > 0)
                Text('-$totalDels', style: AppTheme.codeFont(fontSize: 11, color: AppColors.red)),
            ],
          ),
        ),
        // Individual file diffs
        ...diffs.map((diff) => DiffViewer(
              diff: diff,
              initiallyExpanded: diffs.length <= 3,
              onFileTap: onFileTap,
            )),
      ],
    );
  }
}
