class RawMessage {
  final String type;
  final String? id;
  final String? taskId;
  final Map<String, dynamic>? payload;

  RawMessage({
    required this.type,
    this.id,
    this.taskId,
    this.payload,
  });

  factory RawMessage.fromJson(Map<String, dynamic> json) {
    return RawMessage(
      type: json['type'] as String,
      id: json['id'] as String?,
      taskId: json['task_id'] as String?,
      payload: json['payload'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    if (id != null) 'id': id,
    if (taskId != null) 'task_id': taskId,
    if (payload != null) 'payload': payload,
  };
}

class OutMessage {
  final String type;
  final String? id;
  final String? taskId;
  final dynamic payload;

  OutMessage({
    required this.type,
    this.id,
    this.taskId,
    this.payload,
  });

  factory OutMessage.fromJson(Map<String, dynamic> json) {
    return OutMessage(
      type: json['type'] as String,
      id: json['id'] as String?,
      taskId: json['task_id'] as String?,
      payload: json['payload'],
    );
  }
}

class TerminalLine {
  final TerminalLineType type;
  final String content;
  final DateTime timestamp;

  TerminalLine({required this.type, this.content = '', DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}

enum TerminalLineType {
  userInput,
  agentThinking,
  planStep,
  fileCreated,
  fileModified,
  fileDeleted,
  toolCall,
  tokenCount,
  separator,
  text,
  error,
}

class ConfigState {
  final String activeProvider;
  final Map<String, ProviderStatus> providers;
  final String? workingDir;

  ConfigState({
    required this.activeProvider,
    required this.providers,
    this.workingDir,
  });

  factory ConfigState.fromJson(Map<String, dynamic> json) {
    final providers = <String, ProviderStatus>{};
    if (json['providers'] != null) {
      (json['providers'] as Map<String, dynamic>).forEach((key, value) {
        providers[key] = ProviderStatus.fromJson(value as Map<String, dynamic>);
      });
    }
    return ConfigState(
      activeProvider: json['active_provider'] as String? ?? 'claude',
      providers: providers,
      workingDir: json['working_dir'] as String?,
    );
  }
}

class ProviderStatus {
  final bool configured;
  final String? model;

  ProviderStatus({required this.configured, this.model});

  factory ProviderStatus.fromJson(Map<String, dynamic> json) {
    return ProviderStatus(
      configured: json['configured'] as bool? ?? false,
      model: json['model'] as String?,
    );
  }
}

class TaskState {
  final String taskId;
  final TaskStateStatus status;
  final String? error;

  TaskState({required this.taskId, required this.status, this.error});
}

enum TaskStateStatus {
  queued,
  running,
  completed,
  failed,
  canceled,
}