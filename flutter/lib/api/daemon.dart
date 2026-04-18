import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'app_logger.dart';

final _log = AppLogger.instance;

class OpenCodeAPI {
  static const _defaultPort = 19280;
  static const _daemonChannel = MethodChannel('io.mocode/daemon');

  String _baseUrl = 'http://127.0.0.1:$_defaultPort';
  String? _username;
  String? _password;
  bool _connected = false;
  String? _sessionId;
  String? _lastError;
  bool _daemonManagedLocally = false;

  // Track subscriptions + channels for cleanup
  WebSocketChannel? _eventChannel;
  StreamSubscription? _eventSubscription;
  int _msgCounter = 0;

  final _messagesController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _responseController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messagesController.stream;
  Stream<Map<String, dynamic>> get responses => _responseController.stream;
  Stream<bool> get connection => _connectionController.stream;
  bool get isConnected => _connected;
  String? get lastError => _lastError;
  String? get sessionId => _sessionId;

  void configure({String? baseUrl, String? username, String? password}) {
    if (baseUrl != null) _baseUrl = baseUrl;
    _username = username;
    _password = password;
  }

  /// Try to discover daemon port from port file, falling back to default.
  Future<void> discoverPort({String? portFilePath}) async {
    final paths = [
      portFilePath,
      './daemon_port',
      '../daemon_port',
      '../backend/daemon_port',
      '/data/data/com.mocode.app/daemon_port',
    ].whereType<String>();

    for (final path in paths) {
      try {
        final content = await File(path).readAsString();
        final port = int.tryParse(content.trim());
        if (port != null && port > 0) {
          _baseUrl = 'http://127.0.0.1:$port';
          _log.info('app', 'Discovered daemon on port $port from $path');
          return;
        }
      } catch (_) {
        // file doesn't exist, try next
      }
    }
    _log.warn('app', 'No port file found, using default port $_defaultPort');
  }

  Map<String, String> get _authHeaders {
    if (_username == null || _password == null) return {};
    final creds = base64Encode(utf8.encode('$_username:$_password'));
    return {'Authorization': 'Basic $creds'};
  }

  Map<String, String> _directoryHeaders(String? directory) {
    if (directory == null) return {};
    return {'X-Opencode-Directory': directory};
  }

  // --- Daemon lifecycle (Android foreground service) ---

