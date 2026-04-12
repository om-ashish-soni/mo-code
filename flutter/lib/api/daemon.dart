import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class OpenCodeAPI {
  String _baseUrl = 'http://127.0.0.1:4096';
  String? _username;
  String? _password;
  bool _connected = false;
  String? _sessionId;
  String? _lastError;

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
    try {
      final health = await fetchHealth();
      if (health != null && health['healthy'] == true) {
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
    try {
      final wsUrl = '${_baseUrl.replaceFirst('http', 'ws')}/global/event';
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      channel.stream.listen(
        (data) {
          try {
            final lines = (data as String).split('\n');
            for (final line in lines) {
              if (line.startsWith('data: ')) {
                final json = jsonDecode(line.substring(6)) as Map<String, dynamic>;
                final payload = json['payload'] as Map<String, dynamic>?;
                if (payload != null) {
                  _messagesController.add(payload);
                }
              }
            }
          } catch (e) {
            debugPrint('Event parse error: $e');
          }
        },
        onError: (e) {
          debugPrint('Event stream error: $e');
        },
        onDone: () {
          debugPrint('Event stream closed');
        },
      );
    } catch (e) {
      debugPrint('Failed to start event stream: $e');
    }
  }

  Future<Map<String, dynamic>?> fetchHealth() async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/global/health'),
        headers: _authHeaders,
      );
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Health check failed: $e');
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
      return null;
    } catch (e) {
      debugPrint('Create session failed: $e');
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
      return null;
    } catch (e) {
      debugPrint('Send message failed: $e');
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
      debugPrint('Send async message failed: $e');
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
      return null;
    } catch (e) {
      debugPrint('Fetch config failed: $e');
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
      return null;
    } catch (e) {
      debugPrint('Fetch status failed: $e');
      return null;
    }
  }

  /// Send a raw message via WebSocket (for config.set, provider.switch, etc.)
  void sendWsMessage(Map<String, dynamic> message) {
    // For now, route config/provider changes through HTTP POST
    final type = message['type'] as String?;
    final payload = message['payload'] as Map<String, dynamic>?;
    if (type == null || payload == null) return;

    switch (type) {
      case 'config.set':
        _postJson('/api/config', payload);
        break;
      case 'provider.switch':
        _postJson('/api/provider/switch', payload);
        break;
      default:
        debugPrint('sendWsMessage: unsupported type $type');
    }
  }

  Future<void> _postJson(String path, Map<String, dynamic> body) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl$path'),
        headers: {'Content-Type': 'application/json', ..._authHeaders},
        body: jsonEncode(body),
      );
    } catch (e) {
      debugPrint('POST $path failed: $e');
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
      return null;
    } catch (e) {
      debugPrint('Start copilot auth failed: $e');
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
      return null;
    } catch (e) {
      debugPrint('Poll copilot auth failed: $e');
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
