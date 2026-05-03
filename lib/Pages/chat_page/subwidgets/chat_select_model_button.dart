import 'package:flutter/material.dart';

class ChatSelectModelButton extends StatelessWidget {
  final String? currentModelName;
  final void Function() onPressed;

  const ChatSelectModelButton({
    super.key,
    this.currentModelName,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      icon: const Icon(Icons.auto_awesome_outlined),
      label: Text(currentModelName ?? 'Выберите модель, чтобы начать'),
      iconAlignment: IconAlignment.end,
      onPressed: onPressed,
    );
  }
}
