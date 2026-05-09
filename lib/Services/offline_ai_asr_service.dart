import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class OfflineAiAsrModel {
  final String id;
  final String label;
  final String description;
  final String archiveUrl;
  final String archiveRoot;
  final String modelFileName;

  const OfflineAiAsrModel({
    required this.id,
    required this.label,
    required this.description,
    required this.archiveUrl,
    required this.archiveRoot,
    required this.modelFileName,
  });
}

class OfflineAiAsrDownloadProgress {
  final double value;
  final String label;

  const OfflineAiAsrDownloadProgress({
    required this.value,
    required this.label,
  });
}

class OfflineAiAsrService {
  static const modeSettingKey = 'speechRecognitionMode';
  static const systemMode = 'system';
  static const offlineAiMode = 'offline_ai';
  static const defaultModelId = 't-one-ru';

  static const models = <OfflineAiAsrModel>[
    OfflineAiAsrModel(
      id: defaultModelId,
      label: 'AI-распознавание RU',
      description:
          'Русская потоковая модель T-One CTC. Работает офлайн после скачивания, лучше контролирует паузы, но без полноценной пунктуации.',
      archiveUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-t-one-russian-2025-09-08.tar.bz2',
      archiveRoot: 'sherpa-onnx-streaming-t-one-russian-2025-09-08',
      modelFileName: 'model.onnx',
    ),
  ];

  static const sampleRate = 16000;
  static const _silenceRmsThreshold = 0.012;
  static const _minSpeechDuration = Duration(milliseconds: 250);

  final AudioRecorder _recorder = AudioRecorder();

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  StreamSubscription<Uint8List>? _audioSubscription;
  Timer? _maxListenTimer;
  Timer? _silenceTimer;
  bool _bindingsInitialized = false;
  bool _isListening = false;
  bool _hasSpeech = false;
  DateTime? _firstVoiceAt;
  DateTime? _lastVoiceAt;
  String _lastPartialText = '';

  bool get isListening => _isListening;

  OfflineAiAsrModel modelById(String? id) {
    return models.firstWhere(
      (model) => model.id == id,
      orElse: () => models.first,
    );
  }

  Future<bool> isModelDownloaded(String? modelId) async {
    final model = modelById(modelId);
    final modelFile = File(await _modelPath(model));
    final tokensFile = File(await _tokensPath(model));
    return modelFile.existsSync() && tokensFile.existsSync();
  }

