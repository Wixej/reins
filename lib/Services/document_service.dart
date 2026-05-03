import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:reins/Models/document_attachment.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class DocumentService {
  static const supportedExtensions = ['txt', 'md', 'pdf'];
  static const maxExtractedCharacters = 45000;

  final List<String> _lastSkippedDocuments = [];
  List<String> get lastSkippedDocuments => List.unmodifiable(_lastSkippedDocuments);

  Future<List<DocumentAttachment>> pickDocuments() async {
    _lastSkippedDocuments.clear();

    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
      withData: true,
      withReadStream: true,
    );

    if (result == null) return const [];

    final documents = <DocumentAttachment>[];
    for (final file in result.files) {
      final document = await _extractPlatformFile(file);
      if (document != null) {
        documents.add(document);
      }
    }

    return documents;
  }

  Future<DocumentAttachment?> _extractPlatformFile(PlatformFile file) async {
    final name = file.name.trim().isEmpty ? 'document' : file.name.trim();
    final extension = _extensionFor(file);

    if (!supportedExtensions.contains(extension)) {
      _lastSkippedDocuments.add('$name: unsupported format');
      return null;
    }

    try {
      final bytes = file.bytes ?? await _readPlatformFileBytes(file);
      if (bytes == null || bytes.isEmpty) {
        _lastSkippedDocuments.add('$name: no file content access');
        return null;
      }

      final document = _extractDocumentFromBytes(
        bytes,
        name: name,
        extension: extension,
      );

      if (document == null) {
        _lastSkippedDocuments.add('$name: no readable text found');
      }

      return document;
    } catch (_) {
      _lastSkippedDocuments.add('$name: read error');
      return null;
    }
  }

  String _extensionFor(PlatformFile file) {
    final fromName = path.extension(file.name).replaceFirst('.', '').toLowerCase();
    if (fromName.isNotEmpty) return fromName;

    final pluginExtension = file.extension?.toLowerCase().trim() ?? '';
    if (pluginExtension.isNotEmpty && pluginExtension != file.name.toLowerCase()) {
      return pluginExtension;
    }

    final filePath = file.path;
    if (filePath != null && filePath.isNotEmpty) {
      return path.extension(filePath).replaceFirst('.', '').toLowerCase();
    }

    return '';
  }

  Future<List<int>?> _readPlatformFileBytes(PlatformFile file) async {
    final filePath = file.path;
    if (filePath != null && filePath.isNotEmpty) {
      final localFile = File(filePath);
      if (await localFile.exists()) {
        return localFile.readAsBytes();
      }
    }

    final stream = file.readStream;
    if (stream == null) return null;

    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<DocumentAttachment?> extractDocument(File file) async {
    if (!await file.exists()) return null;

    final name = path.basename(file.path);
    final extension = path.extension(file.path).replaceFirst('.', '').toLowerCase();
    final bytes = await file.readAsBytes();

    return _extractDocumentFromBytes(bytes, name: name, extension: extension);
  }

  DocumentAttachment? _extractDocumentFromBytes(
    List<int> bytes, {
    required String name,
    required String extension,
  }) {
    final text = switch (extension) {
      'txt' || 'md' => _decodePlainText(bytes),
      'pdf' => _extractPdfText(bytes),
      _ => '',
    };

    final normalizedText = _normalizeText(text);
    if (normalizedText.isEmpty) return null;

    return DocumentAttachment(
      name: name,
      extension: extension,
      text: _limitText(normalizedText),
    );
  }

  String buildPromptContext(List<DocumentAttachment> documents) {
    if (documents.isEmpty) return '';

    final buffer = StringBuffer()
      ..writeln('Контекст из прикрепленных документов. Используй его при ответе, если он относится к вопросу.')
      ..writeln('Если в документах нет нужной информации, прямо скажи об этом и не выдумывай.')
      ..writeln();

    for (var i = 0; i < documents.length; i++) {
      final document = documents[i];
      buffer
        ..writeln(
            '[Документ ${i + 1}: ${document.name}, ${document.extension.toUpperCase()}, ${document.characterCount} символов]')
        ..writeln(document.text)
        ..writeln();
    }

    return buffer.toString().trim();
  }

  String _decodePlainText(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  String _extractPdfText(List<int> bytes) {
    final PdfDocument document;
    try {
      document = PdfDocument(inputBytes: bytes);
    } catch (_) {
      return '';
    }

    try {
      return PdfTextExtractor(document).extractText();
    } catch (_) {
      return '';
    } finally {
      document.dispose();
    }
  }

  String _normalizeText(String value) {
    return value
        .replaceAll('\u0000', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _limitText(String value) {
    if (value.length <= maxExtractedCharacters) return value;

    return '${value.substring(0, maxExtractedCharacters).trim()}\n\n[Документ обрезан: текст слишком большой.]';
  }
}
