import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  int _historyIndex = -1; // -1 means not browsing history
  String _savedInput = ''; // saves current input when browsing history

  @override
  void initState() {
    super.initState();
    // Auto-focus the text field on mount
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
    // Add to history (avoid duplicates at end)
    if (_history.isEmpty || _history.last != text) {
      _history.add(text);
    }
    _historyIndex = -1;
    _savedInput = '';
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
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
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
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      setState(() => _hasText = _controller.text.isNotEmpty);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _handleKeyEvent,
              child: TextField(
                controller: _controller,
                focusNode: _textFieldFocus,
                autofocus: true,
                enabled: !widget.disabled,
                maxLines: 1,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.5),
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: widget.disabled ? 'Connecting...' : 'Type a prompt...',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  isDense: false,
                ),
                onChanged: (value) {
                  _historyIndex = -1; // reset history browsing on manual edit
                  if (value.isEmpty != !_hasText) {
                    setState(() => _hasText = value.isNotEmpty);
                  }
                },
                onSubmitted: (_) {
                  _submit();
                  _textFieldFocus.requestFocus(); // keep focus after submit
                },
              ),
            ),
          ),
          if (widget.showMic)
            IconButton(
              icon: const Icon(Icons.mic, color: AppColors.textMuted, size: 20),
              onPressed: widget.disabled ? null : () {},
            ),
          if (widget.taskRunning && widget.onStop != null)
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(left: 8),
              decoration: const BoxDecoration(
                color: AppColors.red,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.stop, color: AppColors.white, size: 18),
                onPressed: widget.onStop,
              ),
            )
          else
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: _hasText && !widget.disabled ? AppColors.purple : AppColors.border,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.play_arrow,
                  color: _hasText && !widget.disabled ? AppColors.white : AppColors.textMuted,
                  size: 18,
                ),
                onPressed: _hasText && !widget.disabled ? _submit : null,
              ),
            ),
        ],
      ),
    );
  }
}