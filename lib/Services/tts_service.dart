import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'offline_ai_tts_service.dart';

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
  static const modeSettingKey = 'ttsMode';
  static const offlineVoiceSettingKey = 'offlineAiVoice';
  static const speechRateSettingKey = 'ttsSpeechRate';
  static const voicePitchSettingKey = 'ttsVoicePitch';
  static const systemMode = 'system';
  static const offlineAiMode = 'offlineAi';

  final FlutterTts _flutterTts = FlutterTts();
  final OfflineAiTtsService _offlineAiTtsService;

  bool _isInitialized = false;
  Completer<void>? _activeSpeechCompleter;

  TtsService(this._offlineAiTtsService);

  List<OfflineAiVoice> get offlineAiVoices => OfflineAiTtsService.voices;

  String get currentMode => Hive.box('settings').get(modeSettingKey, defaultValue: systemMode) as String;

  double get currentSpeechRate => _settingDouble(speechRateSettingKey, defaultValue: 1.0).clamp(0.75, 1.3).toDouble();

  double get currentVoicePitch => _settingDouble(voicePitchSettingKey, defaultValue: 1.0).clamp(0.85, 1.15).toDouble();

  String get currentOfflineVoiceId => Hive.box('settings').get(
        offlineVoiceSettingKey,
        defaultValue: OfflineAiTtsService.defaultVoiceId,
      ) as String;

  Future<void> setMode(String value) async {
    final normalized = value == offlineAiMode ? offlineAiMode : systemMode;
    await Hive.box('settings').put(modeSettingKey, normalized);
  }

  Future<void> setOfflineVoice(String voiceId) async {
    final voice = _offlineAiTtsService.voiceById(voiceId);
    await Hive.box('settings').put(offlineVoiceSettingKey, voice.id);
  }

  Future<void> setSpeechRate(double value) async {
    await Hive.box('settings').put(speechRateSettingKey, value.clamp(0.75, 1.3).toDouble());
    if (_isInitialized) {
      await _applyVoiceTuning();
    }
  }

  Future<void> setVoicePitch(double value) async {
    await Hive.box('settings').put(voicePitchSettingKey, value.clamp(0.85, 1.15).toDouble());
    if (_isInitialized) {
      await _applyVoiceTuning();
    }
  }

  Future<bool> isOfflineVoiceDownloaded([String? voiceId]) {
    return _offlineAiTtsService.isVoiceDownloaded(voiceId ?? currentOfflineVoiceId);
  }

  Future<void> downloadOfflineVoice(
    String? voiceId, {
    void Function(OfflineAiTtsDownloadProgress progress)? onProgress,
  }) {
    return _offlineAiTtsService.downloadVoice(
      voiceId ?? currentOfflineVoiceId,
      onProgress: onProgress,
    );
  }

  Future<void> deleteOfflineVoice([String? voiceId]) {
    return _offlineAiTtsService.deleteVoice(voiceId ?? currentOfflineVoiceId);
  }

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
      await _applyVoiceTuning();

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

    if (currentMode == offlineAiMode) {
      await _flutterTts.stop();
      _completeActiveSpeech();
      await _offlineAiTtsService.speak(
        normalizedText,
        voiceId: currentOfflineVoiceId,
        speed: currentSpeechRate,
      );
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
    await _offlineAiTtsService.stop();
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

  Future<void> _applyVoiceTuning() async {
    await _flutterTts.setSpeechRate((0.45 * currentSpeechRate).clamp(0.25, 0.75).toDouble());
    await _flutterTts.setPitch(currentVoicePitch);
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

  double _settingDouble(String key, {required double defaultValue}) {
    final raw = Hive.box('settings').get(key, defaultValue: defaultValue);
    if (raw is num) {
      return raw.toDouble();
    }

    return double.tryParse(raw.toString()) ?? defaultValue;
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
