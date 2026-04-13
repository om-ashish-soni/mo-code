import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        itemCount: widget.lines.length,
        itemBuilder: (context, index) {
          final line = widget.lines[index];
          final widget_ = _buildLine(line);

          // Animate new items (last 3) sliding in
          if (index >= widget.lines.length - 3) {
            return widget_
                .animate()
                .fadeIn(duration: 250.ms, curve: Curves.easeOut)
                .slideY(begin: 0.1, end: 0, duration: 250.ms, curve: Curves.easeOut);
          }
          return widget_;
        },
      ),
    );
  }

  Widget _buildLine(TerminalLine line) {
    switch (line.type) {
      case TerminalLineType.userInput:
        return _buildUserInput(line.content);
      case TerminalLineType.agentThinking:
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.purple.withAlpha(150),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  line.content,
                  style: AppTheme.uiFont(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        );
      case TerminalLineType.planStep:
        return _buildPlanStep(line.content);
      case TerminalLineType.fileCreated:
        return _buildFileEvent(Icons.add_circle_outline, AppColors.green, line.content);
      case TerminalLineType.fileModified:
        return _buildFileEvent(Icons.edit_outlined, AppColors.amber, line.content);
      case TerminalLineType.fileDeleted:
        return _buildFileEvent(Icons.remove_circle_outline, AppColors.red, line.content);
      case TerminalLineType.toolCall:
        return _buildToolCall(line.content);
      case TerminalLineType.tokenCount:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            line.content,
            style: AppTheme.codeFont(
              fontSize: 11,
              color: AppColors.textDisabled,
            ),
          ),
        );
      case TerminalLineType.separator:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.border.withAlpha(0),
                  AppColors.border,
                  AppColors.border.withAlpha(0),
                ],
              ),
            ),
          ),
        );
      case TerminalLineType.text:
        return _buildMarkdownText(line.content);
      case TerminalLineType.error:
        return _buildError(line.content);
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

  Widget _buildUserInput(String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.green.withAlpha(12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.green.withAlpha(30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.green.withAlpha(30),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.person, size: 12, color: AppColors.green),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              content,
              style: AppTheme.uiFont(
                fontSize: 14,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.red.withAlpha(12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.red.withAlpha(30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 14, color: AppColors.red),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              content,
              style: AppTheme.uiFont(fontSize: 13, color: AppColors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkdownText(String content) {
    if (content.length < 3 || !_looksLikeMarkdown(content)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          content,
          style: AppTheme.uiFont(
            fontSize: 14,
            color: AppColors.textPrimary,
            height: 1.6,
          ),
        ),
      );
    }

    return MarkdownBody(
      data: content,
      selectable: false,
      shrinkWrap: true,
      styleSheet: _markdownStyleSheet(),
    );
  }

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
      p: AppTheme.uiFont(fontSize: 14, color: AppColors.textPrimary, height: 1.6),
      h1: AppTheme.uiFont(fontSize: 20, color: AppColors.white, fontWeight: FontWeight.w700),
      h2: AppTheme.uiFont(fontSize: 17, color: AppColors.white, fontWeight: FontWeight.w600),
      h3: AppTheme.uiFont(fontSize: 15, color: AppColors.white, fontWeight: FontWeight.w600),
      code: AppTheme.codeFont(
        color: AppColors.amber,
        fontSize: 13,
      ).copyWith(backgroundColor: AppColors.surface),
      codeblockDecoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      codeblockPadding: const EdgeInsets.all(AppSpacing.lg),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.purple.withAlpha(120), width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: AppSpacing.lg, top: 4, bottom: 4),
      listBullet: AppTheme.uiFont(fontSize: 14, color: AppColors.textMuted),
      a: AppTheme.uiFont(fontSize: 14, color: AppColors.blue).copyWith(
        decoration: TextDecoration.underline,
      ),
      strong: AppTheme.uiFont(fontSize: 14, color: AppColors.white, fontWeight: FontWeight.w600),
      em: AppTheme.uiFont(fontSize: 14, color: AppColors.textPrimary).copyWith(
        fontStyle: FontStyle.italic,
      ),
      tableHead: AppTheme.uiFont(fontSize: 12, color: AppColors.white, fontWeight: FontWeight.w600),
      tableBody: AppTheme.uiFont(fontSize: 12, color: AppColors.textPrimary),
      tableBorder: TableBorder.all(color: AppColors.border, width: 0.5),
      tableCellsPadding: const EdgeInsets.all(AppSpacing.sm),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.border.withAlpha(120), width: 1),
        ),
      ),
    );
  }

  Widget _buildToolCall(String content) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.purple.withAlpha(8),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.purple.withAlpha(25),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.build_outlined, size: 11, color: AppColors.purple),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              content,
              style: AppTheme.codeFont(fontSize: 12, color: AppColors.purple),
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
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: AppColors.purpleDim,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                parts[0].trim(),
                style: AppTheme.uiFont(
                  fontSize: 11,
                  color: AppColors.purpleLight,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  parts.sublist(1).join('. '),
                  style: AppTheme.uiFont(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        content,
        style: AppTheme.uiFont(fontSize: 14, color: AppColors.textPrimary),
      ),
    );
  }

  Widget _buildFileEvent(IconData icon, Color color, String content) {
    final filename = content.split(':').first.trim();
    final details =
        content.contains(':') ? content.split(':').sublist(1).join(':') : '';

    return GestureDetector(
      onTap: () => widget.onFileTap?.call(filename),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: color.withAlpha(8),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: filename,
                    style: AppTheme.codeFont(
                      fontSize: 12,
                      color: color,
                    ).copyWith(decoration: TextDecoration.underline),
                  ),
                  if (details.isNotEmpty)
                    TextSpan(
                      text: details,
                      style: AppTheme.codeFont(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                ]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
