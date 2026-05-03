import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class UserFactsSettings extends StatefulWidget {
  const UserFactsSettings({super.key});

  @override
  State<UserFactsSettings> createState() => _UserFactsSettingsState();
}

class _UserFactsSettingsState extends State<UserFactsSettings> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final settingsBox = Hive.box('settings');
    _controller = TextEditingController(
      text: settingsBox.get('userFacts', defaultValue: '') as String,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsBox = Hive.box('settings');

    return ValueListenableBuilder(
      valueListenable: settingsBox.listenable(keys: ['userFacts']),
      builder: (context, box, _) {
        final userFacts = box.get('userFacts', defaultValue: '') as String;

        if (!_focusNode.hasFocus && _controller.text != userFacts) {
          _controller.value = TextEditingValue(
            text: userFacts,
            selection: TextSelection.collapsed(offset: userFacts.length),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Факты о вас',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              minLines: 4,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Что модель должна знать о вас',
                hintText: 'Например: меня зовут Алексей, мне 39, я живу в Тюмени и люблю рыбалку.',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => box.put('userFacts', value),
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            ),
            const SizedBox(height: 8),
            Text(
              'Эти факты подмешиваются к каждому запросу вместе с текущими датой и временем устройства.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        );
      },
    );
  }
}
