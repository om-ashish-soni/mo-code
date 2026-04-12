import 'package:flutter/material.dart';
import '../theme/colors.dart';

class InputBar extends StatefulWidget {
  final Function(String) onSubmit;
  final bool disabled;
  final bool showMic;

  const InputBar({
    super.key,
    required this.onSubmit,
    this.disabled = false,
    this.showMic = false,
  });

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
    _controller.clear();
    setState(() => _hasText = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !widget.disabled,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Type or speak...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onChanged: (value) {
                if (value.isEmpty != !_hasText) {
                  setState(() => _hasText = value.isNotEmpty);
                }
              },
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (widget.showMic)
            IconButton(
              icon: const Icon(Icons.mic, color: AppColors.textMuted, size: 20),
              onPressed: widget.disabled ? null : () {},
            ),
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