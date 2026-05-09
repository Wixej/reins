import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'package:reins/Services/services.dart';

class VoiceSettings extends StatefulWidget {
  const VoiceSettings({super.key});

  @override
  State<VoiceSettings> createState() => _VoiceSettingsState();
}

class _VoiceSettingsState extends State<VoiceSettings> {
  late final Future<List<TtsEngineInfo>> _enginesFuture;
  bool _isApplyingEngine = false;
  bool _isTestingVoice = false;
  bool _isDownloadingVoice = false;
  bool _isDownloadingAsr = false;
  String _downloadLabel = '';
  double _downloadProgress = 0;
  String _asrDownloadLabel = '';
  double _asrDownloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _enginesFuture = context.read<TtsService>().getAvailableEngines();
  }

  @override
  Widget build(BuildContext context) {
    final settingsBox = Hive.box('settings');

    return ValueListenableBuilder(
      valueListenable: settingsBox.listenable(
        keys: [
          'voiceModeEnabled',
          'ttsEngine',
          'voiceReplyEnabled',
          TtsService.modeSettingKey,
          TtsService.offlineVoiceSettingKey,
          TtsService.speechRateSettingKey,
          TtsService.voicePitchSettingKey,
          OfflineAiAsrService.modeSettingKey,
        ],
      ),
      builder: (context, box, _) {
        final voiceModeEnabled = box.get('voiceModeEnabled', defaultValue: false) as bool;
        final voiceReplyEnabled = box.get('voiceReplyEnabled', defaultValue: true) as bool;
        final selectedEngine = box.get('ttsEngine') as String?;
        final selectedMode = box.get(
          TtsService.modeSettingKey,
          defaultValue: TtsService.systemMode,
        ) as String;
        final selectedOfflineVoice = box.get(
          TtsService.offlineVoiceSettingKey,
          defaultValue: OfflineAiTtsService.defaultVoiceId,
        ) as String;
        final speechRate = context.read<TtsService>().currentSpeechRate;
        final voicePitch = context.read<TtsService>().currentVoicePitch;
        final selectedAsrMode = box.get(
          OfflineAiAsrService.modeSettingKey,
          defaultValue: OfflineAiAsrService.systemMode,
        ) as String;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Голос и память',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.headphones_rounded),
              title: const Text('Голосовой режим'),
              subtitle: const Text('Показывает кнопку "Голос" рядом с полем ввода'),
              value: voiceModeEnabled,
              onChanged: (value) => box.put('voiceModeEnabled', value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.volume_up_rounded),
              title: const Text('Озвучивать ответы'),
              subtitle: const Text('Работает внутри голосового режима'),
              value: voiceReplyEnabled,
              onChanged: voiceModeEnabled ? (value) => box.put('voiceReplyEnabled', value) : null,
            ),
            const SizedBox(height: 10),
            _buildSpeechRecognitionSettings(selectedAsrMode),
            const SizedBox(height: 8),
            _buildVoiceEngineModeDropdown(selectedMode),
            const SizedBox(height: 12),
            if (selectedMode == TtsService.offlineAiMode)
              _buildOfflineAiVoiceSettings(selectedOfflineVoice)
            else if (!Platform.isAndroid)
              Text(
                'Выбор системного синтезатора речи сейчас доступен на Android.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              _buildSystemEngineDropdown(selectedEngine),
            const SizedBox(height: 12),
            _buildVoiceTuningSliders(
              speechRate: speechRate,
              voicePitch: voicePitch,
              isOfflineAiMode: selectedMode == TtsService.offlineAiMode,
            ),
            const SizedBox(height: 12),
            _buildTestButton(selectedMode, selectedOfflineVoice),
          ],
        );
      },
    );
  }

  Widget _buildSpeechRecognitionSettings(String selectedAsrMode) {
    final asrService = context.read<OfflineAiAsrService>();
    final model = asrService.modelById(OfflineAiAsrService.defaultModelId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Распознавание речи',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue:
              selectedAsrMode == OfflineAiAsrService.offlineAiMode ? OfflineAiAsrService.offlineAiMode : OfflineAiAsrService.systemMode,
          decoration: const InputDecoration(
            labelText: 'Движок распознавания',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: OfflineAiAsrService.systemMode,
              child: Text('Системный Android'),
            ),
            DropdownMenuItem(
              value: OfflineAiAsrService.offlineAiMode,
              child: Text('Офлайн AI-распознавание'),
            ),
          ],
          onChanged: _isDownloadingAsr
              ? null
              : (value) async {
                  await Hive.box('settings').put(
                    OfflineAiAsrService.modeSettingKey,
                    value ?? OfflineAiAsrService.systemMode,
                  );
                },
        ),
        if (selectedAsrMode == OfflineAiAsrService.offlineAiMode) ...[
          const SizedBox(height: 8),
          Text(
            model.description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_isDownloadingAsr) ...[
            LinearProgressIndicator(value: _asrDownloadProgress == 0 ? null : _asrDownloadProgress),
            const SizedBox(height: 6),
            Text(_asrDownloadLabel),
            const SizedBox(height: 8),
          ],
          FutureBuilder<bool>(
            key: ValueKey('offline-asr-${model.id}-$_isDownloadingAsr'),
            future: asrService.isModelDownloaded(model.id),
            builder: (context, snapshot) {
              final isDownloaded = snapshot.data ?? false;
              return Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _isDownloadingAsr
                          ? null
                          : isDownloaded
                              ? () => _deleteOfflineAsrModel(model.id)
                              : () => _downloadOfflineAsrModel(model.id),
                      icon: Icon(isDownloaded ? Icons.delete_outline_rounded : Icons.download_rounded),
                      label: Text(isDownloaded ? 'Удалить модель' : 'Скачать модель'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    avatar: Icon(
                      isDownloaded ? Icons.check_circle_rounded : Icons.cloud_download_rounded,
                      size: 18,
                    ),
                    label: Text(isDownloaded ? 'Готов' : 'Не скачана'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Модель скачивается во внутреннюю память приложения и после этого распознаёт речь без интернета.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _buildVoiceEngineModeDropdown(String selectedMode) {
    return DropdownButtonFormField<String>(
      initialValue: selectedMode == TtsService.offlineAiMode ? TtsService.offlineAiMode : TtsService.systemMode,
      decoration: const InputDecoration(
        labelText: 'Голосовой движок',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(
          value: TtsService.systemMode,
          child: Text('Системный TTS'),
        ),
        DropdownMenuItem(
          value: TtsService.offlineAiMode,
          child: Text('Офлайн AI-голос'),
        ),
      ],
      onChanged: _isApplyingEngine || _isDownloadingVoice
          ? null
          : (value) async {
              await context.read<TtsService>().setMode(value ?? TtsService.systemMode);
            },
    );
  }

  Widget _buildSystemEngineDropdown(String? selectedEngine) {
    return FutureBuilder<List<TtsEngineInfo>>(
      future: _enginesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }

        if (snapshot.hasError) {
          return Text(
            'Не удалось получить список синтезаторов речи.',
            style: Theme.of(context).textTheme.bodyMedium,
          );
        }

        final engines = snapshot.data ?? const <TtsEngineInfo>[];
        if (engines.isEmpty) {
          return Text(
            'Синтезаторы речи не найдены.',
            style: Theme.of(context).textTheme.bodyMedium,
          );
        }

        TtsEngineInfo? defaultEngine;
        for (final engine in engines) {
          if (engine.isDefault) {
            defaultEngine = engine;
            break;
          }
        }

        final currentEngineValue =
            engines.any((engine) => engine.id == selectedEngine) ? selectedEngine : (defaultEngine ?? engines.first).id;

        return DropdownButtonFormField<String>(
          key: ValueKey(currentEngineValue),
          initialValue: currentEngineValue,
          decoration: const InputDecoration(
            labelText: 'Системный синтезатор речи',
            border: OutlineInputBorder(),
          ),
          items: engines
              .map(
                (engine) => DropdownMenuItem<String>(
                  value: engine.id,
                  child: Text(
                    engine.isDefault ? '${engine.label} (системный)' : engine.label,
                  ),
                ),
              )
              .toList(),
          onChanged: _isApplyingEngine
              ? null
              : (value) async {
                  await _saveSelectedEngine(value);
                },
        );
      },
    );
  }

  Widget _buildOfflineAiVoiceSettings(String selectedVoiceId) {
    final ttsService = context.read<TtsService>();
    final voices = ttsService.offlineAiVoices;
    final selectedVoice = voices.firstWhere(
      (voice) => voice.id == selectedVoiceId,
      orElse: () => voices.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: selectedVoice.id,
          decoration: const InputDecoration(
            labelText: 'Офлайн AI-голос',
            border: OutlineInputBorder(),
          ),
          items: voices
              .map(
                (voice) => DropdownMenuItem<String>(
                  value: voice.id,
                  child: Text(voice.label),
                ),
              )
              .toList(),
          onChanged: _isDownloadingVoice
              ? null
              : (value) async {
                  if (value == null) return;
                  await ttsService.setOfflineVoice(value);
                },
        ),
        const SizedBox(height: 8),
        Text(
          selectedVoice.description,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (_isDownloadingVoice) ...[
          LinearProgressIndicator(value: _downloadProgress == 0 ? null : _downloadProgress),
          const SizedBox(height: 6),
          Text(_downloadLabel),
          const SizedBox(height: 8),
        ],
        FutureBuilder<bool>(
          key: ValueKey('offline-ai-${selectedVoice.id}-$_isDownloadingVoice'),
          future: ttsService.isOfflineVoiceDownloaded(selectedVoice.id),
          builder: (context, snapshot) {
            final isDownloaded = snapshot.data ?? false;
            return Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _isDownloadingVoice
                        ? null
                        : isDownloaded
                            ? () => _deleteSelectedOfflineVoice(selectedVoice.id)
                            : () => _downloadSelectedOfflineVoice(selectedVoice.id),
                    icon: Icon(
                      isDownloaded ? Icons.delete_outline_rounded : Icons.download_rounded,
                    ),
                    label: Text(isDownloaded ? 'Удалить голос' : 'Скачать голос'),
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  avatar: Icon(
                    isDownloaded ? Icons.check_circle_rounded : Icons.cloud_download_rounded,
                    size: 18,
                  ),
                  label: Text(isDownloaded ? 'Готов' : 'Не скачан'),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          'Модель скачивается во внутреннюю память приложения и после этого работает без интернета.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildVoiceTuningSliders({
    required double speechRate,
    required double voicePitch,
    required bool isOfflineAiMode,
  }) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Настройка звучания',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _buildLabeledSlider(
          label: 'Скорость',
          valueLabel: '${speechRate.toStringAsFixed(2)}x',
          value: speechRate,
          min: 0.75,
          max: 1.3,
          divisions: 11,
          onChanged: (value) => context.read<TtsService>().setSpeechRate(value),
        ),
        _buildLabeledSlider(
          label: 'Тембр',
          valueLabel: voicePitch == 1.0 ? 'обычный' : voicePitch.toStringAsFixed(2),
          value: voicePitch,
          min: 0.85,
          max: 1.15,
          divisions: 12,
          onChanged: isOfflineAiMode ? null : (value) => context.read<TtsService>().setVoicePitch(value),
        ),
        if (isOfflineAiMode)
          Text(
            'В офлайн AI-голосе тембр задается выбранной моделью. Ползунок тембра работает для системного TTS.',
            style: textTheme.bodySmall,
          ),
      ],
    );
  }

  Widget _buildLabeledSlider({
    required String label,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(valueLabel, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildTestButton(String selectedMode, String selectedOfflineVoice) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: _isApplyingEngine || _isTestingVoice || _isDownloadingVoice
            ? null
            : () => _testSelectedVoice(selectedMode, selectedOfflineVoice),
        icon: _isTestingVoice
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.record_voice_over_rounded),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            _isTestingVoice ? 'Проверяю голос...' : 'Проверить голос',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Future<void> _testSelectedVoice(String selectedMode, String selectedOfflineVoice) async {
    final ttsService = context.read<TtsService>();
    if (selectedMode == TtsService.offlineAiMode && !await ttsService.isOfflineVoiceDownloaded(selectedOfflineVoice)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала скачайте выбранный офлайн AI-голос.'),
        ),
      );
      return;
    }

    setState(() {
      _isTestingVoice = true;
    });

    try {
      await ttsService.speak(
        'Тестовое сообщение. Выбранный голос работает.',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось проверить голос: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTestingVoice = false;
        });
      }
    }
  }

  Future<void> _downloadSelectedOfflineVoice(String voiceId) async {
    setState(() {
      _isDownloadingVoice = true;
      _downloadLabel = 'Подготовка скачивания...';
      _downloadProgress = 0;
    });

    try {
      await context.read<TtsService>().downloadOfflineVoice(
        voiceId,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _downloadLabel = progress.label;
            _downloadProgress = progress.value;
          });
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Офлайн AI-голос скачан.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось скачать голос: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingVoice = false;
          _downloadLabel = '';
          _downloadProgress = 0;
        });
      }
    }
  }

  Future<void> _deleteSelectedOfflineVoice(String voiceId) async {
    try {
      await context.read<TtsService>().deleteOfflineVoice(voiceId);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Офлайн AI-голос удален.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить голос: $error')),
      );
    }
  }

  Future<void> _downloadOfflineAsrModel(String modelId) async {
    setState(() {
      _isDownloadingAsr = true;
      _asrDownloadLabel = 'Подготовка скачивания...';
      _asrDownloadProgress = 0;
    });

    try {
      await context.read<OfflineAiAsrService>().downloadModel(
        modelId,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _asrDownloadLabel = progress.label;
            _asrDownloadProgress = progress.value;
          });
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Офлайн AI-распознавание скачано.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось скачать распознавание: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingAsr = false;
          _asrDownloadLabel = '';
          _asrDownloadProgress = 0;
        });
      }
    }
  }

  Future<void> _deleteOfflineAsrModel(String modelId) async {
    try {
      await context.read<OfflineAiAsrService>().deleteModel(modelId);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Офлайн AI-распознавание удалено.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить распознавание: $error')),
      );
    }
  }

  Future<void> _saveSelectedEngine(String? value) async {
    setState(() {
      _isApplyingEngine = true;
    });

    try {
      await context.read<TtsService>().setEngine(value);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось переключить синтезатор речи: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingEngine = false;
        });
      }
    }
  }
}
