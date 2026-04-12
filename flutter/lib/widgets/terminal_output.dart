import 'package:flutter/material.dart';
import '../models/messages.dart';
import '../theme/colors.dart';

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
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: widget.lines.length,
      itemBuilder: (context, index) {
        return _buildLine(widget.lines[index]);
      },
    );
  }

  Widget _buildLine(TerminalLine line) {
    switch (line.type) {
      case TerminalLineType.userInput:
        return Text(
          '\$ ${line.content}',
          style: const TextStyle(color: AppColors.green, fontSize: 13),
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
        return Text(
          '> ${line.content}',
          style: const TextStyle(color: AppColors.purple, fontSize: 13),
        );
      case TerminalLineType.tokenCount:
        return Text(
          '● ${line.content}',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
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
        return Text(
          line.content,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        );
      case TerminalLineType.error:
        return Text(
          '! ${line.content}',
          style: const TextStyle(color: AppColors.red, fontSize: 13),
        );
    }
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
    final details = content.contains(':') ? content.split(':').sublist(1).join(':') : '';
    
    return GestureDetector(
      onTap: () => widget.onFileTap?.call(filename),
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
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }
}