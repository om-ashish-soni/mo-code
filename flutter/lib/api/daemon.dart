import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class OpenCodeAPI {
  static const _defaultPort = 19280;

  String _baseUrl = 'http://127.0.0.1:$_defaultPort';
  String? _username;
  String? _password;
  bool _connected = false;
  String? _sessionId;
  String? _lastError;

  // Track subscriptions + channels for cleanup
  WebSocketChannel? _eventChannel;
  StreamSubscription? _eventSubscription;

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

  Future<void> connect() async {
    // Try port discovery before connecting
    await discoverPort();

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

  void _startEventStream() {
    // Clean up any previous subscription
    _eventSubscription?.cancel();
    _eventChannel?.sink.close();

    try {
      final wsUrl = '${_baseUrl.replaceFirst('http', 'ws')}/ws';
      _eventChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _eventSubscription = _eventChannel!.stream.listen(
        (data) {
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
        },
        onDone: () {
          debugPrint('Event stream closed');
          _connected = false;
          _connectionController.add(false);
        },
      );
    } catch (e) {
      debugPrint('Failed to start event stream: $e');
    }
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

  // --- Cancel/Stop task ---

  Future<bool> cancelSession(String sessionId) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/session/$sessionId/cancel'),
        headers: _authHeaders,
      );
      return resp.statusCode == 200 || resp.statusCode == 204;
    } catch (e) {
      debugPrint('Cancel session failed: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
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
