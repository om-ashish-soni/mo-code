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

  /// Structured data for diff and todo line types.
  final DiffFile? diffData;
  final List<TodoItem>? todoItems;

  TerminalLine({
    required this.type,
    this.content = '',
    DateTime? timestamp,
    this.diffData,
    this.todoItems,
  }) : timestamp = timestamp ?? DateTime.now();
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
  diff,
  todo,
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

// ---------------------------------------------------------------------------
// Diff models (mirrors backend DiffHunk / DiffHunkLine)
// ---------------------------------------------------------------------------

class DiffHunkLine {
  final DiffLineType type;
  final String content;

  const DiffHunkLine({required this.type, required this.content});

  factory DiffHunkLine.fromJson(Map<String, dynamic> json) {
    return DiffHunkLine(
      type: DiffLineType.fromString(json['type'] as String? ?? 'context'),
      content: json['content'] as String? ?? '',
    );
  }
}

enum DiffLineType {
  context,
  added,
  removed;

  static DiffLineType fromString(String s) {
    switch (s) {
      case 'added':
        return DiffLineType.added;
      case 'removed':
        return DiffLineType.removed;
      default:
        return DiffLineType.context;
    }
  }
}

class DiffHunk {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final List<DiffHunkLine> lines;

  const DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
  });

  factory DiffHunk.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'] as List<dynamic>? ?? [];
    return DiffHunk(
      oldStart: json['old_start'] as int? ?? 0,
      oldCount: json['old_count'] as int? ?? 0,
      newStart: json['new_start'] as int? ?? 0,
      newCount: json['new_count'] as int? ?? 0,
      lines: rawLines
          .map((l) => DiffHunkLine.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }
}

class DiffFile {
  final String path;
  final List<DiffHunk> hunks;

  const DiffFile({required this.path, required this.hunks});

  factory DiffFile.fromJson(Map<String, dynamic> json) {
    final rawHunks = json['hunks'] as List<dynamic>? ?? [];
    return DiffFile(
      path: json['file'] as String? ?? json['path'] as String? ?? '',
      hunks: rawHunks
          .map((h) => DiffHunk.fromJson(h as Map<String, dynamic>))
          .toList(),
    );
  }

  int get additions =>
      hunks.fold(0, (sum, h) => sum + h.lines.where((l) => l.type == DiffLineType.added).length);
  int get deletions =>
      hunks.fold(0, (sum, h) => sum + h.lines.where((l) => l.type == DiffLineType.removed).length);
}

// ---------------------------------------------------------------------------
// TODO item model (for TodoWrite / TODO panel)
// ---------------------------------------------------------------------------

class TodoItem {
  final String id;
  final String content;
  final TodoStatus status;

  const TodoItem({
    required this.id,
    required this.content,
    required this.status,
  });

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      status: TodoStatus.fromString(json['status'] as String? ?? 'pending'),
    );
  }

  TodoItem copyWith({String? content, TodoStatus? status}) {
    return TodoItem(
      id: id,
      content: content ?? this.content,
      status: status ?? this.status,
    );
  }
}

enum TodoStatus {
  pending,
  inProgress,
  completed;

  static TodoStatus fromString(String s) {
    switch (s) {
      case 'in_progress':
        return TodoStatus.inProgress;
      case 'completed':
        return TodoStatus.completed;
      default:
        return TodoStatus.pending;
    }
  }
}