  Future<void> downloadModel(
    String? modelId, {
    void Function(OfflineAiAsrDownloadProgress progress)? onProgress,
  }) async {
    final model = modelById(modelId);
    final baseDir = await _baseDir();
    final modelDir = Directory(p.join(baseDir.path, model.id));
    final tempDir = Directory(p.join(baseDir.path, '${model.id}.download'));
    final archiveFile = File(p.join(baseDir.path, '${model.id}.tar.bz2'));

    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
    await tempDir.create(recursive: true);

    try {
      onProgress?.call(
        const OfflineAiAsrDownloadProgress(value: 0, label: 'Скачивание модели распознавания...'),
      );
      await _downloadArchive(model.archiveUrl, archiveFile, onProgress);

      onProgress?.call(
        const OfflineAiAsrDownloadProgress(value: 0.78, label: 'Распаковка модели...'),
      );
      await _extractArchive(archiveFile, tempDir, model.archiveRoot);

      if (modelDir.existsSync()) {
        await modelDir.delete(recursive: true);
      }
      await tempDir.rename(modelDir.path);
      await archiveFile.delete().catchError((_) => archiveFile);
      _freeRecognizer();

      onProgress?.call(
        const OfflineAiAsrDownloadProgress(value: 1, label: 'Модель распознавания готова.'),
      );
    } catch (_) {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> deleteModel(String? modelId) async {
    final model = modelById(modelId);
    await cancelListening();
    _freeRecognizer();

    final dir = Directory(await _modelDirPath(model));
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  Future<bool> startListening({
    required void Function(String recognizedText, bool isFinal) onResult,
    void Function(String message)? onError,
    void Function(String status)? onStatusChanged,
    Duration pauseFor = const Duration(seconds: 7),
    Duration listenFor = const Duration(seconds: 120),
    String? modelId,
  }) async {
    if (_isListening) return true;

    final model = modelById(modelId);
    if (!await isModelDownloaded(model.id)) {
      onError?.call('Сначала скачайте офлайн AI-модель распознавания.');
      return false;
    }

    try {
      _ensureBindingsInitialized();
      final recognizer = await _loadRecognizer(model);
      final stream = recognizer.createStream();
      _stream = stream;
      _isListening = true;
      _hasSpeech = false;
      _firstVoiceAt = null;
      _lastVoiceAt = null;
      _lastPartialText = '';

      final audioStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
          streamBufferSize: 1600,
        ),
      );

      onStatusChanged?.call('listening');

      _audioSubscription = audioStream.listen(
        (chunk) {
          _handleAudioChunk(
            chunk,
            recognizer,
            stream,
            pauseFor,
            onResult,
            onStatusChanged,
          );
        },
        onError: (error) {
          onError?.call(error.toString());
          unawaited(cancelListening());
        },
        onDone: () => onStatusChanged?.call('notListening'),
        cancelOnError: false,
      );

      _maxListenTimer = Timer(listenFor, () {
        unawaited(_finishListening(onResult, onStatusChanged));
      });

      return true;
    } catch (error) {
      await cancelListening();
      onError?.call(error.toString());
      return false;
    }
  }

  Future<void> stopListening() async {
    if (!_isListening) return;
    await _finishListening((_, __) {}, (_) {});
  }

  Future<void> cancelListening() async {
    _maxListenTimer?.cancel();
    _silenceTimer?.cancel();
    _maxListenTimer = null;
    _silenceTimer = null;

    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder.cancel().catchError((_) {});

    _stream?.free();
    _stream = null;
    _isListening = false;
  }

  Future<void> dispose() async {
    await cancelListening();
    _freeRecognizer();
    await _recorder.dispose();
  }

  void _handleAudioChunk(
    Uint8List chunk,
    sherpa.OnlineRecognizer recognizer,
    sherpa.OnlineStream stream,
    Duration pauseFor,
    void Function(String recognizedText, bool isFinal) onResult,
    void Function(String status)? onStatusChanged,
  ) {
    if (!_isListening || chunk.isEmpty) return;

    final samples = _pcm16ToFloat32(chunk);
    final rms = _rms(samples);
    final now = DateTime.now();

    if (rms >= _silenceRmsThreshold) {
      _firstVoiceAt ??= now;
      _lastVoiceAt = now;

      if (!_hasSpeech && now.difference(_firstVoiceAt!) >= _minSpeechDuration) {
        _hasSpeech = true;
      }
    }

    stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }

    final partialText = _postProcessText(recognizer.getResult(stream).text, finalResult: false);
    if (partialText.isNotEmpty && partialText != _lastPartialText) {
      _lastPartialText = partialText;
      onResult(partialText, false);
    }

    _silenceTimer?.cancel();
    if (_hasSpeech && _lastVoiceAt != null) {
      final silenceLeft = pauseFor - now.difference(_lastVoiceAt!);
      _silenceTimer = Timer(
        silenceLeft.isNegative ? Duration.zero : silenceLeft,
        () => unawaited(_finishListening(onResult, onStatusChanged)),
      );
    }
  }

  Future<void> _finishListening(
    void Function(String recognizedText, bool isFinal) onResult,
    void Function(String status)? onStatusChanged,
  ) async {
    if (!_isListening) return;

    _isListening = false;
    _maxListenTimer?.cancel();
    _silenceTimer?.cancel();
    _maxListenTimer = null;
    _silenceTimer = null;

    final stream = _stream;
    final recognizer = _recognizer;

    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder.stop().catchError((_) => null);

    if (stream != null && recognizer != null) {
      stream.inputFinished();
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }

      final finalText = _postProcessText(recognizer.getResult(stream).text, finalResult: true);
      if (finalText.isNotEmpty) {
        onResult(finalText, true);
      } else {
        onResult(_lastPartialText, true);
      }
      stream.free();
    }

