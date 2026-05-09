import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as path;
import 'package:reins/Constants/constants.dart';
import 'package:reins/Models/document_attachment.dart';
import 'package:uuid/uuid.dart';

class OllamaMessage {
  /// The unique identifier of the message.
  String id;

  /// The text content of the message.
  String content;

  /// Extra context sent to the model but not shown or stored as visible chat text.
  String? hiddenContext;

  /// The image content of the message.
  List<File>? images;

  /// Document attachments shown in the chat bubble.
  List<DocumentAttachment>? documents;

  /// The date and time the message was created.
  DateTime createdAt;

  /// The role of the message.
  OllamaMessageRole role;

  /// The model used to generate the message.
  String? model;

  /// Optional reasoning trace emitted by thinking-capable models.
  String? thinking;

  /// Whether this assistant message used web search context before answering.
  bool usedWebSearch;

  /// Milliseconds from request start to the first non-empty assistant text chunk.
  int? firstContentLatencyMs;

  /// Internal route used for this answer, shown with latency for diagnostics.
  String? responseRoute;

  // Metadata fields
  bool? done;
  String? doneReason;
  List<int>? context;
  int? totalDuration;
  int? loadDuration;
  int? promptEvalCount;
  int? promptEvalDuration;
  int? evalCount;
  int? evalDuration;

  StringBuffer? _contentStreamBuffer;
  StringBuffer? _thinkingStreamBuffer;

  OllamaMessage(
    this.content, {
    String? id,
    required this.role,
    this.hiddenContext,
    this.images,
    this.documents,
    DateTime? createdAt,
    this.model,
    this.thinking,
    this.usedWebSearch = false,
    this.firstContentLatencyMs,
    this.responseRoute,
    this.done,
    this.doneReason,
    this.context,
    this.totalDuration,
    this.loadDuration,
    this.promptEvalCount,
    this.promptEvalDuration,
    this.evalCount,
    this.evalDuration,
  })  : id = id ?? Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  factory OllamaMessage.fromJson(Map<String, dynamic> json) => OllamaMessage(
        _parseContent(json),
        role: json["message"] != null
            ? OllamaMessageRole.fromString(json["message"]["role"])
            : OllamaMessageRole.assistant, // For generated messages (default)
        images: null,
        createdAt: DateTime.parse(json["created_at"]),
        model: json["model"],
        thinking: _parseThinking(json),
        usedWebSearch: json["used_web_search"] == true,
        firstContentLatencyMs: json["first_content_latency_ms"],
        responseRoute: json["response_route"],
        // Metadata fields
        done: json["done"],
        doneReason: json["done_reason"],
        context: json["context"] != null ? List<int>.from(json["context"].map((x) => x)) : null,
        totalDuration: json["total_duration"],
        loadDuration: json["load_duration"],
        promptEvalCount: json["prompt_eval_count"],
        promptEvalDuration: json["prompt_eval_duration"],
        evalCount: json["eval_count"],
        evalDuration: json["eval_duration"],
      );

  factory OllamaMessage.fromDatabase(Map<String, dynamic> map) {
    final parsed = _extractThinkingFromStoredContent(map['content']);

    return OllamaMessage(
      parsed.content,
      id: map['message_id'],
      role: OllamaMessageRole.fromString(map['role']),
      images: _constructImages(map['images']),
      documents: parsed.documents,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      model: map['model'],
      thinking: parsed.thinking,
      usedWebSearch: parsed.usedWebSearch,
      firstContentLatencyMs: parsed.firstContentLatencyMs,
      responseRoute: parsed.responseRoute,
    );
  }

  Future<Map<String, dynamic>> toJson() async => {
        "model": model,
        "created_at": createdAt.toIso8601String(),
        "message": {
          "role": role.name,
          "content": content,
          "thinking": thinking,
          "images": await _base64EncodeImages(),
        },
        "done": done,
        "done_reason": doneReason,
        "context": context == null ? null : List<dynamic>.from(context!.map((x) => x)),
        "total_duration": totalDuration,
        "load_duration": loadDuration,
        "prompt_eval_count": promptEvalCount,
        "prompt_eval_duration": promptEvalDuration,
        "eval_count": evalCount,
        "eval_duration": evalDuration,
      };

