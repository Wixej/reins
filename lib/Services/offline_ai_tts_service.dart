import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class OfflineAiVoice {
  final String id;
  final String label;
  final String description;
  final String archiveUrl;
  final String archiveRoot;
  final String modelFileName;

  const OfflineAiVoice({
    required this.id,
    required this.label,
    required this.description,
    required this.archiveUrl,
    required this.archiveRoot,
    required this.modelFileName,
  });
}

class OfflineAiTtsDownloadProgress {
  final double value;
  final String label;

  const OfflineAiTtsDownloadProgress({
    required this.value,
    required this.label,
  });
}

class _OfflineAiVoiceDownloadSpec {
  final List<String> urls;
  final String archiveRoot;
  final String modelFileName;

  const _OfflineAiVoiceDownloadSpec({
    required this.urls,
    required this.archiveRoot,
    required this.modelFileName,
  });
}

class OfflineAiTtsService {
  static const _downloadManifestUrl = 'https://raw.githubusercontent.com/Wixej/reins/main/model_manifest.json';
  static const defaultVoiceId = 'irina';

  static const voices = <OfflineAiVoice>[
    OfflineAiVoice(
      id: 'irina',
      label: 'AI-голос Ирина',
      description: 'Женский русский голос, компактная int8-модель около 21 МБ.',
      archiveUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ru_RU-irina-medium-int8.tar.bz2',
      archiveRoot: 'vits-piper-ru_RU-irina-medium-int8',
      modelFileName: 'ru_RU-irina-medium.onnx',
    ),
    OfflineAiVoice(
      id: 'ruslan',
      label: 'AI-голос Руслан',
      description: 'Мужской русский голос, компактная int8-модель около 21 МБ.',
      archiveUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ru_RU-ruslan-medium-int8.tar.bz2',
      archiveRoot: 'vits-piper-ru_RU-ruslan-medium-int8',
      modelFileName: 'ru_RU-ruslan-medium.onnx',
    ),
    OfflineAiVoice(
      id: 'dmitri',
      label: 'AI-голос Дмитрий',
      description: 'Мужской русский голос, компактная int8-модель около 21 МБ.',
      archiveUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ru_RU-dmitri-medium-int8.tar.bz2',
      archiveRoot: 'vits-piper-ru_RU-dmitri-medium-int8',
      modelFileName: 'ru_RU-dmitri-medium.onnx',
    ),
    OfflineAiVoice(
      id: 'denis',
      label: 'AI-голос Денис',
      description: 'Мужской русский голос, компактная int8-модель около 21 МБ.',
      archiveUrl:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ru_RU-denis-medium-int8.tar.bz2',
      archiveRoot: 'vits-piper-ru_RU-denis-medium-int8',
      modelFileName: 'ru_RU-denis-medium.onnx',
    ),
  ];

  final AudioPlayer _audioPlayer = AudioPlayer();

  Isolate? _workerIsolate;
  ReceivePort? _workerReceivePort;
  SendPort? _workerSendPort;
  Completer<SendPort>? _workerStartCompleter;
  final Map<int, Completer<Map<String, Object?>>> _workerRequests = {};
  int _workerRequestId = 0;
  int _speechGenerationSerial = 0;
  bool _bindingsInitialized = false;

  OfflineAiVoice voiceById(String? id) {
    return voices.firstWhere(
      (voice) => voice.id == id,
      orElse: () => voices.first,
    );
  }

  Future<bool> isVoiceDownloaded(String? voiceId) async {
    final voice = voiceById(voiceId);
    final model = File(await _modelPath(voice));
    final tokens = File(await _tokensPath(voice));
    final espeakData = Directory(await _espeakDataPath(voice));
    return model.existsSync() && tokens.existsSync() && espeakData.existsSync();
  }

