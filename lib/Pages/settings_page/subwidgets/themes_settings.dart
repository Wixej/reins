import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:reins/Constants/constants.dart';

class ThemesSettings extends StatefulWidget {
  const ThemesSettings({super.key});

  @override
  State<ThemesSettings> createState() => _ThemesSettingsState();
}

class _ThemesSettingsState extends State<ThemesSettings> {
  final _settingsBox = Hive.box('settings');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Тема',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: ShapeDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: CircleAvatar(
                      backgroundImage: AssetImage(AppConstants.appIconPng),
                      radius: MediaQuery.of(context).textScaler.scale(16),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Текущая тема: $_currentThemeLabel',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _BrightnessChip(
                    label: 'Система',
                    icon: Icons.radio_button_off,
                    selected: _brightnessValue == null,
                    onSelected: () => _setBrightness(null),
                  ),
                  _BrightnessChip(
                    label: 'Белая',
                    icon: Icons.light_mode_outlined,
                    selected: _brightnessValue == 1,
                    onSelected: () => _setBrightness(1),
                  ),
                  _BrightnessChip(
                    label: 'Темная',
                    icon: Icons.dark_mode_outlined,
                    selected: _brightnessValue == 0,
                    onSelected: () => _setBrightness(0),
                  ),
                  _BrightnessChip(
                    label: 'Черная',
                    icon: Icons.nightlight_round,
                    selected: _brightnessValue == 2,
                    onSelected: () => _setBrightness(2),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ThemeButton(
              seedColor: Colors.red,
              onPressed: () => _settingsBox.put("color", Colors.red),
            ),
            _ThemeButton(
              seedColor: Colors.green,
              onPressed: () => _settingsBox.put("color", Colors.green),
            ),
            _ThemeButton(
              seedColor: Colors.blue,
              onPressed: () => _settingsBox.put("color", Colors.blue),
            ),
            _ThemeButton(
              seedColor: Colors.purple,
              onPressed: () => _settingsBox.put("color", Colors.purple),
            ),
            _ThemeButton(
              seedColor: Colors.orange,
              onPressed: () => _settingsBox.put("color", Colors.orange),
            ),
            _ThemeButton(
              seedColor: Colors.grey,
              onPressed: () => _settingsBox.put("color", Colors.grey),
            ),
          ],
        ),
      ],
    );
  }

  void _setBrightness(int? value) {
    setState(() => _settingsBox.put('brightness', value));
  }

  int? get _brightnessValue => _settingsBox.get('brightness') as int?;

  String get _currentThemeLabel {
    return switch (_brightnessValue) {
      null => 'как в системе',
      1 => 'белая',
      0 => 'темная',
      2 => 'черная',
      _ => 'как в системе',
    };
  }
}

class _BrightnessChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;

  const _BrightnessChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onSelected: (_) => onSelected(),
    );
  }
}

class _ThemeButton extends StatelessWidget {
  final Color seedColor;
  final Function()? onPressed;

  const _ThemeButton({required this.seedColor, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Theme.of(context).brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.neutral,
    );

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.surfaceContainer,
        padding: EdgeInsets.all(16.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _colorNames[seedColor] ?? "Своя",
            style: TextStyle(color: colorScheme.primary),
          ),
          Container(
            height: 20,
            width: 80,
            decoration: ShapeDecoration(
              color: colorScheme.primary,
              shape: StadiumBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 20,
            width: 80,
            decoration: ShapeDecoration(
              color: colorScheme.surface,
              shape: StadiumBorder(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static final _colorNames = {
    Colors.red: "Красная",
    Colors.blue: "Синяя",
    Colors.purple: "Фиолетовая",
    Colors.orange: "Оранжевая",
    Colors.green: "Зеленая",
    Colors.grey: "Серая",
  };
}
