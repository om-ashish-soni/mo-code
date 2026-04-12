import 'package:flutter/material.dart';
import '../theme/colors.dart';

class ProviderSwitcher extends StatelessWidget {
  final String activeProvider;
  final Function(String) onSwitch;

  const ProviderSwitcher({
    super.key,
    required this.activeProvider,
    required this.onSwitch,
  });

  static const _providers = ['copilot', 'claude', 'gemini'];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: _providers.map((p) => _buildPill(p)).toList(),
      ),
    );
  }

  Widget _buildPill(String provider) {
    final isActive = provider == activeProvider;
    return Expanded(
      child: GestureDetector(
        onTap: isActive ? null : () => onSwitch(provider),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? AppColors.purple : AppColors.border,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            provider == 'claude' ? 'Claude' : provider == 'gemini' ? 'Gemini' : 'Copilot',
            style: TextStyle(
              color: isActive ? AppColors.white : AppColors.textMuted,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}