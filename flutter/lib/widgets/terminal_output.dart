import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/messages.dart';
import '../theme/colors.dart';
import 'diff_viewer.dart';
import 'todo_panel.dart';

class TerminalOutput extends StatefulWidget {
  final List<TerminalLine> lines;
  final ScrollController? scrollController;
  final Function(String)? onFileTap;

  const TerminalOutput({
    super.key,
    required this.lines,
    this.scrollController,
    this.onFileTap,
  });

  @override
  State<TerminalOutput> createState() => _TerminalOutputState();
}

class _TerminalOutputState extends State<TerminalOutput> {
  late ScrollController _scrollController;
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 50;
    if (!atBottom && _autoScroll) {
      setState(() => _autoScroll = false);
    } else if (atBottom && !_autoScroll) {
      setState(() => _autoScroll = true);
    }
  }

  @override
  void didUpdateWidget(TerminalOutput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_autoScroll && widget.lines.length > oldWidget.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    if (widget.scrollController == null) {
      _scrollController.dispose();
    } else {
      _scrollController.removeListener(_onScroll);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: widget.lines.length,
        itemBuilder: (context, index) {
          return _buildLine(widget.lines[index]);
        },
      ),
    );
  }

  Widget _buildLine(TerminalLine line) {
    switch (line.type) {
      case TerminalLineType.userInput:
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '\$ ${line.content}',
            style: const TextStyle(color: AppColors.green, fontSize: 13),
          ),
        );
      case TerminalLineType.agentThinking:
        return Text(
          '⟐ ${line.content}',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
            fontStyle: FontStyle.italic,
          ),
        );
      case TerminalLineType.planStep:
        return _buildPlanStep(line.content);
      case TerminalLineType.fileCreated:
        return _buildFileEvent('✓', AppColors.green, line.content);
      case TerminalLineType.fileModified:
        return _buildFileEvent('~', AppColors.amber, line.content);
      case TerminalLineType.fileDeleted:
        return _buildFileEvent('-', AppColors.red, line.content);
      case TerminalLineType.toolCall:
        return _buildToolCall(line.content);
      case TerminalLineType.tokenCount:
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '● ${line.content}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
            ),
          ),
        );
      case TerminalLineType.separator:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '────────────────',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        );
      case TerminalLineType.text:
        return _buildMarkdownText(line.content);
      case TerminalLineType.error:
        return Text(
          '! ${line.content}',
          style: const TextStyle(color: AppColors.red, fontSize: 13),
        );
      case TerminalLineType.diff:
        if (line.diffData != null) {
          return DiffViewer(
            diff: line.diffData!,
            onFileTap: widget.onFileTap,
          );
        }
        return const SizedBox.shrink();
      case TerminalLineType.todo:
        if (line.todoItems != null) {
          return TodoPanel(items: line.todoItems!);
        }
        return const SizedBox.shrink();
    }
  }

  /// Renders text content as markdown with syntax-highlighted code blocks.
  Widget _buildMarkdownText(String content) {
    // For very short content or content without markdown markers, use plain text.
    if (content.length < 3 || !_looksLikeMarkdown(content)) {
      return Text(
        content,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      );
    }

    return MarkdownBody(
      data: content,
      selectable: false, // Selection handled by parent SelectionArea
      shrinkWrap: true,
      styleSheet: _markdownStyleSheet(),
    );
  }

  /// Heuristic to detect markdown content worth rendering.
  bool _looksLikeMarkdown(String text) {
    return text.contains('```') ||
        text.contains('**') ||
        text.contains('##') ||
        text.contains('- ') ||
        text.contains('1. ') ||
        text.contains('`') ||
        text.contains('[');
  }

  MarkdownStyleSheet _markdownStyleSheet() {
    return MarkdownStyleSheet(
      p: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.5),
      h1: const TextStyle(
          color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold),
      h2: const TextStyle(
          color: AppColors.white, fontSize: 16, fontWeight: FontWeight.bold),
      h3: const TextStyle(
          color: AppColors.white, fontSize: 14, fontWeight: FontWeight.bold),
      code: TextStyle(
        color: AppColors.amber,
        backgroundColor: AppColors.surface.withValues(alpha: 0.5),
        fontSize: 12,
        fontFamily: 'JetBrainsMono',
      ),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.purple.withValues(alpha: 0.5), width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
      listBullet:
          const TextStyle(color: AppColors.textMuted, fontSize: 13),
      a: const TextStyle(
          color: AppColors.blue, decoration: TextDecoration.underline),
      strong: const TextStyle(
          color: AppColors.white, fontWeight: FontWeight.bold),
      em: const TextStyle(
          color: AppColors.textPrimary, fontStyle: FontStyle.italic),
      tableHead: const TextStyle(
          color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 12),
      tableBody: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
      tableBorder: TableBorder.all(color: AppColors.border, width: 0.5),
      tableCellsPadding: const EdgeInsets.all(6),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.border.withValues(alpha: 0.5), width: 1),
        ),
      ),
    );
  }

  Widget _buildToolCall(String content) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        children: [
          const Icon(Icons.build_outlined, size: 12, color: AppColors.purple),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              content,
              style: const TextStyle(color: AppColors.purple, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanStep(String content) {
    final parts = content.split('. ');
    if (parts.length > 1) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              parts[0].trim(),
              style: const TextStyle(color: AppColors.purple, fontSize: 13),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                parts.sublist(1).join('. '),
                style: const TextStyle(color: AppColors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    return Text(
      content,
      style: const TextStyle(color: AppColors.white, fontSize: 13),
    );
  }

  Widget _buildFileEvent(String prefix, Color color, String content) {
    final filename = content.split(':').first.trim();
    final details =
        content.contains(':') ? content.split(':').sublist(1).join(':') : '';

    return GestureDetector(
      onTap: () => widget.onFileTap?.call(filename),
      child: Padding(
        padding: const EdgeInsets.only(top: 1, bottom: 1),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: prefix,
                style: TextStyle(color: color, fontSize: 13),
              ),
              TextSpan(
                text: ' $filename',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                ),
              ),
              if (details.isNotEmpty)
                TextSpan(
                  text: details,
                  style:
                      const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
