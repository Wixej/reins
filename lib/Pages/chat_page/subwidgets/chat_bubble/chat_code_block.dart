import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

class ChatCodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent.replaceAll(RegExp(r'\n$'), '');
    final language = _languageFrom(element);

    return ChatCodeBlock(
      code: code,
      language: language,
    );
  }

  String _languageFrom(md.Element element) {
    var className = element.attributes['class'] ?? '';
    for (final child in element.children?.whereType<md.Element>() ?? const <md.Element>[]) {
      final childClass = child.attributes['class'];
      if (childClass != null && childClass.isNotEmpty) {
        className = childClass;
        break;
      }
    }
    final language = className.replaceFirst(RegExp(r'^language-'), '').trim();
    return language.isEmpty ? 'code' : language;
  }
}

class ChatCodeBlock extends StatelessWidget {
  final String code;
  final String language;

  const ChatCodeBlock({
    super.key,
    required this.code,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF2F4F7);
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFD9DEE8);
    final header = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE7EAF0);
    final foreground = isDark ? const Color(0xFFF4F4F4) : const Color(0xFF111827);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: header),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    Icons.code_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      language,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _copyCode(context),
                    icon: const Icon(Icons.copy_rounded, size: 17),
                    label: const Text('Copy'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(14),
            child: RichText(
              textScaler: MediaQuery.textScalerOf(context).clamp(
                minScaleFactor: 0.8,
                maxScaleFactor: 1.6,
              ),
              text: TextSpan(
                style: GoogleFonts.sourceCodePro(
                  color: foreground,
                  fontSize: 14,
                  height: 1.55,
                ),
                children: _highlight(code, isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyCode(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Код скопирован')),
    );
  }

  List<TextSpan> _highlight(String source, bool isDark) {
    final baseColor = isDark ? const Color(0xFFF4F4F4) : const Color(0xFF111827);
    final keywordColor = isDark ? const Color(0xFF8AB4F8) : const Color(0xFF0B57D0);
    final stringColor = isDark ? const Color(0xFFA8DAB5) : const Color(0xFF0B8043);
    final commentColor = isDark ? const Color(0xFF9AA0A6) : const Color(0xFF6B7280);
    final numberColor = isDark ? const Color(0xFFFDD663) : const Color(0xFFB06000);
    final typeColor = isDark ? const Color(0xFFFFB1C8) : const Color(0xFFB3261E);

    final tokenPattern = RegExp(
      r'''(//[^\n]*|/\*[\s\S]*?\*/|#[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\b(?:abstract|as|async|await|break|case|catch|class|const|continue|def|default|defer|do|else|enum|export|extends|false|final|finally|for|from|func|function|get|guard|if|import|in|interface|is|let|match|mut|new|null|override|package|private|protected|public|return|set|static|struct|super|switch|this|throw|throws|trait|true|try|type|val|var|void|while|with|yield)\b|\b(?:String|int|double|num|bool|List|Map|Set|Future|Stream|Widget|State|BuildContext|Object|dynamic)\b|\b\d+(?:\.\d+)?\b)''',
      multiLine: true,
    );

    final spans = <TextSpan>[];
    var index = 0;

    for (final match in tokenPattern.allMatches(source)) {
      if (match.start > index) {
        spans.add(TextSpan(text: source.substring(index, match.start)));
      }

      final token = match.group(0)!;
      final color = token.startsWith('//') || token.startsWith('/*') || token.startsWith('#')
          ? commentColor
          : token.startsWith('"') || token.startsWith("'") || token.startsWith('`')
              ? stringColor
              : RegExp(r'^\d').hasMatch(token)
                  ? numberColor
                  : _isKnownType(token)
                      ? typeColor
                      : keywordColor;

      spans.add(
        TextSpan(
          text: token,
          style: TextStyle(
            color: color,
            fontWeight: _isKnownType(token) ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      );
      index = match.end;
    }

    if (index < source.length) {
      spans.add(TextSpan(text: source.substring(index), style: TextStyle(color: baseColor)));
    }

    return spans;
  }

  bool _isKnownType(String token) {
    return const {
      'String',
      'int',
      'double',
      'num',
      'bool',
      'List',
      'Map',
      'Set',
      'Future',
      'Stream',
      'Widget',
      'State',
      'BuildContext',
      'Object',
      'dynamic',
    }.contains(token);
  }
}