  Future<Map<String, dynamic>> toChatJson() async => {
        "role": role.name,
        "content": _composeModelContent(),
        if (thinking != null && thinking!.isNotEmpty) "thinking": thinking,
        "images": await _base64EncodeImages(),
      };

  Map<String, dynamic> toDatabaseMap() => {
        'message_id': id,
        'content': _composeStoredContent(
          content,
          thinking,
          usedWebSearch,
          firstContentLatencyMs,
          responseRoute,
          documents,
        ),
        'images': _breakImages(images),
        'role': role.name,
        'timestamp': createdAt.millisecondsSinceEpoch,
      };

  void updateMetadataFrom(OllamaMessage message) {
    usedWebSearch = usedWebSearch || message.usedWebSearch;
    firstContentLatencyMs ??= message.firstContentLatencyMs;
    responseRoute ??= message.responseRoute;
    done = message.done;
    doneReason = message.doneReason;
    context = message.context;
    totalDuration = message.totalDuration;
    loadDuration = message.loadDuration;
    promptEvalCount = message.promptEvalCount;
    promptEvalDuration = message.promptEvalDuration;
    evalCount = message.evalCount;
    evalDuration = message.evalDuration;
  }

  String _composeModelContent() {
    final hidden = hiddenContext?.trim();
    if (hidden == null || hidden.isEmpty) return content;
    if (content.trim().isEmpty) return hidden;
    return '$content\n\n$hidden';
  }

  void appendStreamChunk(OllamaMessage message) {
    if (message.thinking != null && message.thinking!.isNotEmpty) {
      final buffer = _thinkingStreamBuffer ??= StringBuffer(thinking ?? '');
      buffer.write(message.thinking);
      thinking = buffer.toString();
    }

    if (message.content.isNotEmpty) {
      final buffer = _contentStreamBuffer ??= StringBuffer(content);
      buffer.write(message.content);
      content = buffer.toString();
    }

    updateMetadataFrom(message);
  }

  Future<List<String>?> _base64EncodeImages() async {
    if (images != null) {
      return await Future.wait(images!.map(
        (file) => Isolate.run(() => _base64EncodeImageFile(file.path)),
      ));
    }

    return null;
  }

  static List<File>? _constructImages(String? raw) {
    if (raw != null) {
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded.map((imageRelativePath) {
        return File(path.join(
          PathManager.instance.documentsDirectory.path,
          imageRelativePath,
        ));
      }).toList();
    }

    return null;
  }

  String? _breakImages(List<File>? images) {
    if (images != null) {
      final relativePathImages = images.map((file) {
        return path.relative(
          file.path,
          from: PathManager.instance.documentsDirectory.path,
        );
      }).toList();

      return jsonEncode(relativePathImages);
    }

    return null;
  }

  static String _parseContent(Map<String, dynamic> json) {
    final chatMessage = json['message'];
    if (chatMessage is Map<String, dynamic>) {
      return chatMessage['content'] as String? ?? '';
    }

    return json['response'] as String? ?? '';
  }

  static String? _parseThinking(Map<String, dynamic> json) {
    final chatMessage = json['message'];
    if (chatMessage is Map<String, dynamic>) {
      return chatMessage['thinking'] as String?;
    }

    return json['thinking'] as String?;
  }

