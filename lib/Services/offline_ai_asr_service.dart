import 'dart:async';
import 'dart:convert';
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
  final String? vadModelUrl;
  final String? vadModelFileName;

  const OfflineAiAsrModel({
    required this.id,
    required this.label,
    required this.description,
    required this.archiveUrl,
    required this.archiveRoot,
    required this.modelFileName,
    this.vadModelUrl,
    this.vadModelFileName,
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

class _OfflineAiAsrDownloadSpec {
  final List<String> urls;
  final String archiveRoot;
  final String modelFileName;
  final List<String> vadUrls;
  final String? vadModelFileName;

  const _OfflineAiAsrDownloadSpec({
    required this.urls,
    required this.archiveRoot,
    required this.modelFileName,
    required this.vadUrls,
    required this.vadModelFileName,
  });
}

class OfflineAiAsrService {
  static const _downloadManifestUrl = 'https://raw.githubusercontent.com/Wixej/reins/main/model_manifest.json';
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
      vadModelUrl: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
      vadModelFileName: 'silero_vad.onnx',
    ),
  ];

  static const sampleRate = 16000;
  static const _silenceRmsThreshold = 0.012;
  static const _minSpeechDuration = Duration(milliseconds: 250);

  final AudioRecorder _recorder = AudioRecorder();

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  sherpa.VoiceActivityDetector? _vad;
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
    if (!modelFile.existsSync() || !tokensFile.existsSync()) {
      return false;
    }

    if (model.vadModelFileName == null || model.vadModelUrl == null) {
      return true;
    }

    return File(await _vadModelPath(model)).existsSync();
  }

  Future<void> downloadModel(
    String? modelId, {
    void Function(OfflineAiAsrDownloadProgress progress)? onProgress,
  }) async {
    final model = modelById(modelId);
    final downloadSpec = await _resolveModelDownloadSpec(model);
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
      await _downloadArchive(downloadSpec.urls, archiveFile, onProgress);

      onProgress?.call(
        const OfflineAiAsrDownloadProgress(value: 0.78, label: 'Распаковка модели...'),
      );
      await _extractArchive(archiveFile, tempDir, downloadSpec.archiveRoot);
      await _normalizeDownloadedModelFiles(tempDir, model, downloadSpec);
      await _downloadVadModel(model, downloadSpec, tempDir, onProgress);

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
    _freeVad();

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
      final vad = await _loadVad(model);
      vad?.reset();
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
    _vad?.reset();
    _isListening = false;
  }

  Future<void> dispose() async {
    await cancelListening();
    _freeRecognizer();
    _freeVad();
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
    final hasVoice = _isVoiceDetected(samples, rms);

    if (hasVoice) {
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
    _vad?.reset();
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
        rule1MinTrailingSilence: 1.5,
        rule2MinTrailingSilence: 1.0,
        rule3MinUtteranceLength: 20,
      ),
    );

    _recognizer = recognizer;
    return recognizer;
  }

  Future<sherpa.VoiceActivityDetector?> _loadVad(OfflineAiAsrModel model) async {
    if (_vad != null) return _vad;
    if (model.vadModelFileName == null || model.vadModelUrl == null) return null;

    final vadPath = await _vadModelPath(model);
    if (!File(vadPath).existsSync()) return null;

    _vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: vadPath,
          threshold: 0.5,
          minSilenceDuration: 0.35,
          minSpeechDuration: 0.18,
          maxSpeechDuration: 12.0,
        ),
        sampleRate: sampleRate,
        numThreads: 1,
        provider: 'cpu',
        debug: false,
      ),
      bufferSizeInSeconds: 10,
    );

    return _vad;
  }

  bool _isVoiceDetected(Float32List samples, double rms) {
    final vad = _vad;
    if (vad == null) {
      return rms >= _silenceRmsThreshold;
    }

    vad.acceptWaveform(samples);
    final detected = vad.isDetected();
    while (!vad.isEmpty()) {
      vad.pop();
    }

    return detected || rms >= _silenceRmsThreshold;
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
      final isQuestion = RegExp(
              r'^(кто|что|где|когда|куда|откуда|почему|зачем|как|какой|какая|какое|какие|можно|надо|нужно|сколько)\b')
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

  void _freeVad() {
    _vad?.free();
    _vad = null;
  }

  Future<_OfflineAiAsrDownloadSpec> _resolveModelDownloadSpec(OfflineAiAsrModel model) async {
    final fallback = _OfflineAiAsrDownloadSpec(
      urls: [model.archiveUrl],
      archiveRoot: model.archiveRoot,
      modelFileName: model.modelFileName,
      vadUrls: [
        if (model.vadModelUrl != null) model.vadModelUrl!,
      ],
      vadModelFileName: model.vadModelFileName,
    );

    try {
      final manifest = await _fetchDownloadManifest();
      final asr = manifest['asr'];
      if (asr is! Map) return fallback;

      final entry = asr[model.id];
      if (entry is! Map) return fallback;

      final urls = _readManifestUrls(entry);
      final archiveRoot = (entry['archiveRoot'] as String?)?.trim();
      final modelFileName = (entry['modelFileName'] as String?)?.trim();
      final vadUrls = _readManifestUrls(entry, urlsKey: 'vadUrls', urlKey: 'vadUrl');
      final vadModelFileName = (entry['vadModelFileName'] as String?)?.trim();

      if (urls.isEmpty ||
          archiveRoot == null ||
          archiveRoot.isEmpty ||
          modelFileName == null ||
          modelFileName.isEmpty) {
        return fallback;
      }

      return _OfflineAiAsrDownloadSpec(
        urls: urls,
        archiveRoot: archiveRoot,
        modelFileName: modelFileName,
        vadUrls: vadUrls.isEmpty ? fallback.vadUrls : vadUrls,
        vadModelFileName: vadModelFileName?.isEmpty == true
            ? fallback.vadModelFileName
            : (vadModelFileName ?? fallback.vadModelFileName),
      );
    } catch (_) {
      return fallback;
    }
  }

  Future<Map<String, Object?>> _fetchDownloadManifest() async {
    final response = await http.get(Uri.parse(_downloadManifestUrl)).timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Manifest HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('Manifest root must be an object');
    }

    return decoded.cast<String, Object?>();
  }

  List<String> _readManifestUrls(
    Map<dynamic, dynamic> entry, {
    String urlsKey = 'urls',
    String urlKey = 'url',
  }) {
    final urls = <String>[];
    final rawUrls = entry[urlsKey];
    if (rawUrls is List) {
      urls.addAll(rawUrls.whereType<String>());
    }

    final rawUrl = entry[urlKey];
    if (rawUrl is String) {
      urls.add(rawUrl);
    }

    return urls
        .map((url) => url.trim())
        .where((url) => url.startsWith('https://') || url.startsWith('http://'))
        .toSet()
        .toList();
  }

  Future<void> _normalizeDownloadedModelFiles(
    Directory tempDir,
    OfflineAiAsrModel model,
    _OfflineAiAsrDownloadSpec downloadSpec,
  ) async {
    if (downloadSpec.modelFileName == model.modelFileName) {
      return;
    }

    final actualModel = File(p.join(tempDir.path, downloadSpec.modelFileName));
    final expectedModel = File(p.join(tempDir.path, model.modelFileName));
    if (!expectedModel.existsSync() && actualModel.existsSync()) {
      await expectedModel.parent.create(recursive: true);
      await actualModel.copy(expectedModel.path);
    }
  }

  Future<void> _downloadVadModel(
    OfflineAiAsrModel model,
    _OfflineAiAsrDownloadSpec downloadSpec,
    Directory targetDir,
    void Function(OfflineAiAsrDownloadProgress progress)? onProgress,
  ) async {
    final fileName = model.vadModelFileName ?? downloadSpec.vadModelFileName;
    if (downloadSpec.vadUrls.isEmpty || fileName == null) return;

    onProgress?.call(
      const OfflineAiAsrDownloadProgress(value: 0.88, label: 'Загрузка VAD-модели...'),
    );

    await _downloadSingleFile(
      downloadSpec.vadUrls,
      File(p.join(targetDir.path, fileName)),
      onProgress: onProgress,
      progressStart: 0.88,
      progressSpan: 0.1,
    );
  }

  Future<void> _downloadArchive(
    List<String> urls,
    File target,
    void Function(OfflineAiAsrDownloadProgress progress)? onProgress,
  ) async {
    Object? lastError;
    for (final url in urls) {
      try {
        if (target.existsSync()) {
          await target.delete();
        }

        await _downloadArchiveFromUrl(url, target, onProgress);
        return;
      } catch (error) {
        lastError = error;
      }
    }

    throw HttpException('Не удалось скачать модель распознавания: $lastError');
  }

  Future<void> _downloadArchiveFromUrl(
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

    await target.parent.create(recursive: true);
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

  Future<void> _downloadSingleFile(
    List<String> urls,
    File target, {
    void Function(OfflineAiAsrDownloadProgress progress)? onProgress,
    double progressStart = 0,
    double progressSpan = 1,
  }) async {
    Object? lastError;
    for (final url in urls) {
      try {
        if (target.existsSync()) {
          await target.delete();
        }

        await _downloadSingleFileFromUrl(
          url,
          target,
          onProgress: onProgress,
          progressStart: progressStart,
          progressSpan: progressSpan,
        );
        return;
      } catch (error) {
        lastError = error;
      }
    }

    throw HttpException('Failed to download file: $lastError');
  }

  Future<void> _downloadSingleFileFromUrl(
    String url,
    File target, {
    void Function(OfflineAiAsrDownloadProgress progress)? onProgress,
    double progressStart = 0,
    double progressSpan = 1,
  }) async {
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    final response = await client.send(request);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      client.close();
      throw HttpException('Failed to download file: HTTP ${response.statusCode}');
    }

    await target.parent.create(recursive: true);
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
              value: progressStart + progress * progressSpan,
              label: 'Загрузка VAD-модели ${(progress * 100).round()}%',
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

  Future<String> _vadModelPath(OfflineAiAsrModel model) async {
    return p.join(await _modelDirPath(model), model.vadModelFileName!);
  }
}
