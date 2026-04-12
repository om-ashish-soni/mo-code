import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// GitHub Copilot models — the single Copilot provider serves all of these.
/// Reference: https://docs.github.com/en/copilot/using-github-copilot/ai-models/changing-the-ai-model-for-copilot-chat
const copilotModels = [
  _ModelDef('gpt-4o', 'GPT-4o', 'Fast, balanced'),
  _ModelDef('gpt-4.1', 'GPT-4.1', 'Latest GPT'),
  _ModelDef('o4-mini', 'o4-mini', 'Reasoning, compact'),
  _ModelDef('o3-mini', 'o3-mini', 'Reasoning'),
  _ModelDef('claude-sonnet-4', 'Claude Sonnet 4', 'Anthropic'),
  _ModelDef('claude-3.5-sonnet', 'Claude 3.5 Sonnet', 'Anthropic'),
  _ModelDef('gemini-2.0-flash', 'Gemini 2.0 Flash', 'Google, fast'),
  _ModelDef('gemini-2.5-pro', 'Gemini 2.5 Pro', 'Google, advanced'),
];

/// Direct-provider models (when using your own API key).
const claudeModels = [
  _ModelDef('claude-sonnet-4-20250514', 'Claude Sonnet 4', 'Latest'),
  _ModelDef('claude-3.5-haiku-20241022', 'Claude 3.5 Haiku', 'Fast'),
];

const geminiModels = [
  _ModelDef('gemini-2.5-pro', 'Gemini 2.5 Pro', 'Advanced'),
  _ModelDef('gemini-2.5-flash', 'Gemini 2.5 Flash', 'Fast'),
];

class _ModelDef {
  final String id;
  final String label;
  final String description;
  const _ModelDef(this.id, this.label, this.description);
}

/// Compact provider bar shown at the top of the agent screen.
/// Tapping opens the model picker bottom sheet.
class ProviderSwitcher extends StatelessWidget {
  final String activeProvider;
  final String activeModel;
  final Function(String provider) onProviderSwitch;
  final Function(String model) onModelSwitch;

  const ProviderSwitcher({
    super.key,
    required this.activeProvider,
    required this.activeModel,
    required this.onProviderSwitch,
    required this.onModelSwitch,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showModelPicker(context),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          color: AppColors.panel,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            // Provider pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.purple.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.purple.withAlpha(60)),
              ),
              child: Text(
                _providerLabel(activeProvider),
                style: const TextStyle(
                  color: AppColors.purple,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Active model
            Expanded(
              child: Text(
                activeModel,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.unfold_more, color: AppColors.textMuted, size: 16),
          ],
        ),
      ),
    );
  }

  String _providerLabel(String provider) {
    return switch (provider) {
      'copilot' => 'GitHub Copilot',
      'claude' => 'Claude',
      'gemini' => 'Gemini',
      'openrouter' => 'OpenRouter',
      'ollama' => 'Ollama',
      'azure' => 'Azure',
      _ => provider,
    };
  }

  void _showModelPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return _ModelPickerSheet(
          activeProvider: activeProvider,
          activeModel: activeModel,
          onProviderSwitch: (p) {
            Navigator.pop(ctx);
            onProviderSwitch(p);
          },
          onModelSwitch: (m) {
            Navigator.pop(ctx);
            onModelSwitch(m);
          },
        );
      },
    );
  }
}

class _ModelPickerSheet extends StatelessWidget {
  final String activeProvider;
  final String activeModel;
  final Function(String) onProviderSwitch;
  final Function(String) onModelSwitch;

  const _ModelPickerSheet({
    required this.activeProvider,
    required this.activeModel,
    required this.onProviderSwitch,
    required this.onModelSwitch,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.85,
      minChildSize: 0.3,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            border: Border(
              top: BorderSide(color: AppColors.border),
              left: BorderSide(color: AppColors.border),
              right: BorderSide(color: AppColors.border),
            ),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Provider tabs
              _buildProviderTabs(),
              const Divider(color: AppColors.border, height: 1),
              // Models for active provider
              ..._modelsForProvider().map((m) => _buildModelTile(m)),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProviderTabs() {
    const providers = ['copilot', 'claude', 'gemini'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: providers.map((p) {
          final isActive = p == activeProvider;
          return Expanded(
            child: GestureDetector(
              onTap: isActive ? null : () => onProviderSwitch(p),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.purple.withAlpha(40) : AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActive ? AppColors.purple : AppColors.border,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _label(p),
                  style: TextStyle(
                    color: isActive ? AppColors.purple : AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _label(String p) {
    return switch (p) {
      'copilot' => 'Copilot',
      'claude' => 'Claude',
      'gemini' => 'Gemini',
      _ => p,
    };
  }

  List<_ModelDef> _modelsForProvider() {
    return switch (activeProvider) {
      'copilot' => copilotModels,
      'claude' => claudeModels,
      'gemini' => geminiModels,
      _ => [],
    };
  }

  Widget _buildModelTile(_ModelDef model) {
    final isActive = model.id == activeModel;
    return InkWell(
      onTap: () => onModelSwitch(model.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? AppColors.purple.withAlpha(15) : null,
          border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.label,
                    style: TextStyle(
                      color: isActive ? AppColors.purple : AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    model.description,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              model.id,
              style: TextStyle(
                color: isActive ? AppColors.purple.withAlpha(150) : AppColors.textMuted,
                fontSize: 10,
                fontFamily: 'JetBrainsMono',
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle, color: AppColors.purple, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}