  static _StoredMessageParts _extractThinkingFromStoredContent(String rawContent) {
    const webSearchMarker = '<!-- reins:web_search -->';
    final firstContentLatencyPattern = RegExp(r'^<!-- reins:first_content_ms=(\d+) -->\s*');
    final responseRoutePattern = RegExp(r'^<!-- reins:route=([a-z_]+) -->\s*');
    final documentsPattern = RegExp(r'^<!-- reins:documents=([A-Za-z0-9_-]+) -->\s*');
    var contentWithoutMarker = rawContent.trimLeft();
    var usedWebSearch = false;
    int? firstContentLatencyMs;
    String? responseRoute;
    List<DocumentAttachment>? documents;

    var consumedMarker = true;
    while (consumedMarker) {
      consumedMarker = false;

      if (contentWithoutMarker.startsWith(webSearchMarker)) {
        usedWebSearch = true;
        contentWithoutMarker = contentWithoutMarker.substring(webSearchMarker.length).trimLeft();
        consumedMarker = true;
      }

      final latencyMatch = firstContentLatencyPattern.firstMatch(contentWithoutMarker);
      if (latencyMatch != null) {
        firstContentLatencyMs = int.tryParse(latencyMatch.group(1) ?? '');
        contentWithoutMarker = contentWithoutMarker.substring(latencyMatch.end).trimLeft();
        consumedMarker = true;
      }

      final routeMatch = responseRoutePattern.firstMatch(contentWithoutMarker);
      if (routeMatch != null) {
        responseRoute = routeMatch.group(1);
        contentWithoutMarker = contentWithoutMarker.substring(routeMatch.end).trimLeft();
        consumedMarker = true;
      }

      final documentsMatch = documentsPattern.firstMatch(contentWithoutMarker);
      if (documentsMatch != null) {
        documents = _decodeStoredDocuments(documentsMatch.group(1) ?? '');
        contentWithoutMarker = contentWithoutMarker.substring(documentsMatch.end).trimLeft();
        consumedMarker = true;
      }
    }

    final match =
        RegExp(r'^\s*<think>\s*\n?(.*?)\n?\s*</think>\s*\n?(.*)$', dotAll: true).firstMatch(contentWithoutMarker);

    if (match == null) {
      return _StoredMessageParts(
        content: contentWithoutMarker,
        thinking: null,
        usedWebSearch: usedWebSearch,
        firstContentLatencyMs: firstContentLatencyMs,
        responseRoute: responseRoute,
        documents: documents,
      );
    }

    return _StoredMessageParts(
      content: (match.group(2) ?? '').trimLeft(),
      thinking: (match.group(1) ?? '').trim(),
      usedWebSearch: usedWebSearch,
      firstContentLatencyMs: firstContentLatencyMs,
      responseRoute: responseRoute,
      documents: documents,
    );
  }

  static String _composeStoredContent(
    String content,
    String? thinking,
    bool usedWebSearch,
    int? firstContentLatencyMs,
    String? responseRoute,
    List<DocumentAttachment>? documents,
  ) {
    const webSearchMarker = '<!-- reins:web_search -->';
    final markers = [
      if (usedWebSearch) webSearchMarker,
      if (firstContentLatencyMs != null) '<!-- reins:first_content_ms=$firstContentLatencyMs -->',
      if (responseRoute != null && responseRoute.trim().isNotEmpty) '<!-- reins:route=${responseRoute.trim()} -->',
      if (documents != null && documents.isNotEmpty) '<!-- reins:documents=${_encodeStoredDocuments(documents)} -->',
    ];
    final marker = markers.isEmpty ? '' : '${markers.join('\n')}\n';

    if (thinking == null || thinking.trim().isEmpty) {
      return '$marker$content';
    }

    if (content.trim().isEmpty) {
      return '$marker<think>\n${thinking.trim()}\n</think>';
    }

    return '$marker<think>\n${thinking.trim()}\n</think>\n$content';
  }

  static String _encodeStoredDocuments(List<DocumentAttachment> documents) {
    final previewDocuments = documents.map((document) => document.toStoredPreview().toJson()).toList();
    return base64Url.encode(utf8.encode(jsonEncode(previewDocuments))).replaceAll('=', '');
  }

  static List<DocumentAttachment>? _decodeStoredDocuments(String encoded) {
    if (encoded.isEmpty) return null;

    try {
      final padded = encoded.padRight(encoded.length + ((4 - encoded.length % 4) % 4), '=');
      final decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
      if (decoded is! List) return null;

      return decoded
          .whereType<Map>()
          .map((item) => DocumentAttachment.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return null;
    }
  }
}

String _base64EncodeImageFile(String filePath) {
  return base64Encode(File(filePath).readAsBytesSync());
}

class _StoredMessageParts {
  final String content;
  final String? thinking;
  final bool usedWebSearch;
  final int? firstContentLatencyMs;
  final String? responseRoute;
  final List<DocumentAttachment>? documents;

  const _StoredMessageParts({
    required this.content,
    required this.thinking,
    required this.usedWebSearch,
    required this.firstContentLatencyMs,
    required this.responseRoute,
    required this.documents,
  });
}

enum OllamaMessageRole {
  user,
  assistant,
  system;

  factory OllamaMessageRole.fromString(String role) {
    switch (role) {
      case 'user':
        return OllamaMessageRole.user;
      case 'assistant':
        return OllamaMessageRole.assistant;
      case 'system':
        return OllamaMessageRole.system;
      default:
        throw ArgumentError('Unknown role: $role');
    }
  }
}
