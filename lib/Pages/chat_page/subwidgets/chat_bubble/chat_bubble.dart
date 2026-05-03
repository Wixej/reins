import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:reins/Extensions/markdown_stylesheet_extension.dart';
import 'package:reins/Models/ollama_message.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'chat_bubble_actions.dart';
import 'chat_bubble_image.dart';
import 'chat_bubble_document.dart';
import 'chat_bubble_menu.dart';
import 'chat_bubble_think_block.dart';

class ChatBubble extends StatelessWidget {
  final OllamaMessage message;

  const ChatBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final actions = ChatBubbleActions(message);

    return ChatBubbleMenu(
      menuChildren: [
        MenuItemButton(
          onPressed: actions.handleCopy,
          leadingIcon: Icon(Icons.copy_outlined),
          child: const Text('Copy'),
        ),
        MenuItemButton(
          onPressed: () => actions.handleSelectText(context),
          leadingIcon: Icon(Icons.select_all_outlined),
          child: const Text('Select Text'),
        ),
        MenuItemButton(
          onPressed: () => actions.handleRegenerate(context),
          leadingIcon: Icon(Icons.refresh_outlined),
          child: const Text('Regenerate'),
        ),
        Divider(),
        MenuItemButton(
          onPressed: () => actions.handleEdit(context),
          closeOnActivate: false,
          leadingIcon: Icon(Icons.edit_outlined),
          child: const Text('Edit'),
        ),
        MenuItemButton(
          onPressed: () => actions.handleDelete(context),
          leadingIcon: Icon(Icons.delete_outline),
          child: const Text('Delete'),
        ),
      ],
      child: _ChatBubbleBody(message: message),
    );
  }
}

class _ChatBubbleBody extends StatelessWidget {
  final OllamaMessage message;

  const _ChatBubbleBody({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25.0, vertical: 15.0),
      child: Column(
        spacing: 8,
        crossAxisAlignment: bubbleAlignment,
        children: [
          // If the message has an image attachment, display it
          if (message.images != null && message.images!.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: message.images!.map((imageFile) => ChatBubbleImage(imageFile: imageFile)).toList(),
            ),
          if (message.documents != null && message.documents!.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: message.documents!.map((document) => ChatBubbleDocument(document: document)).toList(),
            ),
          if (message.thinking != null && message.thinking!.trim().isNotEmpty)
            ThinkBlockWidget(content: message.thinking!.trim()),
          if (!isSentFromUser && (message.usedWebSearch || message.firstContentLatencyMs != null))
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _ResponseInfoIndicator(
                  latencyMs: message.firstContentLatencyMs,
                  usedWebSearch: message.usedWebSearch,
                ),
              ],
            ),
          Container(
            padding: isSentFromUser ? const EdgeInsets.all(10.0) : null,
            constraints: BoxConstraints(
              maxWidth: isSentFromUser ? MediaQuery.of(context).size.width * 0.8 : double.infinity,
            ),
            decoration: BoxDecoration(
              color: isSentFromUser
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: message.content.trim().isEmpty
                ? const SizedBox.shrink()
                : MarkdownBody(
                    data: message.content,
                    selectable: true,
                    softLineBreak: true,
                    styleSheet: context.markdownStyleSheet.copyWith(
                      code: GoogleFonts.sourceCodePro(),
                    ),
                    builders: {'think': ThinkBlockBuilder()},
                    extensionSet: md.ExtensionSet(
                      <md.BlockSyntax>[ThinkBlockSyntax(), ...md.ExtensionSet.gitHubFlavored.blockSyntaxes],
                      <md.InlineSyntax>[md.EmojiSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
                    ),
                    onTapLink: (text, href, title) {
                      if (href != null && href.isNotEmpty) {
                        launchUrlString(href);
                      }
                    },
                  ),
          ),
          Text(
            TimeOfDay.fromDateTime(message.createdAt.toLocal()).format(context),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Returns true if the message is sent from the user.
  bool get isSentFromUser => message.role == OllamaMessageRole.user;

  /// Returns the alignment of the bubble.
  ///
  /// If the message is sent from the user, the alignment is [Alignment.centerRight].
  /// Otherwise, the alignment is [Alignment.centerLeft].
  CrossAxisAlignment get bubbleAlignment => isSentFromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
}

class _ResponseInfoIndicator extends StatelessWidget {
  final int? latencyMs;
  final bool usedWebSearch;

  const _ResponseInfoIndicator({
    this.latencyMs,
    required this.usedWebSearch,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.speed_rounded,
              size: 15,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              _label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  String get _label {
    final parts = <String>[];

    if (latencyMs != null) {
      parts.add('Первый текст через ${_formatLatency(latencyMs!)}');
    } else if (usedWebSearch) {
      parts.add('Поиск в интернете выполнен');
    }

    if (usedWebSearch) parts.add('интернет');
    return parts.where((part) => part.isNotEmpty).join(' · ');
  }

  String _formatLatency(int milliseconds) {
    if (milliseconds < 1000) {
      return '$milliseconds мс';
    }

    final seconds = milliseconds / 1000;
    return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)} с';
  }
}
