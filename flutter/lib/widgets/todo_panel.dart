import 'package:flutter/material.dart';
import '../models/messages.dart';
import '../theme/colors.dart';

/// Task progress panel inspired by opencode's TodoWrite.
///
/// Displays a list of TODO items with status indicators (pending, in-progress,
/// completed). Supports animated transitions when items change status.
/// Designed to be embedded inline in the terminal output stream.
class TodoPanel extends StatefulWidget {
  final List<TodoItem> items;
  final bool collapsible;
  final bool initiallyExpanded;

  const TodoPanel({
    super.key,
    required this.items,
    this.collapsible = true,
    this.initiallyExpanded = true,
  });

  @override
  State<TodoPanel> createState() => _TodoPanelState();
}

class _TodoPanelState extends State<TodoPanel> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final completed =
        widget.items.where((i) => i.status == TodoStatus.completed).length;
    final total = widget.items.length;
    final allDone = completed == total && total > 0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: allDone
              ? AppColors.green.withAlpha(80)
              : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(completed, total, allDone),
          if (_expanded) _buildItemList(),
        ],
      ),
    );
  }

  Widget _buildHeader(int completed, int total, bool allDone) {
    return GestureDetector(
      onTap: widget.collapsible ? () => setState(() => _expanded = !_expanded) : null,
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
            Icon(
              allDone ? Icons.check_circle_rounded : Icons.checklist_rounded,
              size: 14,
              color: allDone ? AppColors.green : AppColors.purple,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Tasks',
                style: AppTheme.uiFont(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
              ),
            ),
            _buildProgressBadge(completed, total, allDone),
            if (widget.collapsible) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(
                _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 14,
                color: AppColors.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBadge(int completed, int total, bool allDone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: allDone ? AppColors.greenDim : AppColors.purpleDim,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        '$completed/$total',
        style: AppTheme.codeFont(
          fontSize: 10,
          color: allDone ? AppColors.green : AppColors.purpleLight,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildItemList() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        children: widget.items
            .map((item) => _TodoItemRow(key: ValueKey(item.id), item: item))
            .toList(),
      ),
    );
  }
}

class _TodoItemRow extends StatelessWidget {
  final TodoItem item;

  const _TodoItemRow({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs + 1),
      color: item.status == TodoStatus.inProgress
          ? AppColors.amberDim.withAlpha(30)
          : Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: _buildStatusIcon(),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              item.content,
              style: AppTheme.codeFont(
                fontSize: 12,
                color: _textColor(),
              ).copyWith(
                decoration: item.status == TodoStatus.completed
                    ? TextDecoration.lineThrough
                    : null,
                decorationColor: AppColors.textMuted,
              ),
            ),
          ),
          if (item.status == TodoStatus.inProgress)
            const _PulsingDot(),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (item.status) {
      case TodoStatus.pending:
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.textMuted, width: 1.2),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      case TodoStatus.inProgress:
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.amber, width: 1.2),
            borderRadius: BorderRadius.circular(3),
            color: AppColors.amberDim,
          ),
          child: const Center(
            child: Icon(Icons.more_horiz, size: 10, color: AppColors.amber),
          ),
        );
      case TodoStatus.completed:
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.greenDim,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: AppColors.green, width: 1.2),
          ),
          child: const Center(
            child: Icon(Icons.check, size: 10, color: AppColors.green),
          ),
        );
    }
  }

  Color _textColor() {
    switch (item.status) {
      case TodoStatus.pending:
        return AppColors.textMuted;
      case TodoStatus.inProgress:
        return AppColors.textPrimary;
      case TodoStatus.completed:
        return AppColors.textMuted;
    }
  }
}

/// Small pulsing dot indicator for in-progress items.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) {
        return Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: _animation.value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