    _stream = null;
    onStatusChanged?.call('done');
  }

  Future<sherpa.OnlineRecognizer> _loadRecognizer(OfflineAiAsrModel model) async {
    if (_recognizer != null) return _recognizer!;

    final recognizer = sherpa.OnlineRecognizer(
      sherpa.OnlineRecognizerConfig(
        feat: const sherpa.FeatureConfig(sampleRate: sampleRate, featureDim: 80),
        model: sherpa.OnlineModelConfig(
          toneCtc: sherpa.OnlineToneCtcModelConfig(model: await _modelPath(model)),
          tokens: await _tokensPath(model),
          numThreads: 2,
          provider: 'cpu',
          debug: false,
          modelType: 't-one-ctc',
        ),
        enableEndpoint: true,
        rule1MinTrailingSilence: 2.8,
        rule2MinTrailingSilence: 1.8,
        rule3MinUtteranceLength: 20,
      ),
    );

    _recognizer = recognizer;
    return recognizer;
  }

  Float32List _pcm16ToFloat32(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    final samples = Float32List(sampleCount);
    final data = ByteData.sublistView(bytes);

    for (var i = 0; i < sampleCount; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }

    return samples;
  }

  double _rms(Float32List samples) {
    if (samples.isEmpty) return 0;
    var sum = 0.0;
    for (final sample in samples) {
      sum += sample * sample;
    }
    return math.sqrt(sum / samples.length);
  }

  String _postProcessText(String text, {required bool finalResult}) {
    var normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return normalized;

    normalized = normalized[0].toUpperCase() + normalized.substring(1);
    if (finalResult && !RegExp(r'[.!?…]$').hasMatch(normalized)) {
      final lower = normalized.toLowerCase();
      final isQuestion = RegExp(r'^(кто|что|где|когда|куда|откуда|почему|зачем|как|какой|какая|какое|какие|можно|надо|нужно|сколько)\b')
          .hasMatch(lower);
      normalized += isQuestion ? '?' : '.';
    }

    return normalized;
  }

  void _ensureBindingsInitialized() {
    if (_bindingsInitialized) return;
    sherpa.initBindings();
    _bindingsInitialized = true;
  }

  void _freeRecognizer() {
    _recognizer?.free();
    _recognizer = null;
  }

  Future<void> _downloadArchive(
    String url,
    File target,
    void Function(OfflineAiAsrDownloadProgress progress)? onProgress,
  ) async {
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    final response = await client.send(request);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      client.close();
      throw HttpException('Не удалось скачать модель распознавания: HTTP ${response.statusCode}');
    }

    final sink = target.openWrite();
    final total = response.contentLength;
    var received = 0;

    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);

        if (total != null && total > 0) {
          final progress = (received / total).clamp(0.0, 1.0);
          onProgress?.call(
            OfflineAiAsrDownloadProgress(
              value: progress * 0.78,
              label: 'Скачивание распознавания ${(progress * 100).round()}%',
            ),
          );
        }
      }
    } finally {
      await sink.close();
      client.close();
    }
  }

  Future<void> _extractArchive(File archiveFile, Directory targetDir, String root) async {
    final compressed = await archiveFile.readAsBytes();
    final tarBytes = BZip2Decoder().decodeBytes(compressed);
    final archive = TarDecoder().decodeBytes(tarBytes);

    for (final file in archive.files) {
      final relativePath = _safeRelativeArchivePath(file.name, root);
      if (relativePath == null || relativePath.isEmpty) continue;

      final outputPath = p.join(targetDir.path, relativePath);
      if (!p.isWithin(targetDir.path, outputPath) && p.normalize(outputPath) != p.normalize(targetDir.path)) {
        continue;
      }

      if (file.isDirectory) {
        await Directory(outputPath).create(recursive: true);
        continue;
      }

      await Directory(p.dirname(outputPath)).create(recursive: true);
      await File(outputPath).writeAsBytes(file.content, flush: true);
    }
  }

  String? _safeRelativeArchivePath(String archivePath, String root) {
    final normalized = p.posix.normalize(archivePath.replaceAll('\\', '/'));
    if (normalized == '.' || normalized.startsWith('../') || normalized.contains('/../')) {
      return null;
    }

    final prefix = '$root/';
    if (normalized == root) return '';
    if (!normalized.startsWith(prefix)) return null;
    return normalized.substring(prefix.length);
  }

  Future<Directory> _baseDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'offline_ai_asr'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> _modelDirPath(OfflineAiAsrModel model) async {
    return p.join((await _baseDir()).path, model.id);
  }

  Future<String> _modelPath(OfflineAiAsrModel model) async {
    return p.join(await _modelDirPath(model), model.modelFileName);
  }

  Future<String> _tokensPath(OfflineAiAsrModel model) async {
    return p.join(await _modelDirPath(model), 'tokens.txt');
  }
}
