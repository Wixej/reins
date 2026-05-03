class DocumentAttachment {
  final String name;
  final String extension;
  final String text;

  const DocumentAttachment({
    required this.name,
    required this.extension,
    required this.text,
  });

  int get characterCount => text.length;

  String get preview {
    final compacted = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compacted.length <= 160) return compacted;
    return '${compacted.substring(0, 160).trim()}...';
  }

  DocumentAttachment toStoredPreview() {
    return DocumentAttachment(
      name: name,
      extension: extension,
      text: preview,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'extension': extension,
        'text': text,
      };

  factory DocumentAttachment.fromJson(Map<String, dynamic> json) {
    return DocumentAttachment(
      name: json['name'] as String? ?? 'document',
      extension: json['extension'] as String? ?? '',
      text: json['text'] as String? ?? '',
    );
  }
}