  Future<void> downloadVoice(
    String? voiceId, {
    void Function(OfflineAiTtsDownloadProgress progress)? onProgress,
  }) async {
    final voice = voiceById(voiceId);
    final downloadSpec = await _resolveVoiceDownloadSpec(voice);
    final baseDir = await _baseDir();
    final voiceDir = Directory(p.join(baseDir.path, voice.id));
    final tempDir = Directory(p.join(baseDir.path, '${voice.id}.download'));
    final archiveFile = File(p.join(baseDir.path, '${voice.id}.tar.bz2'));

    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
    await tempDir.create(recursive: true);

    try {
      onProgress?.call(
        const OfflineAiTtsDownloadProgress(value: 0, label: 'Скачивание голоса...'),
      );
      await _downloadArchive(downloadSpec.urls, archiveFile, onProgress);

      onProgress?.call(
        const OfflineAiTtsDownloadProgress(value: 0.75, label: 'Распаковка модели...'),
      );
      await _extractArchive(archiveFile, tempDir, downloadSpec.archiveRoot);
      await _normalizeDownloadedVoiceFiles(tempDir, voice, downloadSpec);

      if (voiceDir.existsSync()) {
        await voiceDir.delete(recursive: true);
      }
      await tempDir.rename(voiceDir.path);

      await archiveFile.delete().catchError((_) => archiveFile);
      _resetWorker();

      onProgress?.call(
        const OfflineAiTtsDownloadProgress(value: 1, label: 'Голос готов.'),
      );
    } catch (_) {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> deleteVoice(String? voiceId) async {
    final voice = voiceById(voiceId);
    _resetWorker();

    final dir = Directory(await _voiceDirPath(voice));
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> speak(
    String text, {
    String? voiceId,
    double speed = 1.0,
  }) async {
    final voice = voiceById(voiceId);
    if (!await isVoiceDownloaded(voice.id)) {
      throw StateError('Офлайн AI-голос еще не скачан.');
    }

    final generationSerial = ++_speechGenerationSerial;
    await _audioPlayer.stop();
    _ensureBindingsInitialized();

    final output = File(
      p.join(
        (await getTemporaryDirectory()).path,
        'reins_ai_tts_${DateTime.now().microsecondsSinceEpoch}.wav',
      ),
    );

    await _generateAudioInWorker(
      voice: voice,
      text: text,
      speed: speed,
      outputPath: output.path,
    );

    if (generationSerial != _speechGenerationSerial) {
      await output.delete().catchError((_) => output);
      return;
    }

    if (!output.existsSync()) {
      throw StateError('Не удалось создать аудио для офлайн AI-голоса.');
    }

    try {
      await _audioPlayer.play(DeviceFileSource(output.path));
      await _waitUntilPlaybackFinishes(text);
    } finally {
      await output.delete().catchError((_) => output);
    }
  }

  Future<void> stop() async {
    _speechGenerationSerial++;
    await _audioPlayer.stop();
  }

  Future<void> _waitUntilPlaybackFinishes(String text) async {
    final completer = Completer<void>();
    StreamSubscription<void>? completeSubscription;
    Timer? timeoutTimer;

    void finish() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    completeSubscription = _audioPlayer.onPlayerComplete.listen((_) => finish());
    timeoutTimer = Timer(_playbackTimeoutFor(text), () {
      unawaited(_audioPlayer.stop());
      finish();
    });

    try {
      await completer.future;
    } finally {
      timeoutTimer.cancel();
      await completeSubscription.cancel();
    }
  }

  Future<void> dispose() async {
    await stop();
    _resetWorker();
    await _audioPlayer.dispose();
  }

  void _ensureBindingsInitialized() {
    if (_bindingsInitialized) {
      return;
    }

    sherpa.initBindings();
    _bindingsInitialized = true;
  }

  Future<void> _generateAudioInWorker({
    required OfflineAiVoice voice,
    required String text,
    required double speed,
    required String outputPath,
  }) async {
    final worker = await _ensureWorker();
    final requestId = ++_workerRequestId;
    final completer = Completer<Map<String, Object?>>();
    _workerRequests[requestId] = completer;

    worker.send(<String, Object?>{
      'type': 'generate',
      'id': requestId,
      'voiceId': voice.id,
      'modelPath': await _modelPath(voice),
      'tokensPath': await _tokensPath(voice),
      'dataDir': await _espeakDataPath(voice),
      'text': text,
      'speed': speed.clamp(0.75, 1.3).toDouble(),
      'outputPath': outputPath,
    });

    final response = await completer.future;
    if (response['ok'] != true) {
      throw StateError(response['error']?.toString() ?? 'РќРµ СѓРґР°Р»РѕСЃСЊ СЃРѕР·РґР°С‚СЊ Р°СѓРґРёРѕ.');
    }
  }

  Future<SendPort> _ensureWorker() async {
    final existing = _workerSendPort;
    if (existing != null) {
      return existing;
    }

    final pendingStart = _workerStartCompleter;
    if (pendingStart != null) {
      return pendingStart.future;
    }

    final completer = Completer<SendPort>();
    _workerStartCompleter = completer;
    final receivePort = ReceivePort();
    _workerReceivePort = receivePort;

    receivePort.listen((message) {
      if (message is SendPort) {
        _workerSendPort = message;
        if (!completer.isCompleted) {
          completer.complete(message);
        }
        return;
      }

      if (message is Map) {
        final response = message.cast<String, Object?>();
        final id = response['id'];
        if (id is int) {
          final request = _workerRequests.remove(id);
          if (request != null && !request.isCompleted) {
            request.complete(response);
          }
        }
      }
    });

    try {
      _workerIsolate = await Isolate.spawn(
        _offlineAiTtsWorkerMain,
        receivePort.sendPort,
        debugName: 'reins_offline_ai_tts',
      );
      return completer.future;
    } catch (_) {
      _workerStartCompleter = null;
      receivePort.close();
      rethrow;
    }
  }

  void _resetWorker() {
    _workerSendPort?.send(<String, Object?>{'type': 'dispose'});
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerReceivePort?.close();
    _workerIsolate = null;
    _workerReceivePort = null;
    _workerSendPort = null;
    _workerStartCompleter = null;

    for (final request in _workerRequests.values) {
      if (!request.isCompleted) {
        request.completeError(StateError('РћС„Р»Р°Р№РЅ AI-РіРѕР»РѕСЃ РѕСЃС‚Р°РЅРѕРІР»РµРЅ.'));
      }
    }
    _workerRequests.clear();
  }

  Future<_OfflineAiVoiceDownloadSpec> _resolveVoiceDownloadSpec(OfflineAiVoice voice) async {
    final fallback = _OfflineAiVoiceDownloadSpec(
      urls: [voice.archiveUrl],
      archiveRoot: voice.archiveRoot,
      modelFileName: voice.modelFileName,
    );

    try {
      final manifest = await _fetchDownloadManifest();
      final voices = manifest['voices'];
      if (voices is! Map) return fallback;

      final entry = voices[voice.id];
      if (entry is! Map) return fallback;

      final urls = _readManifestUrls(entry);
      final archiveRoot = (entry['archiveRoot'] as String?)?.trim();
      final modelFileName = (entry['modelFileName'] as String?)?.trim();

      if (urls.isEmpty ||
          archiveRoot == null ||
          archiveRoot.isEmpty ||
          modelFileName == null ||
          modelFileName.isEmpty) {
        return fallback;
      }

      return _OfflineAiVoiceDownloadSpec(
        urls: urls,
        archiveRoot: archiveRoot,
        modelFileName: modelFileName,
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

  List<String> _readManifestUrls(Map<dynamic, dynamic> entry) {
    final urls = <String>[];
    final rawUrls = entry['urls'];
    if (rawUrls is List) {
      urls.addAll(rawUrls.whereType<String>());
    }

    final rawUrl = entry['url'];
    if (rawUrl is String) {
      urls.add(rawUrl);
    }

    return urls
        .map((url) => url.trim())
        .where((url) => url.startsWith('https://') || url.startsWith('http://'))
        .toSet()
        .toList();
  }

  Future<void> _downloadArchive(
    List<String> urls,
    File target,
    void Function(OfflineAiTtsDownloadProgress progress)? onProgress,
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

    throw HttpException('Не удалось скачать голос: $lastError');
  }

  Future<void> _downloadArchiveFromUrl(
    String url,
    File target,
    void Function(OfflineAiTtsDownloadProgress progress)? onProgress,
  ) async {
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    final response = await client.send(request);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      client.close();
      throw HttpException('Не удалось скачать голос: HTTP ${response.statusCode}');
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
          final downloadProgress = (received / total).clamp(0.0, 1.0);
          onProgress?.call(
            OfflineAiTtsDownloadProgress(
              value: downloadProgress * 0.75,
              label: 'Скачивание голоса ${(downloadProgress * 100).round()}%',
            ),
          );
        }
      }
    } finally {
      await sink.close();
      client.close();
    }
  }

  Future<void> _normalizeDownloadedVoiceFiles(
    Directory tempDir,
    OfflineAiVoice voice,
    _OfflineAiVoiceDownloadSpec downloadSpec,
  ) async {
    if (downloadSpec.modelFileName == voice.modelFileName) {
      return;
    }

    final actualModel = File(p.join(tempDir.path, downloadSpec.modelFileName));
    final expectedModel = File(p.join(tempDir.path, voice.modelFileName));
    if (!expectedModel.existsSync() && actualModel.existsSync()) {
      await expectedModel.parent.create(recursive: true);
      await actualModel.copy(expectedModel.path);
    }
  }

  Future<void> _extractArchive(File archiveFile, Directory targetDir, String root) async {
    final compressed = await archiveFile.readAsBytes();
    final tarBytes = BZip2Decoder().decodeBytes(compressed);
    final archive = TarDecoder().decodeBytes(tarBytes);

    for (final file in archive.files) {
      final relativePath = _safeRelativeArchivePath(file.name, root);
      if (relativePath == null || relativePath.isEmpty) {
        continue;
      }

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
    if (normalized == root) {
      return '';
    }

    if (!normalized.startsWith(prefix)) {
      return null;
    }

    return normalized.substring(prefix.length);
  }

  Duration _playbackTimeoutFor(String text) {
    final seconds = (text.length / 7).ceil().clamp(8, 90);
    return Duration(seconds: seconds);
  }

  Future<Directory> _baseDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'offline_ai_tts'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> _voiceDirPath(OfflineAiVoice voice) async {
    return p.join((await _baseDir()).path, voice.id);
  }

  Future<String> _modelPath(OfflineAiVoice voice) async {
    return p.join(await _voiceDirPath(voice), voice.modelFileName);
  }

  Future<String> _tokensPath(OfflineAiVoice voice) async {
    return p.join(await _voiceDirPath(voice), 'tokens.txt');
  }

  Future<String> _espeakDataPath(OfflineAiVoice voice) async {
    return p.join(await _voiceDirPath(voice), 'espeak-ng-data');
  }
}

@pragma('vm:entry-point')
void _offlineAiTtsWorkerMain(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  sherpa.initBindings();
  sherpa.OfflineTts? tts;
  String? loadedVoiceKey;

  void freeEngine() {
    tts?.free();
    tts = null;
    loadedVoiceKey = null;
  }

  receivePort.listen((message) {
    if (message is! Map) {
      return;
    }

    final request = message.cast<String, Object?>();
    final type = request['type'];

    if (type == 'dispose') {
      freeEngine();
      receivePort.close();
      Isolate.exit();
    }

    if (type != 'generate') {
      return;
    }

    final id = request['id'];
    if (id is! int) {
      return;
    }

    try {
      final voiceKey = [
        request['voiceId'],
        request['modelPath'],
        request['tokensPath'],
        request['dataDir'],
      ].join('|');

      if (tts == null || loadedVoiceKey != voiceKey) {
        freeEngine();
        tts = sherpa.OfflineTts(
          sherpa.OfflineTtsConfig(
            model: sherpa.OfflineTtsModelConfig(
              vits: sherpa.OfflineTtsVitsModelConfig(
                model: request['modelPath']!.toString(),
                tokens: request['tokensPath']!.toString(),
                dataDir: request['dataDir']!.toString(),
              ),
              numThreads: 2,
              debug: false,
              provider: 'cpu',
            ),
            maxNumSenetences: 1,
          ),
        );
        loadedVoiceKey = voiceKey;
      }

      final audio = tts!.generate(
        text: request['text']!.toString(),
        sid: 0,
        speed: (request['speed'] as num?)?.toDouble() ?? 1.0,
      );
      final outputPath = request['outputPath']!.toString();
      final ok = sherpa.writeWave(
        filename: outputPath,
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );

      mainSendPort.send(<String, Object?>{
        'id': id,
        'ok': ok && File(outputPath).existsSync(),
      });
    } catch (error) {
      mainSendPort.send(<String, Object?>{
        'id': id,
        'ok': false,
        'error': error.toString(),
      });
    }
  });
}
