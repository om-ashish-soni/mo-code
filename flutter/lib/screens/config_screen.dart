import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/daemon.dart';
import '../api/app_logger.dart';
import '../theme/colors.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/connection_banner.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _claudeKeyController = TextEditingController();
  final _geminiKeyController = TextEditingController();
  final _workingDirController = TextEditingController();

  String _activeProvider = 'claude';
  Map<String, bool> _providerConfigured = {};
  Map<String, dynamic>? _serverStatus;
  Map<String, dynamic>? _runtimeStatus;

  // Loading / error states
  bool _loading = true;
  bool _loadFailed = false;
  String? _loadError;

  // Status toast
  _StatusToast? _toast;
  Timer? _toastTimer;

  // Copilot device auth state
  bool _copilotAuthInProgress = false;
  String? _copilotUserCode;
  String? _copilotVerificationUri;
  String? _copilotDeviceCode;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _claudeKeyController.dispose();
    _geminiKeyController.dispose();
    _workingDirController.dispose();
    _toastTimer?.cancel();
    super.dispose();
  }

  void _showToast(String message, {bool isError = false}) {
    _toastTimer?.cancel();
    setState(() => _toast = _StatusToast(message: message, isError: isError));
    _toastTimer = Timer(Duration(seconds: isError ? 4 : 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _loadConfig() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _loadError = null;
    });

    final api = context.read<OpenCodeAPI>();
    final results = await Future.wait([
      api.fetchConfig(),
      api.fetchStatus(),
      api.fetchRuntimeStatus(),
    ]);
    final config = results[0];
    final status = results[1];
    final runtime = results[2];

    if (!mounted) return;

    if (config != null) {
      setState(() {
        _activeProvider = config['active_provider'] as String? ?? 'claude';
        final providers = config['providers'] as Map<String, dynamic>? ?? {};
        _providerConfigured = {
          'claude': (providers['claude'] as Map<String, dynamic>?)?['configured'] == true,
          'gemini': (providers['gemini'] as Map<String, dynamic>?)?['configured'] == true,
          'copilot': (providers['copilot'] as Map<String, dynamic>?)?['configured'] == true,
        };
        _serverStatus = status;
        _runtimeStatus = runtime;
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _loadFailed = true;
        _loadError = api.lastError ?? 'Failed to load config';
      });
    }
  }

  void _setApiKey(String provider, String key) {
    if (key.trim().isEmpty) {
      _showToast('API key cannot be empty', isError: true);
      return;
    }
    final api = context.read<OpenCodeAPI>();
    api.sendWsMessage({
      'type': 'config.set',
      'id': 'cfg-${DateTime.now().millisecondsSinceEpoch}',
      'payload': {
        'key': 'providers.$provider.api_key',
        'value': key,
      },
    });
    setState(() => _providerConfigured[provider] = true);
    _showToast('${provider.toUpperCase()} API key saved');
  }

  void _switchProvider(String provider) {
    final api = context.read<OpenCodeAPI>();
    api.sendWsMessage({
      'type': 'provider.switch',
      'id': 'sw-${DateTime.now().millisecondsSinceEpoch}',
      'payload': {
        'provider': provider,
      },
    });
    setState(() => _activeProvider = provider);
    _showToast('Switched to $provider');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.panel,
        elevation: 0,
        title: Text('Config', style: AppTheme.uiFont(fontSize: 18, color: AppColors.white, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.terminal_rounded, color: AppColors.textMuted),
            onPressed: _showLogsSheet,
            tooltip: 'View Logs',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textMuted),
            onPressed: _loadConfig,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SelectionArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoadingSkeleton();

    if (_loadFailed) {
      return ErrorStateWidget(
        message: 'Could not load configuration',
        detail: _loadError,
        onRetry: _loadConfig,
        icon: Icons.settings_outlined,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (_toast != null) _buildToastBanner(),
        _buildServerInfo(),
        const SizedBox(height: AppSpacing.xl),
        _buildProviderSelector(),
        const SizedBox(height: AppSpacing.xl),
        _buildApiKeySection('claude', 'Claude (Anthropic)', _claudeKeyController, 'sk-ant-...'),
        const SizedBox(height: AppSpacing.md),
        _buildApiKeySection('gemini', 'Gemini (Google)', _geminiKeyController, 'AIza...'),
        const SizedBox(height: AppSpacing.md),
        _buildCopilotAuthSection(),
        const SizedBox(height: AppSpacing.xl),
        _buildWorkingDirSection(),
        const SizedBox(height: AppSpacing.xl),
        _buildRuntimeSection(),
        const SizedBox(height: AppSpacing.xl),
        _buildLogsSection(),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildLoadingSkeleton() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ShimmerLoading(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: const Row(
                children: [
                  ShimmerLine(width: 80, height: 14),
                  Spacer(),
                  ShimmerLine(width: 50, height: 10),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Container(
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerLine(width: 100, height: 10),
                  SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(child: ShimmerLine(height: 36)),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(child: ShimmerLine(height: 36)),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(child: ShimmerLine(height: 36)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            for (var i = 0; i < 3; i++) ...[
              Container(
                height: 90,
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerLine(width: 120, height: 12),
                    SizedBox(height: AppSpacing.md),
                    ShimmerLine(height: 40),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToastBanner() {
    final isError = _toast!.isError;
    final color = isError ? AppColors.red : AppColors.green;
    final icon = isError ? Icons.error_outline : Icons.check_circle_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              _toast!.message,
              style: AppTheme.uiFont(fontSize: 13, color: color, fontWeight: FontWeight.w500),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _toast = null),
            child: Icon(Icons.close_rounded, color: color.withAlpha(120), size: 16),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.1, end: 0, duration: 200.ms);
  }

  Widget _buildServerInfo() {
    final connected = context.read<OpenCodeAPI>().isConnected;
    final uptime = _serverStatus?['uptime_seconds'] as int? ?? 0;
    final version = _serverStatus?['version'] as String? ?? '?';
    final activeTasks = _serverStatus?['active_tasks'] as int? ?? 0;
    final statusColor = connected ? AppColors.green : AppColors.red;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Server', style: AppTheme.uiFont(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: statusColor.withAlpha(60), blurRadius: 4, spreadRadius: 1)],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                connected ? 'Connected' : 'Disconnected',
                style: AppTheme.uiFont(fontSize: 13, color: statusColor, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Text('v$version', style: AppTheme.codeFont(fontSize: 11, color: AppColors.textMuted)),
              const SizedBox(width: AppSpacing.md),
              Text('${uptime}s up', style: AppTheme.codeFont(fontSize: 11, color: AppColors.textMuted)),
              const SizedBox(width: AppSpacing.md),
              Text('$activeTasks tasks', style: AppTheme.codeFont(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSelector() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Active Provider', style: AppTheme.uiFont(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (final p in ['claude', 'gemini', 'copilot'])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: p != 'copilot' ? AppSpacing.sm : 0),
                    child: _buildProviderChip(p),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProviderChip(String provider) {
    final active = _activeProvider == provider;
    final configured = _providerConfigured[provider] ?? false;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _switchProvider(provider);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: active ? AppColors.purpleDim : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: active ? AppColors.purple.withAlpha(80) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Text(
              provider,
              style: AppTheme.uiFont(
                fontSize: 13,
                color: active ? AppColors.purpleLight : AppColors.textPrimary,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Icon(
              configured ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 14,
              color: configured ? AppColors.green : AppColors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeySection(String provider, String label, TextEditingController controller, String hint) {
    final configured = _providerConfigured[provider] ?? false;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: AppTheme.uiFont(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
              const Spacer(),
              if (configured)
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 14),
                    const SizedBox(width: AppSpacing.xs),
                    Text('Configured', style: AppTheme.uiFont(fontSize: 11, color: AppColors.green, fontWeight: FontWeight.w500)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: true,
                  style: AppTheme.codeFont(fontSize: 13, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: AppTheme.codeFont(fontSize: 13, color: AppColors.textDisabled),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: const BorderSide(color: AppColors.purple, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ElevatedButton(
                onPressed: () {
                  _setApiKey(provider, controller.text.trim());
                  controller.clear();
                },
                child: Text('Save', style: AppTheme.uiFont(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCopilotAuthSection() {
    final configured = _providerConfigured['copilot'] ?? false;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Copilot (GitHub)', style: AppTheme.uiFont(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
              const Spacer(),
              if (configured)
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 14),
                    const SizedBox(width: AppSpacing.xs),
                    Text('Authenticated', style: AppTheme.uiFont(fontSize: 11, color: AppColors.green, fontWeight: FontWeight.w500)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Sign in with your GitHub account — no API key needed.',
            style: AppTheme.uiFont(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_copilotAuthInProgress && _copilotUserCode != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.purple.withAlpha(40)),
              ),
              child: Column(
                children: [
                  Text('1. Copy this code:', style: AppTheme.uiFont(fontSize: 13, color: AppColors.textMuted)),
                  const SizedBox(height: AppSpacing.md),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _copilotUserCode!));
                      _showToast('Code copied!');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.panel,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(color: AppColors.purple.withAlpha(80)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _copilotUserCode!,
                            style: AppTheme.codeFont(fontSize: 32, color: AppColors.purpleLight, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          const Icon(Icons.copy_rounded, size: 18, color: AppColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('2. Paste it on GitHub:', style: AppTheme.uiFont(fontSize: 13, color: AppColors.textMuted)),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final url = _copilotVerificationUri ?? 'https://github.com/login/device';
                        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                      label: const Text('Open GitHub'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.purpleLight,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.purple),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Waiting for authorization...', style: AppTheme.uiFont(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: configured ? null : _startCopilotAuth,
                icon: const Icon(Icons.login_rounded, size: 18),
                label: Text(configured ? 'Connected' : 'Sign in with GitHub'),
                style: ElevatedButton.styleFrom(
                  disabledBackgroundColor: AppColors.surfaceHigh,
                  disabledForegroundColor: AppColors.textDisabled,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _startCopilotAuth() async {
    final api = context.read<OpenCodeAPI>();
    setState(() => _copilotAuthInProgress = true);

    final deviceResp = await api.startCopilotAuth();
    if (!mounted) return;

    if (deviceResp == null) {
      setState(() => _copilotAuthInProgress = false);
      final err = api.lastError ?? 'unknown error';
      AppLogger.instance.error('copilot', 'Auth start failed: $err');
      _showToast('Failed to start Copilot auth: $err', isError: true);
      return;
    }

    setState(() {
      _copilotUserCode = deviceResp['user_code'] as String?;
      _copilotVerificationUri = deviceResp['verification_uri'] as String?;
      _copilotDeviceCode = deviceResp['device_code'] as String?;
    });

    // Poll for authorization
    final interval = (deviceResp['interval'] as int?) ?? 5;
    _pollCopilotAuth(interval);
  }

  Future<void> _pollCopilotAuth(int intervalSec) async {
    if (_copilotDeviceCode == null) return;
    final api = context.read<OpenCodeAPI>();

    for (int i = 0; i < 60; i++) {
      await Future.delayed(Duration(seconds: intervalSec));
      if (!mounted || !_copilotAuthInProgress) return;

      final result = await api.pollCopilotAuth(_copilotDeviceCode!);
      if (result == null) {
        AppLogger.instance.warn('copilot', 'Poll attempt ${i + 1} returned null: ${api.lastError}');
        continue;
      }

      final status = result['status'] as String?;
      if (status == 'success') {
        AppLogger.instance.info('copilot', 'Auth succeeded!');
        setState(() {
          _copilotAuthInProgress = false;
          _copilotUserCode = null;
          _copilotDeviceCode = null;
          _providerConfigured['copilot'] = true;
        });
        _showToast('Copilot authenticated!');
        return;
      } else if (status == 'failed') {
        final err = result['error'] ?? 'unknown';
        AppLogger.instance.error('copilot', 'Auth failed: $err');
        setState(() {
          _copilotAuthInProgress = false;
          _copilotUserCode = null;
          _copilotDeviceCode = null;
        });
        _showToast('Auth failed: $err', isError: true);
        return;
      }
      // pending — keep polling
    }

    // Timed out
    if (mounted) {
      setState(() {
        _copilotAuthInProgress = false;
        _copilotUserCode = null;
        _copilotDeviceCode = null;
      });
      _showToast('Auth timed out — try again', isError: true);
    }
  }

  Widget _buildWorkingDirSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Working Directory', style: AppTheme.uiFont(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _workingDirController,
                  style: AppTheme.codeFont(fontSize: 13, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: '/path/to/project',
                    hintStyle: AppTheme.codeFont(fontSize: 13, color: AppColors.textDisabled),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: const BorderSide(color: AppColors.purple, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ElevatedButton(
                onPressed: () {
                  final dir = _workingDirController.text.trim();
                  if (dir.isEmpty) {
                    _showToast('Directory cannot be empty', isError: true);
                    return;
                  }
                  final api = context.read<OpenCodeAPI>();
                  api.sendWsMessage({
                    'type': 'config.set',
                    'id': 'wd-${DateTime.now().millisecondsSinceEpoch}',
                    'payload': {
                      'key': 'working_dir',
                      'value': dir,
                    },
                  });
                  _showToast('Working directory updated');
                },
                child: Text('Set', style: AppTheme.uiFont(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRuntimeSection() {
    final available = _runtimeStatus?['available'] == true;
    final sizeBytes = _runtimeStatus?['size_bytes'] as int? ?? 0;

    String formatSize(int bytes) {
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Runtime Environment',
                  style: AppTheme.uiFont(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              const Spacer(),
              Icon(
                available ? Icons.check_circle_rounded : Icons.cancel_rounded,
                size: 14,
                color: available ? AppColors.green : AppColors.textDisabled,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                available ? 'Active' : 'Not available',
                style: AppTheme.uiFont(fontSize: 11, color: available ? AppColors.green : AppColors.textDisabled, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (available) ...[
            _runtimeInfoRow('Type', 'proot + Alpine Linux'),
            _runtimeInfoRow('Size', formatSize(sizeBytes)),
            if (_runtimeStatus?['rootfs'] != null)
              _runtimeInfoRow('Rootfs', _runtimeStatus!['rootfs'] as String),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _resetRuntime,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Reset Environment'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red,
                  side: BorderSide(color: AppColors.red.withAlpha(60)),
                ),
              ),
            ),
          ] else ...[
            Text(
              'proot runtime is not configured. On Android, it bootstraps automatically on first launch.',
              style: AppTheme.uiFont(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _runtimeInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: AppTheme.uiFont(fontSize: 12, color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(value, style: AppTheme.codeFont(fontSize: 12, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Logs',
              style: AppTheme.uiFont(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          const SizedBox(height: AppSpacing.md),
          Text(
            'View app and daemon logs for debugging connection, runtime, or API issues.',
            style: AppTheme.uiFont(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showLogsSheet,
              icon: const Icon(Icons.terminal_rounded, size: 16),
              label: const Text('View Logs'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLogsSheet() async {
    final api = context.read<OpenCodeAPI>();

    // Fetch daemon logs (file-based, Android only)
    final daemonLogs = await api.getDaemonLogs() ?? 'No daemon logs (non-Android or daemon not started)';

    // App logs from in-memory buffer
    final appLogs = AppLogger.instance.text.isEmpty ? 'No app logs yet' : AppLogger.instance.text;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.8,
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    Text('Logs',
                        style: AppTheme.uiFont(fontSize: 16, color: AppColors.white, fontWeight: FontWeight.w600)),
                    const SizedBox(width: AppSpacing.sm),
                    Text('${AppLogger.instance.length} entries',
                        style: AppTheme.codeFont(fontSize: 11, color: AppColors.textMuted)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.textMuted),
                      tooltip: 'Copy all logs',
                      onPressed: () {
                        final combined = '=== APP LOGS ===\n$appLogs\n\n=== DAEMON LOGS ===\n$daemonLogs';
                        Clipboard.setData(ClipboardData(text: combined));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('All logs copied to clipboard',
                                style: AppTheme.uiFont(fontSize: 13, color: AppColors.white)),
                            backgroundColor: AppColors.panel,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              // Tab bar
              TabBar(
                indicatorColor: AppColors.purple,
                labelColor: AppColors.purpleLight,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle: AppTheme.uiFont(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: AppTheme.uiFont(fontSize: 13),
                dividerColor: AppColors.border,
                tabs: const [
                  Tab(text: 'App'),
                  Tab(text: 'Daemon'),
                ],
              ),
              // Tab content — each tab gets its own scroll controller
              Expanded(
                child: TabBarView(
                  children: [
                    _buildLogContent(null, appLogs, _colorizeAppLogs),
                    _buildLogContent(null, daemonLogs, null),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogContent(ScrollController? scrollController, String logs, Widget Function(String)? builder) {
    return SingleChildScrollView(
      controller: scrollController,
      reverse: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: builder != null ? builder(logs) : SelectableText(
        logs,
        style: AppTheme.codeFont(fontSize: 11, color: AppColors.green),
      ),
    );
  }

  Widget _colorizeAppLogs(String logs) {
    final lines = logs.split('\n');
    return SelectableText.rich(
      TextSpan(
        children: lines.map((line) {
          Color color = AppColors.textSecondary;
          if (line.contains('ERROR')) {
            color = AppColors.red;
          } else if (line.contains('WARN')) {
            color = AppColors.amber;
          } else if (line.contains('INFO')) {
            color = AppColors.green;
          } else if (line.contains('DEBUG')) {
            color = AppColors.textMuted;
          }
          return TextSpan(
            text: '$line\n',
            style: AppTheme.codeFont(fontSize: 11, color: color),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _resetRuntime() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text('Reset Runtime?', style: AppTheme.uiFont(fontSize: 16, color: AppColors.white, fontWeight: FontWeight.w600)),
        content: Text(
          'This will wipe and re-extract the Alpine Linux environment. Installed packages will be lost.',
          style: AppTheme.uiFont(fontSize: 13, color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppTheme.uiFont(fontSize: 13, color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Reset', style: AppTheme.uiFont(fontSize: 13, color: AppColors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final api = context.read<OpenCodeAPI>();
    _showToast('Resetting runtime...');
    final success = await api.resetRuntime();
    if (mounted) {
      if (success) {
        _showToast('Runtime reset complete');
        _loadConfig();
      } else {
        _showToast('Runtime reset failed', isError: true);
      }
    }
  }
}

class _StatusToast {
  final String message;
  final bool isError;
  const _StatusToast({required this.message, this.isError = false});
}
