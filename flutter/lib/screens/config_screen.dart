import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/daemon.dart';
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
    final config = await api.fetchConfig();
    final status = await api.fetchStatus();

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
        title: const Text('Config', style: TextStyle(color: AppColors.white, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textMuted),
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
      padding: const EdgeInsets.all(16),
      children: [
        if (_toast != null) _buildToastBanner(),
        _buildServerInfo(),
        const SizedBox(height: 20),
        _buildProviderSelector(),
        const SizedBox(height: 20),
        _buildApiKeySection('claude', 'Claude (Anthropic)', _claudeKeyController, 'sk-ant-...'),
        const SizedBox(height: 12),
        _buildApiKeySection('gemini', 'Gemini (Google)', _geminiKeyController, 'AIza...'),
        const SizedBox(height: 12),
        _buildCopilotAuthSection(),
        const SizedBox(height: 20),
        _buildWorkingDirSection(),
      ],
    );
  }

  Widget _buildLoadingSkeleton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ShimmerLoading(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Server info skeleton
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(12),
              child: const Row(
                children: [
                  ShimmerLine(width: 80, height: 14),
                  Spacer(),
                  ShimmerLine(width: 50, height: 10),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Provider selector skeleton
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(12),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerLine(width: 100, height: 10),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: ShimmerLine(height: 36)),
                      SizedBox(width: 8),
                      Expanded(child: ShimmerLine(height: 36)),
                      SizedBox(width: 8),
                      Expanded(child: ShimmerLine(height: 36)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // API key sections skeleton
            for (var i = 0; i < 3; i++) ...[
              Container(
                height: 90,
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.all(12),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerLine(width: 120, height: 12),
                    SizedBox(height: 12),
                    ShimmerLine(height: 40),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToastBanner() {
    final isError = _toast!.isError;
    final color = isError ? AppColors.red : AppColors.green;
    final icon = isError ? Icons.error_outline : Icons.check_circle;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _toast!.message,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _toast = null),
            child: Icon(Icons.close, color: color.withAlpha(120), size: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildServerInfo() {
    final connected = context.read<OpenCodeAPI>().isConnected;
    final uptime = _serverStatus?['uptime_seconds'] as int? ?? 0;
    final version = _serverStatus?['version'] as String? ?? '?';
    final activeTasks = _serverStatus?['active_tasks'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Server', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: connected ? AppColors.green : AppColors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                connected ? 'Connected' : 'Disconnected',
                style: TextStyle(color: connected ? AppColors.green : AppColors.red, fontSize: 13),
              ),
              const Spacer(),
              Text('v$version', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(width: 12),
              Text('${uptime}s up', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(width: 12),
              Text('$activeTasks tasks', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Active Provider', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final p in ['claude', 'gemini', 'copilot'])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: p != 'copilot' ? 8 : 0),
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
      onTap: () => _switchProvider(provider),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.purple.withAlpha(40) : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.purple : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            Text(
              provider,
              style: TextStyle(
                color: active ? AppColors.purple : AppColors.textPrimary,
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 4),
            Icon(
              configured ? Icons.check_circle : Icons.cancel,
              size: 12,
              color: configured ? AppColors.green : AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeySection(String provider, String label, TextEditingController controller, String hint) {
    final configured = _providerConfigured[provider] ?? false;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
              const Spacer(),
              if (configured)
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColors.green, size: 14),
                    SizedBox(width: 4),
                    Text('Configured', style: TextStyle(color: AppColors.green, fontSize: 11)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: true,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.purple),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  _setApiKey(provider, controller.text.trim());
                  controller.clear();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Save', style: TextStyle(fontSize: 13)),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Copilot (GitHub)', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
              const Spacer(),
              if (configured)
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColors.green, size: 14),
                    SizedBox(width: 4),
                    Text('Authenticated', style: TextStyle(color: AppColors.green, fontSize: 11)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Sign in with your GitHub account — no API key needed.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (_copilotAuthInProgress && _copilotUserCode != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.purple.withAlpha(80)),
              ),
              child: Column(
                children: [
                  const Text('Enter this code at github.com/login/device:', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 8),
                  SelectableText(
                    _copilotUserCode!,
                    style: const TextStyle(color: AppColors.purple, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _copilotVerificationUri ?? 'https://github.com/login/device',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.purple),
                  ),
                  const SizedBox(height: 4),
                  const Text('Waiting for authorization...', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: configured ? null : _startCopilotAuth,
                icon: const Icon(Icons.login, size: 16),
                label: Text(configured ? 'Connected' : 'Sign in with GitHub'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  foregroundColor: AppColors.white,
                  disabledBackgroundColor: AppColors.border,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
      _showToast('Failed to start Copilot auth', isError: true);
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
      if (result == null) continue;

      final status = result['status'] as String?;
      if (status == 'success') {
        setState(() {
          _copilotAuthInProgress = false;
          _copilotUserCode = null;
          _copilotDeviceCode = null;
          _providerConfigured['copilot'] = true;
        });
        _showToast('Copilot authenticated!');
        return;
      } else if (status == 'failed') {
        setState(() {
          _copilotAuthInProgress = false;
          _copilotUserCode = null;
          _copilotDeviceCode = null;
        });
        _showToast('Auth failed: ${result['error'] ?? 'unknown'}', isError: true);
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Working Directory', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _workingDirController,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '/path/to/project',
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.purple),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Set', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusToast {
  final String message;
  final bool isError;
  const _StatusToast({required this.message, this.isError = false});
}
