import 'package:reins/Models/ollama_message.dart';

class ChatSearchResult {
  final String messageId;
  final String chatId;
  final String chatTitle;
  final String content;
  final OllamaMessageRole role;
  final DateTime createdAt;

  const ChatSearchResult({
    required this.messageId,
    required this.chatId,
    required this.chatTitle,
    required this.content,
    required this.role,
    required this.createdAt,
  });

  String snippetFor(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    final normalizedContent = content.toLowerCase();
    final index = normalizedQuery.isEmpty ? -1 : normalizedContent.indexOf(normalizedQuery);

    if (index == -1) {
      return _compact(content, 180);
    }

    final start = (index - 70).clamp(0, content.length);
    final end = (index + normalizedQuery.length + 110).clamp(0, content.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < content.length ? '...' : '';

    return '$prefix${_compact(content.substring(start, end), 220)}$suffix';
  }

  String _compact(String value, int maxLength) {
    final compacted = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compacted.length <= maxLength) return compacted;
    return '${compacted.substring(0, maxLength).trim()}...';
  }
}
