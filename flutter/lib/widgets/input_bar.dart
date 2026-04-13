import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/colors.dart';

class InputBar extends StatefulWidget {
  final Function(String) onSubmit;
  final bool disabled;
  final bool showMic;
  final bool taskRunning;
  final VoidCallback? onStop;

  const InputBar({
    super.key,
    required this.onSubmit,
    this.disabled = false,
    this.showMic = false,
    this.taskRunning = false,
    this.onStop,
  });

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _textFieldFocus = FocusNode();
  bool _hasText = false;

  // Command history
  final List<String> _history = [];
  int _historyIndex = -1;
  String _savedInput = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.disabled) _textFieldFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _textFieldFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_history.isEmpty || _history.last != text) {
      _history.add(text);
    }
    _historyIndex = -1;
    _savedInput = '';
    HapticFeedback.lightImpact();
    widget.onSubmit(text);
    _controller.clear();
    setState(() => _hasText = false);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_history.isEmpty) return KeyEventResult.handled;
      if (_historyIndex == -1) {
        _savedInput = _controller.text;
        _historyIndex = _history.length - 1;
      } else if (_historyIndex > 0) {
        _historyIndex--;
      }
      _controller.text = _history[_historyIndex];
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
      setState(() => _hasText = _controller.text.isNotEmpty);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_historyIndex == -1) return KeyEventResult.handled;
      if (_historyIndex < _history.length - 1) {
        _historyIndex++;
        _controller.text = _history[_historyIndex];
      } else {
        _historyIndex = -1;
        _controller.text = _savedInput;
      }
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
      setState(() => _hasText = _controller.text.isNotEmpty);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.panel.withAlpha(240),
        border: const Border(
          top: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Text field with rounded pill shape
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  border: Border.all(
                    color: _textFieldFocus.hasFocus
                        ? AppColors.purple.withAlpha(100)
                        : AppColors.border,
                    width: 1,
                  ),
                ),
                child: Focus(
                  focusNode: _focusNode,
                  onKeyEvent: _handleKeyEvent,
                  child: TextField(
                    controller: _controller,
                    focusNode: _textFieldFocus,
                    autofocus: true,
                    enabled: !widget.disabled,
                    maxLines: 4,
                    minLines: 1,
                    style: AppTheme.uiFont(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: widget.disabled
                          ? 'Connecting...'
                          : 'Ask anything...',
                      hintStyle: AppTheme.uiFont(
                        fontSize: 15,
                        color: AppColors.textMuted,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      isDense: false,
                    ),
                    onChanged: (value) {
                      _historyIndex = -1;
                      if (value.isEmpty != !_hasText) {
                        setState(() => _hasText = value.isNotEmpty);
                      }
                    },
                    onSubmitted: (_) {
                      _submit();
                      _textFieldFocus.requestFocus();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Send / Stop button — proper 44px touch target
            _buildActionButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    if (widget.taskRunning && widget.onStop != null) {
      return _ActionButton(
        color: AppColors.red,
        icon: Icons.stop_rounded,
        onPressed: () {
          HapticFeedback.mediumImpact();
          widget.onStop!();
        },
      ).animate().scale(
        duration: 200.ms,
        curve: Curves.easeOutBack,
      );
    }

    final active = _hasText && !widget.disabled;
    return _ActionButton(
      color: active ? AppColors.purple : AppColors.surfaceHigh,
      icon: Icons.arrow_upward_rounded,
      iconColor: active ? AppColors.white : AppColors.textMuted,
      onPressed: active ? _submit : null,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final Color? iconColor;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.color,
    required this.icon,
    this.iconColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: AppSpacing.touchTarget,
      height: AppSpacing.touchTarget,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: onPressed != null ? AppColors.cardShadow : null,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(
          icon,
          color: iconColor ?? AppColors.white,
          size: 22,
        ),
        onPressed: onPressed,
      ),
    );
  }
}
