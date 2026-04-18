import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/colors.dart';

/// GitHub Copilot models — the single Copilot provider serves all of these.
const copilotModels = [
  ModelOption('gpt-5-mini', 'GPT-5 Mini', 'Compact, latest'),
  ModelOption('gpt-4o', 'GPT-4o', 'Fast, balanced'),
  ModelOption('gpt-4.1', 'GPT-4.1', 'Latest GPT'),
  ModelOption('gpt-4o-mini', 'GPT-4o Mini', 'Fast, cheap'),
  ModelOption('claude-haiku-4.5', 'Claude Haiku 4.5', 'Anthropic, fast'),
  ModelOption('gemini-2.5-pro', 'Gemini 2.5 Pro', 'Google, advanced'),
  ModelOption('grok-code-fast-1', 'Grok Code Fast', 'xAI, code'),
];

const claudeModels = [
  ModelOption('claude-sonnet-4-20250514', 'Claude Sonnet 4', 'Latest'),
  ModelOption('claude-3.5-haiku-20241022', 'Claude 3.5 Haiku', 'Fast'),
];

const geminiModels = [
  ModelOption('gemini-2.5-flash', 'Gemini 2.5 Flash', 'Fast, cheap'),
  ModelOption('gemini-2.5-pro', 'Gemini 2.5 Pro', 'Advanced'),
];

const openrouterModels = [
  ModelOption('anthropic/claude-sonnet-4', 'Claude Sonnet 4', 'Daily driver'),
  ModelOption('anthropic/claude-haiku-4.5', 'Claude Haiku 4.5', 'Cheap, fast'),
  ModelOption('openai/gpt-4o', 'GPT-4o', 'OpenAI baseline'),
  ModelOption('openai/gpt-4o-mini', 'GPT-4o Mini', 'Cheapest OAI'),
  ModelOption('zhipuai/glm-4.6', 'GLM-4.6', 'Cheap, code-strong'),
  ModelOption('minimax/minimax-m2', 'MiniMax M2', 'Long context, cheap'),
  ModelOption('deepseek/deepseek-v3.2', 'DeepSeek V3.2', 'Strong code, cheap'),
  ModelOption('qwen/qwen3-coder-480b', 'Qwen3 Coder 480B', 'Code specialist'),
];

const ollamaModels = [
  ModelOption('qwen2.5-coder:7b', 'Qwen2.5 Coder 7B', 'Local, code'),
  ModelOption('llama3.1:8b', 'Llama 3.1 8B', 'Local, general'),
  ModelOption('deepseek-coder-v2:16b', 'DeepSeek Coder V2', 'Local, code'),
];

const azureModels = [
  ModelOption('gpt-4o', 'GPT-4o', 'Azure deployment name'),
  ModelOption('gpt-4o-mini', 'GPT-4o Mini', 'Azure deployment name'),
];

class ModelOption {
  final String id;
  final String label;
  final String description;
  const ModelOption(this.id, this.label, this.description);
}

/// Single source of truth for the model list of a given provider.
/// Returns an empty list for unknown providers.
List<ModelOption> modelsForProvider(String provider) {
  return switch (provider) {
    'copilot' => copilotModels,
    'claude' => claudeModels,
    'gemini' => geminiModels,
    'openrouter' => openrouterModels,
    'ollama' => ollamaModels,
    'azure' => azureModels,
    _ => const [],
  };
}

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
      onTap: () {
        HapticFeedback.selectionClick();
        _showModelPicker(context);
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.panel.withAlpha(200),
          border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Row(
          children: [
            // Provider pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.purpleDim,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
              child: Text(
                _providerLabel(activeProvider),
                style: AppTheme.uiFont(
                  fontSize: 12,
                  color: AppColors.purpleLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Active model
            Expanded(
              child: Text(
                activeModel,
                style: AppTheme.uiFont(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.unfold_more, color: AppColors.textMuted, size: 14),
            ),
          ],
        ),
      ),
    );
  }

  String _providerLabel(String provider) {
    return switch (provider) {
      'copilot' => 'Copilot',
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
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.radiusXl),
            ),
            boxShadow: AppColors.elevatedShadow,
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Text(
                  'Model',
                  style: AppTheme.uiFont(
                    fontSize: 18,
                    color: AppColors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Provider tabs
              _buildProviderTabs(),
              const Divider(height: 1, color: AppColors.border),
              // Models for active provider
              ..._modelsForProvider().asMap().entries.map(
                (e) => _buildModelTile(e.value)
                    .animate()
                    .fadeIn(
                      delay: (50 * e.key).ms,
                      duration: 200.ms,
                    )
                    .slideX(
                      begin: 0.05,
                      end: 0,
                      delay: (50 * e.key).ms,
                      duration: 200.ms,
                      curve: Curves.easeOut,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProviderTabs() {
    const providers = ['copilot', 'claude', 'gemini'];
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: providers.map((p) {
          final isActive = p == activeProvider;
          return Expanded(
            child: GestureDetector(
              onTap: isActive ? null : () {
                HapticFeedback.selectionClick();
                onProviderSwitch(p);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.purpleDim : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: isActive ? AppColors.purple.withAlpha(80) : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _label(p),
                  style: AppTheme.uiFont(
                    fontSize: 13,
                    color: isActive ? AppColors.purpleLight : AppColors.textMuted,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
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
      'openrouter' => 'OpenRouter',
      'ollama' => 'Ollama',
      'azure' => 'Azure',
      _ => p,
    };
  }

  List<ModelOption> _modelsForProvider() => modelsForProvider(activeProvider);

  Widget _buildModelTile(ModelOption model) {
    final isActive = model.id == activeModel;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onModelSwitch(model.id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: isActive ? AppColors.purpleDim.withAlpha(60) : null,
          border: Border(
            bottom: BorderSide(color: AppColors.border.withAlpha(80), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.label,
                    style: AppTheme.uiFont(
                      fontSize: 15,
                      color: isActive ? AppColors.purpleLight : AppColors.textPrimary,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    model.description,
                    style: AppTheme.uiFont(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              model.id,
              style: AppTheme.codeFont(
                fontSize: 10,
                color: isActive ? AppColors.purple.withAlpha(150) : AppColors.textDisabled,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: AppSpacing.sm),
              const Icon(Icons.check_circle, color: AppColors.purple, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}
