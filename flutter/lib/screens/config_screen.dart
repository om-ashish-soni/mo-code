import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/daemon.dart';
import '../theme/colors.dart';

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
  bool _loading = true;
  String? _statusMessage;
  Map<String, dynamic>? _serverStatus;

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
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final api = context.read<OpenCodeAPI>();
    final config = await api.fetchConfig();
    final status = await api.fetchStatus();

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
        _statusMessage = 'Failed to load config. Is the daemon running?';
      });
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _statusMessage = null);
      });
    }
  }

  void _setApiKey(String provider, String key) {
    if (key.trim().isEmpty) {
      setState(() => _statusMessage = 'API key cannot be empty');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _statusMessage = null);
      });
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
    setState(() {
      _statusMessage = '${provider.toUpperCase()} API key saved';
      _providerConfigured[provider] = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _statusMessage = null);
    });
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
    setState(() {
      _activeProvider = provider;
      _statusMessage = 'Switched to $provider';
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _statusMessage = null);
    });
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_statusMessage != null) _buildStatusBanner(),
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
            ),
    );
  }

  Widget _buildStatusBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.green.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.green.withAlpha(80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.green, size: 16),
          const SizedBox(width: 8),
          Text(_statusMessage!, style: const TextStyle(color: AppColors.green, fontSize: 13)),
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
    if (deviceResp == null) {
      setState(() {
        _copilotAuthInProgress = false;
        _statusMessage = 'Failed to start Copilot auth';
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _statusMessage = null);
      });
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
          _statusMessage = 'Copilot authenticated!';
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _statusMessage = null);
        });
        return;
      } else if (status == 'failed') {
        setState(() {
          _copilotAuthInProgress = false;
          _copilotUserCode = null;
          _copilotDeviceCode = null;
          _statusMessage = 'Auth failed: ${result['error'] ?? 'unknown'}';
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _statusMessage = null);
        });
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
        _statusMessage = 'Auth timed out — try again';
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _statusMessage = null);
      });
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
                  final api = context.read<OpenCodeAPI>();
                  api.sendWsMessage({
                    'type': 'config.set',
                    'id': 'wd-${DateTime.now().millisecondsSinceEpoch}',
                    'payload': {
                      'key': 'working_dir',
                      'value': _workingDirController.text.trim(),
                    },
                  });
                  setState(() => _statusMessage = 'Working directory updated');
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) setState(() => _statusMessage = null);
                  });
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