  /// Start the Go daemon via the Android foreground service.
  /// No-op on non-Android platforms.
  Future<bool> startDaemon() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _daemonChannel.invokeMethod<bool>('startDaemon');
      _daemonManagedLocally = result == true;
      if (_daemonManagedLocally) {
        // Wait for daemon to initialize and write its port file.
        await Future.delayed(const Duration(seconds: 2));
      }
      return _daemonManagedLocally;
    } on PlatformException catch (e) {
      _log.error('app', 'Failed to start daemon service: ${e.message}');
      return false;
    } on MissingPluginException {
      _log.warn('app', 'Daemon platform channel not available (non-Android?)');
      return false;
    }
  }

  /// Stop the daemon foreground service.
  Future<bool> stopDaemon() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _daemonChannel.invokeMethod<bool>('stopDaemon');
      _daemonManagedLocally = false;
      return result == true;
    } on MissingPluginException {
      return false;
    }
  }

  /// Check if the daemon process is running (via foreground service).
  Future<bool> isDaemonRunning() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _daemonChannel.invokeMethod<bool>('isRunning') == true;
    } on MissingPluginException {
      return false;
    }
  }

  /// Get the port the daemon is listening on (from the service).
  Future<int> getDaemonPort() async {
    if (!Platform.isAndroid) return 0;
    try {
      return await _daemonChannel.invokeMethod<int>('getPort') ?? 0;
    } on MissingPluginException {
      return 0;
    }
  }

  Future<void> connect() async {
    _log.info('app', 'Connecting to daemon...');

    // On Android, start the daemon if it's not already running.
    if (Platform.isAndroid) {
      final running = await isDaemonRunning();
      if (!running) {
        _log.info('app', 'Daemon not running, starting foreground service...');
        await startDaemon();
      } else {
        _log.info('app', 'Daemon already running');
      }
      // Try to get port from the service first.
      final servicePort = await getDaemonPort();
      if (servicePort > 0) {
        _baseUrl = 'http://127.0.0.1:$servicePort';
        _log.info('app', 'Using daemon port from service: $servicePort');
      } else {
        _log.warn('app', 'Service returned port 0, discovering from port file...');
        await discoverPort();
      }
    } else {
      await discoverPort();
    }

    _log.info('http', 'Health check → $_baseUrl/api/health');
    try {
      final health = await fetchHealth();
      if (health != null && (health['healthy'] == true || health['status'] == 'ok')) {
        _connected = true;
        _connectionController.add(true);
        _lastError = null;
        _log.info('http', 'Health check passed ✓');
        _startEventStream();
      } else {
        _log.error('http', 'Health check returned unhealthy: $health');
        throw Exception('Server not healthy');
      }
    } catch (e) {
      _connected = false;
      _connectionController.add(false);
      _lastError = e.toString();
      _log.error('http', 'Connection failed: $e');
      rethrow;
    }
  }

  int _wsReconnectAttempt = 0;
  Timer? _wsReconnectTimer;
  static const _wsMaxReconnectDelay = Duration(seconds: 30);
  static const _wsMaxReconnectAttempts = 10;

  void _startEventStream() {
    // Clean up any previous subscription
    _eventSubscription?.cancel();
    _eventChannel?.sink.close();
    _wsReconnectTimer?.cancel();

    try {
      final wsUrl = '${_baseUrl.replaceFirst('http', 'ws')}/ws';
      _log.info('ws', 'Connecting to $wsUrl');
      _eventChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _eventSubscription = _eventChannel!.stream.listen(
        (data) {
          _wsReconnectAttempt = 0; // Reset on successful data.
          try {
            final decoded = jsonDecode(data as String) as Map<String, dynamic>;
            final type = decoded['type'] as String? ?? '';
            // Log important events (skip noisy stream chunks)
            if (type == 'task.complete') {
              _log.info('task', 'Task completed: ${decoded['task_id']}');
            } else if (type == 'task.failed') {
              final payload = decoded['payload'] as Map<String, dynamic>? ?? {};
              _log.error('task', 'Task failed: ${payload['error'] ?? decoded['task_id']}');
            } else if (type == 'error') {
              final payload = decoded['payload'] as Map<String, dynamic>? ?? {};
              _log.error('ws', 'Server error: ${payload['message'] ?? payload}');
            } else if (type == 'config.current') {
              _log.info('app', 'Config updated: provider=${(decoded['payload'] as Map?)?['active_provider']}');
            }
            _messagesController.add(decoded);
          } catch (e) {
            _log.error('ws', 'Event parse error: $e');
          }
        },
        onError: (e) {
          _log.error('ws', 'Stream error: $e');
          _connected = false;
          _connectionController.add(false);
          _scheduleWsReconnect();
        },
        onDone: () {
          _log.warn('ws', 'Stream closed');
          _connected = false;
          _connectionController.add(false);
          _scheduleWsReconnect();
        },
      );
    } catch (e) {
      _log.error('ws', 'Failed to start event stream: $e');
      _scheduleWsReconnect();
    }
  }

  void _scheduleWsReconnect() {
    if (_wsReconnectAttempt >= _wsMaxReconnectAttempts) {
      _log.error('ws', 'Max reconnect attempts reached ($_wsMaxReconnectAttempts). Giving up.');
      return;
    }
    _wsReconnectTimer?.cancel();
    _wsReconnectAttempt++;
    // Exponential backoff: 1s, 2s, 4s, 8s, ... capped at 30s.
    final delaySec = Duration(
      seconds: (1 << (_wsReconnectAttempt - 1))
          .clamp(1, _wsMaxReconnectDelay.inSeconds),
    );
    _log.info('ws', 'Reconnecting in ${delaySec.inSeconds}s (attempt $_wsReconnectAttempt/$_wsMaxReconnectAttempts)');
    _wsReconnectTimer = Timer(delaySec, () async {
      // Verify daemon is still healthy before reconnecting.
      final health = await fetchHealth();
      if (health != null) {
        _connected = true;
        _connectionController.add(true);
        _startEventStream();
      } else {
        _scheduleWsReconnect();
      }
    });
  }

  Future<Map<String, dynamic>?> fetchHealth() async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/api/health'),
        headers: _authHeaders,
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      _lastError = 'Health check returned ${resp.statusCode}';
      _log.error('http', _lastError!);
      return null;
    } catch (e) {
      _lastError = 'Health check failed: $e';
      _log.error('http', _lastError!);
      return null;
    }
  }

  Future<String?> createSession({String? title, String? directory}) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/session'),
        headers: {'Content-Type': 'application/json', ..._authHeaders, ..._directoryHeaders(directory)},
        body: jsonEncode({'title': title ?? 'Mo-Code Session'}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _sessionId = data['id'] as String?;
        return _sessionId;
      }
      _lastError = 'Create session: HTTP ${resp.statusCode}';
      return null;
    } catch (e) {
      _lastError = 'Create session failed: $e';
      _log.error('http', _lastError!);
      return null;
    }
  }

  Future<Map<String, dynamic>?> sendMessage(String sessionId, String text, {String? model}) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/session/$sessionId/message'),
        headers: {'Content-Type': 'application/json', ..._authHeaders},
        body: jsonEncode({
          'parts': [{'type': 'text', 'text': text}],
          if (model != null) 'model': model,
        }),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _responseController.add(data);
        return data;
      }
      _lastError = 'Send message: HTTP ${resp.statusCode}';
      return null;
    } catch (e) {
      _lastError = 'Send message failed: $e';
      _log.error('http', _lastError!);
      return null;
    }
  }

  Future<Map<String, dynamic>?> sendMessageAsync(String sessionId, String text, {String? model}) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/session/$sessionId/prompt_async'),
        headers: {'Content-Type': 'application/json', ..._authHeaders},
        body: jsonEncode({
          'parts': [{'type': 'text', 'text': text}],
          if (model != null) 'model': model,
        }),
      );
      return resp.statusCode == 204 ? {'status': 'queued'} : null;
    } catch (e) {
      _lastError = 'Send async message failed: $e';
      _log.error('http', _lastError!);
      return null;
    }
  }

  Future<Map<String, dynamic>?> getFileContent(String path, {String? directory}) async {
    try {
      final encoded = Uri.encodeComponent(path);
      var url = '$_baseUrl/file/content?path=$encoded';
      if (directory != null) {
        url += '&directory=${Uri.encodeComponent(directory)}';
      }
      final resp = await http.get(
        Uri.parse(url),
        headers: _authHeaders,
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      _log.error('http', 'Get file content failed: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> findFiles(String query, {String? directory}) async {
    try {
      var url = '$_baseUrl/find/file?query=${Uri.encodeComponent(query)}&limit=20';
      if (directory != null) {
        url += '&directory=${Uri.encodeComponent(directory)}';
      }
      final resp = await http.get(
        Uri.parse(url),
        headers: _authHeaders,
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return (data['files'] as List?)?.cast<Map<String, dynamic>>();
      }
      return null;
    } catch (e) {
      _log.error('http', 'Find files failed: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> findInFiles(String pattern, {String? directory}) async {
    try {
      var url = '$_baseUrl/find?pattern=${Uri.encodeComponent(pattern)}&limit=50';
      if (directory != null) {
        url += '&directory=${Uri.encodeComponent(directory)}';
      }
      final resp = await http.get(
        Uri.parse(url),
        headers: _authHeaders,
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return (data['matches'] as List?)?.cast<Map<String, dynamic>>();
      }
      return null;
    } catch (e) {
      _log.error('http', 'Find failed: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> listSessions({String? directory}) async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/session'),
        headers: {..._authHeaders, ..._directoryHeaders(directory)},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return (data['sessions'] as List?)?.cast<Map<String, dynamic>>();
      }
      return null;
    } catch (e) {
      _log.error('http', 'List sessions failed: $e');
      return null;
    }
  }

  // --- Daemon logs ---

  /// Get the last 200 lines of daemon logs (Android only).
  Future<String?> getDaemonLogs() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _daemonChannel.invokeMethod<String>('getLogs');
    } on MissingPluginException {
      return null;
    }
  }

  // --- Runtime environment (proot + Alpine) ---

  /// Get runtime bootstrap status from the platform channel (Android only).
  Future<Map<String, dynamic>?> getRuntimeStatus() async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _daemonChannel.invokeMethod<Map>('getRuntimeStatus');
      return result?.cast<String, dynamic>();
    } on MissingPluginException {
      return null;
    }
  }

  /// Reset the runtime — wipes and re-extracts proot + Alpine rootfs.
  Future<bool> resetRuntime() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _daemonChannel.invokeMethod<bool>('resetRuntime') == true;
    } on MissingPluginException {
      return false;
    }
  }

  /// Run proot diagnostics via the Go daemon HTTP endpoint (POST /api/runtime/diagnose).
  /// Returns a map with keys: ok, bin_exists, bin_executable, loader_exists,
  /// rootfs_exists, echo_ok, exit_code, stderr, error.
  /// Returns null on network error. Returns {"error":"proot not configured"} when
  /// proot is disabled on the daemon side.
  Future<Map<String, dynamic>?> runProotDiagnostic() async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/runtime/diagnose'),
        headers: _authHeaders,
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      _log.error('http', 'Runtime diagnose: HTTP ${resp.statusCode}');
      return null;
    } catch (e) {
      _log.error('http', 'Runtime diagnose failed: $e');
      return null;
    }
  }

  /// Fetch runtime status from the Go daemon HTTP endpoint.
  Future<Map<String, dynamic>?> fetchRuntimeStatus() async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/api/runtime/status'),
        headers: _authHeaders,
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      _log.error('http', 'Fetch runtime status failed: $e');
      return null;
    }
  }

  // --- Config & Status (for ConfigScreen) ---

  Future<Map<String, dynamic>?> fetchConfig() async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/api/config'),
        headers: _authHeaders,
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      _lastError = 'Fetch config: HTTP ${resp.statusCode}';
      return null;
    } catch (e) {
      _lastError = 'Fetch config failed: $e';
      _log.error('http', _lastError!);
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchStatus() async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/api/status'),
        headers: _authHeaders,
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      _lastError = 'Fetch status: HTTP ${resp.statusCode}';
      return null;
    } catch (e) {
      _lastError = 'Fetch status failed: $e';
      _log.error('http', _lastError!);
      return null;
    }
  }

  /// Send a raw message via HTTP POST (for config.set, provider.switch, etc.)
  Future<bool> sendWsMessage(Map<String, dynamic> message) async {
    final type = message['type'] as String?;
    final payload = message['payload'] as Map<String, dynamic>?;
    if (type == null || payload == null) return false;

    switch (type) {
      case 'config.set':
        return _postJson('/api/config', payload);
      case 'provider.switch':
        return _postJson('/api/provider/switch', payload);
      default:
        _log.warn('ws', 'sendWsMessage: unsupported type $type');
        return false;
    }
  }

  Future<bool> _postJson(String path, Map<String, dynamic> body) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl$path'),
        headers: {'Content-Type': 'application/json', ..._authHeaders},
        body: jsonEncode(body),
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) return true;
      _lastError = 'POST $path: HTTP ${resp.statusCode}';
      return false;
    } catch (e) {
      _lastError = 'POST $path failed: $e';
      _log.error('http', _lastError!);
      return false;
    }
  }

  // --- Copilot Device Auth ---

  Future<Map<String, dynamic>?> startCopilotAuth() async {
    _log.info('http', 'POST /api/auth/copilot/device');
    try {
      // 75s: daemon needs up to 60s for GitHub TLS handshake on first connect.
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/copilot/device'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 75));
      if (resp.statusCode == 200) {
        _log.info('http', 'Copilot device auth started');
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      _lastError = 'Start copilot auth: HTTP ${resp.statusCode} — ${resp.body}';
      _log.error('http', _lastError!);
      return null;
    } catch (e) {
      _lastError = 'Start copilot auth failed: $e';
      _log.error('http', _lastError!);
      return null;
    }
  }

  Future<Map<String, dynamic>?> pollCopilotAuth(String deviceCode) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/auth/copilot/poll'),
        headers: {'Content-Type': 'application/json', ..._authHeaders},
        body: jsonEncode({'device_code': deviceCode}),
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      _lastError = 'Poll copilot auth: HTTP ${resp.statusCode} — ${resp.body}';
      _log.error('http', _lastError!);
      return null;
    } catch (e) {
      _lastError = 'Poll copilot auth failed: $e';
      _log.error('http', _lastError!);
      return null;
    }
  }

  // --- WebSocket message sending ---

  /// Send a JSON message over the active WebSocket connection.
  bool sendWsJson(Map<String, dynamic> message) {
    if (_eventChannel == null) {
      _log.warn('ws', 'sendWsJson: no WebSocket connection');
      return false;
    }
    try {
      _eventChannel!.sink.add(jsonEncode(message));
      return true;
    } catch (e) {
      _log.error('ws', 'sendWsJson failed: $e');
      return false;
    }
  }

  /// Send a task.start message over WebSocket to begin an agent task.
  /// If [taskId] is provided, it's used as the message ID (for session reuse).
  String? startTask(String prompt, {String? provider, String? workingDir, String? taskId}) {
    _msgCounter++;
    final id = taskId ?? 'msg-$_msgCounter-${DateTime.now().millisecondsSinceEpoch}';
    _log.info('task', 'Starting task $id: "${prompt.length > 60 ? '${prompt.substring(0, 60)}...' : prompt}"');
    final sent = sendWsJson({
      'type': 'task.start',
      'id': id,
      'payload': {
        'prompt': prompt,
        if (provider != null) 'provider': provider,
        if (workingDir != null) 'working_dir': workingDir,
      },
    });
    return sent ? id : null;
  }

  /// Send a task.cancel message over WebSocket.
  bool cancelTask(String taskId) {
    return sendWsJson({
      'type': 'task.cancel',
      'id': 'cancel-${DateTime.now().millisecondsSinceEpoch}',
      'task_id': taskId,
    });
  }

  /// Invoke a tool directly on the daemon without going through the LLM.
  /// Backs the chat `!<cmd>` shell-bypass feature: we send
  /// `direct_tool_call` and the daemon replies with `direct_tool_result`.
  /// The returned ID lets callers correlate the response.
  String? sendDirectToolCall(
    String tool, {
    Map<String, dynamic>? args,
  }) {
    _msgCounter++;
    final id = 'dt-$_msgCounter-${DateTime.now().millisecondsSinceEpoch}';
    final sent = sendWsJson({
      'type': 'direct_tool_call',
      'id': id,
      'payload': {
        'tool': tool,
        if (args != null) 'args': args,
      },
    });
    if (sent) {
      _log.info('ws', 'direct_tool_call → $tool (id=$id)');
    }
    return sent ? id : null;
  }

  // --- Session management via WebSocket ---

  /// Request session list via WebSocket. Response arrives on messages stream
  /// as a message with type 'session.list_result'.
  String? requestSessionList() {
    _msgCounter++;
    final id = 'sess-list-$_msgCounter';
    final sent = sendWsJson({
      'type': 'session.list',
      'id': id,
    });
    return sent ? id : null;
  }

  /// Request a single session by ID. Response arrives as 'session.get_result'.
  String? requestSessionGet(String sessionId) {
    _msgCounter++;
    final id = 'sess-get-$_msgCounter';
    final sent = sendWsJson({
      'type': 'session.get',
      'id': id,
      'payload': {'id': sessionId},
    });
    return sent ? id : null;
  }

  /// Resume a session with a new prompt. Events stream as 'agent.stream'.
  String? resumeSession(String sessionId, String prompt) {
    _msgCounter++;
    final id = 'sess-resume-$_msgCounter';
    final sent = sendWsJson({
      'type': 'session.resume',
      'id': id,
      'payload': {'id': sessionId, 'prompt': prompt},
    });
    return sent ? id : null;
  }

  /// Delete a session. Response arrives as 'session.list_result' with updated list.
  String? deleteSession(String sessionId) {
    _msgCounter++;
    final id = 'sess-del-$_msgCounter';
    final sent = sendWsJson({
      'type': 'session.delete',
      'id': id,
      'payload': {'id': sessionId},
    });
    return sent ? id : null;
  }

  /// Wait for a specific message type from the WS stream with a timeout.
  Future<Map<String, dynamic>?> waitForMessage(String type, {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      return await messages
          .where((msg) => msg['type'] == type)
          .first
          .timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  Future<void> disconnect() async {
    _wsReconnectTimer?.cancel();
    _wsReconnectAttempt = 0;
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _eventChannel?.sink.close();
    _eventChannel = null;
    _connected = false;
    _connectionController.add(false);
    _sessionId = null;
  }

  void dispose() {
    disconnect();
    _messagesController.close();
    _connectionController.close();
    _responseController.close();
  }
}
