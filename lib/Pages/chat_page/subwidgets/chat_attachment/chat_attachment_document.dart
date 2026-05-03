import 'package:flutter/material.dart';
import 'package:reins/Models/document_attachment.dart';

class ChatAttachmentDocument extends StatelessWidget {
  final DocumentAttachment document;
  final ValueChanged<DocumentAttachment> onRemove;

  const ChatAttachmentDocument({
    super.key,
    required this.document,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            _icon,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  document.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${document.extension.toUpperCase()} · ${document.characterCount} симв.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Убрать документ',
            onPressed: () => onRemove(document),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  IconData get _icon {
    return switch (document.extension) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'doc' || 'docx' => Icons.description_outlined,
      _ => Icons.article_outlined,
    };
  }
}
