import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

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
          debugPrint('Discovered daemon on port $port from $path');
          return;
        }
      } catch (_) {
        // file doesn't exist, try next
      }
    }
    debugPrint('No port file found, using default port $_defaultPort');
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
    } on MissingPluginException {
      debugPrint('Daemon platform channel not available');
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
    // On Android, start the daemon if it's not already running.
    if (Platform.isAndroid) {
      final running = await isDaemonRunning();
      if (!running) {
        await startDaemon();
      }
      // Try to get port from the service first.
      final servicePort = await getDaemonPort();
      if (servicePort > 0) {
        _baseUrl = 'http://127.0.0.1:$servicePort';
        debugPrint('Using daemon port from service: $servicePort');
      } else {
        await discoverPort();
      }
    } else {
      await discoverPort();
    }

    try {
      final health = await fetchHealth();
      if (health != null && (health['healthy'] == true || health['status'] == 'ok')) {
        _connected = true;
        _connectionController.add(true);
        _lastError = null;
        _startEventStream();
      } else {
        throw Exception('Server not healthy');
      }
    } catch (e) {
      _connected = false;
      _connectionController.add(false);
      _lastError = e.toString();
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
      _eventChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _eventSubscription = _eventChannel!.stream.listen(
        (data) {
          _wsReconnectAttempt = 0; // Reset on successful data.
          try {
            final decoded = jsonDecode(data as String) as Map<String, dynamic>;
            _messagesController.add(decoded);
          } catch (e) {
            debugPrint('Event parse error: $e');
          }
        },
        onError: (e) {
          debugPrint('Event stream error: $e');
          _connected = false;
          _connectionController.add(false);
          _scheduleWsReconnect();
        },
        onDone: () {
          debugPrint('Event stream closed');
          _connected = false;
          _connectionController.add(false);
          _scheduleWsReconnect();
        },
      );
    } catch (e) {
      debugPrint('Failed to start event stream: $e');
      _scheduleWsReconnect();
    }
  }

  void _scheduleWsReconnect() {
    if (_wsReconnectAttempt >= _wsMaxReconnectAttempts) {
      debugPrint('WebSocket: max reconnect attempts reached');
      return;
    }
    _wsReconnectTimer?.cancel();
    _wsReconnectAttempt++;
    // Exponential backoff: 1s, 2s, 4s, 8s, ... capped at 30s.
    final delaySec = Duration(
      seconds: (1 << (_wsReconnectAttempt - 1))
          .clamp(1, _wsMaxReconnectDelay.inSeconds),
    );
    debugPrint('WebSocket: reconnecting in ${delaySec.inSeconds}s (attempt $_wsReconnectAttempt)');
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
      return null;
    } catch (e) {
      _lastError = 'Health check failed: $e';
      debugPrint(_lastError!);
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
      debugPrint(_lastError!);
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
      debugPrint(_lastError!);
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
      debugPrint(_lastError!);
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
      debugPrint('Get file content failed: $e');
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
      debugPrint('Find files failed: $e');
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
      debugPrint('Find failed: $e');
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
      debugPrint('List sessions failed: $e');
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
      debugPrint('Fetch runtime status failed: $e');
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
      debugPrint(_lastError!);
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
      debugPrint(_lastError!);
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
        debugPrint('sendWsMessage: unsupported type $type');
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
      debugPrint(_lastError!);
      return false;
    }
  }

  // --- Copilot Device Auth ---

  Future<Map<String, dynamic>?> startCopilotAuth() async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/auth/copilot/device'),
        headers: _authHeaders,
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      _lastError = 'Start copilot auth: HTTP ${resp.statusCode}';
      return null;
    } catch (e) {
      _lastError = 'Start copilot auth failed: $e';
      debugPrint(_lastError!);
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
      _lastError = 'Poll copilot auth: HTTP ${resp.statusCode}';
      return null;
    } catch (e) {
      _lastError = 'Poll copilot auth failed: $e';
      debugPrint(_lastError!);
      return null;
    }
  }

  // --- WebSocket message sending ---

  /// Send a JSON message over the active WebSocket connection.
  bool sendWsJson(Map<String, dynamic> message) {
    if (_eventChannel == null) {
      debugPrint('sendWsJson: no WebSocket connection');
      return false;
    }
    try {
      _eventChannel!.sink.add(jsonEncode(message));
      return true;
    } catch (e) {
      debugPrint('sendWsJson failed: $e');
      return false;
    }
  }

  /// Send a task.start message over WebSocket to begin an agent task.
  String? startTask(String prompt, {String? provider, String? workingDir}) {
    _msgCounter++;
    final id = 'msg-$_msgCounter-${DateTime.now().millisecondsSinceEpoch}';
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
