import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  final SpeechToText _speechToText = SpeechToText();

  static bool isQuietSpeechErrorMessage(String message) {
    final normalized = message.toLowerCase().trim();
    return normalized.contains('error_') ||
        normalized.startsWith('error ') ||
        normalized.contains('busy') ||
        normalized.contains('error_no_match') ||
        normalized.contains('error_no_mach') ||
        normalized.contains('error_speech_timeout') ||
        normalized.contains('error_client') ||
        normalized.contains('error_busy') ||
        normalized.contains('no_match') ||
        normalized.contains('speech_timeout') ||
        normalized.contains('client');
  }

  bool get isListening => _speechToText.isListening;

  Future<bool> initialize({
    ValueChanged<String>? onError,
    ValueChanged<String>? onStatusChanged,
  }) async {
    return _speechToText.initialize(
      onError: (error) {
        final message = error.errorMsg;
        if (isQuietSpeechErrorMessage(message)) {
          return;
        }

        onError?.call(message);
      },
      onStatus: (status) => onStatusChanged?.call(status),
    );
  }

  Future<bool> startListening({
    required void Function(String recognizedText, bool isFinal) onResult,
    ValueChanged<String>? onError,
    ListenMode listenMode = ListenMode.dictation,
    bool partialResults = true,
    Duration? pauseFor,
    Duration? listenFor,
    String? localeId,
    bool cancelOnError = true,
  }) async {
    if (_speechToText.isListening) {
      return true;
    }

    try {
      await _speechToText.listen(
        pauseFor: pauseFor,
        listenFor: listenFor,
        localeId: localeId,
        listenOptions: SpeechListenOptions(
          listenMode: listenMode,
          partialResults: partialResults,
          cancelOnError: cancelOnError,
        ),
        onResult: (SpeechRecognitionResult result) {
          onResult(result.recognizedWords, result.finalResult);
        },
      );

      return _speechToText.isListening;
    } catch (error) {
      final message = error.toString();
      if (!isQuietSpeechErrorMessage(message)) {
        onError?.call(message);
      }
      return false;
    }
  }

  Future<void> stopListening() async {
    if (_speechToText.isListening) {
      await _speechToText.stop();
    }
  }

  Future<void> cancelListening() async {
    if (_speechToText.isListening) {
      await _speechToText.cancel();
    }
  }
}
