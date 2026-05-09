import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Extension on [BuildContext] to provide consistent markdown styling across the app.
extension MarkdownStyleSheetExtension on BuildContext {
  /// Returns a [MarkdownStyleSheet] that matches the app's theme with bodyLarge text size.
  ///
  /// This ensures markdown content uses the same base size as other readable text
  /// in the app, while respecting user accessibility settings up to 2x scale.
  MarkdownStyleSheet get markdownStyleSheet {
    final colorScheme = Theme.of(this).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final textTheme = Theme.of(this).textTheme;
    final bodyStyle = textTheme.bodyLarge?.copyWith(
      color: colorScheme.onSurface,
    );
    final inlineCodeBackground = isDark ? const Color(0xFF252525) : const Color(0xFFE9EEF6);
    final blockBackground = isDark ? const Color(0xFF202020) : const Color(0xFFF2F4F7);
    final blockBorder = isDark ? const Color(0xFF444444) : const Color(0xFFD9DEE8);

    return MarkdownStyleSheet.fromTheme(
      Theme.of(this).copyWith(
        textTheme: Theme.of(this).textTheme.copyWith(
              bodyMedium: bodyStyle,
            ),
      ),
    ).copyWith(
      textScaler: MediaQuery.textScalerOf(this).clamp(
        minScaleFactor: 0.8,
        maxScaleFactor: 2.0,
      ),
      p: bodyStyle,
      blockquote: bodyStyle?.copyWith(
        color: colorScheme.onSurface,
      ),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      blockquoteDecoration: BoxDecoration(
        color: blockBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: colorScheme.primary.withValues(alpha: isDark ? 0.85 : 0.65),
            width: 4,
          ),
          top: BorderSide(color: blockBorder),
          right: BorderSide(color: blockBorder),
          bottom: BorderSide(color: blockBorder),
        ),
      ),
      code: bodyStyle?.copyWith(
        color: colorScheme.onSurface,
        backgroundColor: inlineCodeBackground,
      ),
      codeblockDecoration: BoxDecoration(
        color: blockBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: blockBorder,
        ),
      ),
      codeblockPadding: const EdgeInsets.all(14),
    );
  }
}
