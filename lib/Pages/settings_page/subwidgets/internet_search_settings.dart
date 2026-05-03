import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class InternetSearchSettings extends StatelessWidget {
  const InternetSearchSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsBox = Hive.box('settings');

    return ValueListenableBuilder(
      valueListenable: settingsBox.listenable(keys: ['webSearchEnabled']),
      builder: (context, box, _) {
        final isEnabled = box.get('webSearchEnabled', defaultValue: false) as bool;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Поиск в интернете',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.travel_explore_rounded),
              title: const Text('Разрешить веб-поиск'),
              subtitle: const Text(
                  'Модель сама решает, когда нужны свежие данные, а клиент подмешивает найденные источники в ответ.'),
              value: isEnabled,
              onChanged: (value) => box.put('webSearchEnabled', value),
            ),
          ],
        );
      },
    );
  }
}
