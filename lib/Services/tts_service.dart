import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive_flutter/hive_flutter.dart';

class TtsEngineInfo {
  final String id;
  final String label;
  final bool isDefault;

  const TtsEngineInfo({
    required this.id,
    required this.label,
    this.isDefault = false,
  });
}

class TtsService {
  static const _languageCode = 'ru-RU';
  static const _engineSettingKey = 'ttsEngine';

  final FlutterTts _flutterTts = FlutterTts();

  bool _isInitialized = false;
  Completer<void>? _activeSpeechCompleter;

  Future<void> initialize() async {
    if (!_isInitialized) {
      await _flutterTts.awaitSpeakCompletion(true);
      _flutterTts.setCompletionHandler(_completeActiveSpeech);
      _flutterTts.setCancelHandler(_completeActiveSpeech);
      _flutterTts.setErrorHandler((message) {
        final completer = _activeSpeechCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.completeError(Exception(message));
        }
        _activeSpeechCompleter = null;
      });
      await _flutterTts.setLanguage(_languageCode);
      await _flutterTts.setSpeechRate(0.45);
      await _flutterTts.setPitch(1.0);

      if (Platform.isAndroid) {
        await _flutterTts.setAudioAttributesForNavigation();
      }

      _isInitialized = true;
    }

    await _applySavedEngine();
  }

  Future<List<TtsEngineInfo>> getAvailableEngines() async {
    await initialize();

    if (!Platform.isAndroid) {
      return const [];
    }

    final rawEngines = await _flutterTts.getEngines;
    if (rawEngines is! List) {
      return const [];
    }

    return rawEngines
        .map<TtsEngineInfo?>((engine) {
          if (engine is String) {
            return TtsEngineInfo(id: engine, label: engine);
          }

          if (engine is Map) {
            final id = (engine['name'] ?? engine['engine'] ?? '').toString().trim();
            if (id.isEmpty) {
              return null;
            }

            final label = (engine['label'] ?? engine['displayName'] ?? id).toString().trim();
            final isDefault = engine['default'] == true;

            return TtsEngineInfo(
              id: id,
              label: label.isEmpty ? id : label,
              isDefault: isDefault,
            );
          }

          return null;
        })
        .whereType<TtsEngineInfo>()
        .fold<Map<String, TtsEngineInfo>>({}, (accumulator, engine) {
          accumulator.putIfAbsent(engine.id, () => engine);
          return accumulator;
        })
        .values
        .toList();
  }

  Future<void> setEngine(String? engineId) async {
    await initialize();

    final settingsBox = Hive.box('settings');
    final normalizedEngineId = engineId?.trim();

    if (!Platform.isAndroid) {
      await settingsBox.delete(_engineSettingKey);
      return;
    }

    if (normalizedEngineId == null || normalizedEngineId.isEmpty) {
      TtsEngineInfo? defaultEngine;
      for (final engine in await getAvailableEngines()) {
        if (engine.isDefault) {
          defaultEngine = engine;
          break;
        }
      }

      if (defaultEngine != null) {
        await _flutterTts.setEngine(defaultEngine.id);
      }

      await settingsBox.delete(_engineSettingKey);
      return;
    }

    await _flutterTts.setEngine(normalizedEngineId);
    await settingsBox.put(_engineSettingKey, normalizedEngineId);
  }

  Future<void> speak(String text) async {
    await stop();
    await speakQueued(text);
  }

  Future<void> speakQueued(String text) async {
    final normalizedText = _normalizeForSpeech(text);
    if (normalizedText.isEmpty) {
      return;
    }

    await initialize();
    final speechCompleter = Completer<void>();
    _activeSpeechCompleter = speechCompleter;

    final result = await _flutterTts.speak(normalizedText);
    if (result != 1) {
      _completeActiveSpeech();
    }

    await speechCompleter.future.timeout(
      _speechTimeoutFor(normalizedText),
      onTimeout: () {
        _completeActiveSpeech();
      },
    );
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    _completeActiveSpeech();
  }

  void _completeActiveSpeech() {
    final completer = _activeSpeechCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _activeSpeechCompleter = null;
  }

  Duration _speechTimeoutFor(String text) {
    final seconds = (text.length / 8).ceil().clamp(8, 90);
    return Duration(seconds: seconds);
  }

  Future<void> _applySavedEngine() async {
    if (!Platform.isAndroid) {
      return;
    }

    final savedEngine = Hive.box('settings').get(_engineSettingKey) as String?;
    if (savedEngine == null || savedEngine.trim().isEmpty) {
      return;
    }

    try {
      await _flutterTts.setEngine(savedEngine.trim());
    } catch (_) {
      await Hive.box('settings').delete(_engineSettingKey);
    }
  }

  String _normalizeForSpeech(String text) {
    return text
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'`([^`]+)`'), r'$1')
        .replaceAll(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'), r'$1')
        .replaceAll(
          RegExp(
            r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0E}\u{FE0F}\u{200D}]',
            unicode: true,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[#>*_~-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
