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
        keys: ['voiceModeEnabled', 'ttsEngine', 'voiceReplyEnabled'],
      ),
      builder: (context, box, _) {
        final voiceModeEnabled = box.get('voiceModeEnabled', defaultValue: false) as bool;
        final voiceReplyEnabled = box.get('voiceReplyEnabled', defaultValue: true) as bool;
        final selectedEngine = box.get('ttsEngine') as String?;

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
            const SizedBox(height: 8),
            if (!Platform.isAndroid)
              Text(
                'Выбор синтезатора речи сейчас доступен на Android.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              FutureBuilder<List<TtsEngineInfo>>(
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

                  final currentEngineValue = engines.any((engine) => engine.id == selectedEngine)
                      ? selectedEngine
                      : (defaultEngine ?? engines.first).id;

                  return DropdownButtonFormField<String>(
                    key: ValueKey(currentEngineValue),
                    initialValue: currentEngineValue,
                    decoration: const InputDecoration(
                      labelText: 'Синтезатор речи',
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
              ),
            const SizedBox(height: 12),
            _buildTestButton(),
          ],
        );
      },
    );
  }

  Widget _buildTestButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: _isApplyingEngine || _isTestingVoice ? null : _testSelectedVoice,
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

  Future<void> _testSelectedVoice() async {
    setState(() {
      _isTestingVoice = true;
    });

    try {
      await context.read<TtsService>().speak(
            'Тестовое сообщение. Выбранный синтезатор речи работает.',
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось проверить синтезатор речи: $error'),
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
