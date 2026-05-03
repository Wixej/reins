import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:reins/Constants/constants.dart';
import 'package:reins/Models/chat_configure_arguments.dart';
import 'package:reins/Models/ollama_exception.dart';
import 'package:reins/Models/ollama_chat.dart';
import 'package:reins/Providers/chat_provider.dart';
import 'package:reins/Widgets/flexible_text.dart';

import 'ollama_bottom_sheet_header.dart';

class ChatConfigureBottomSheet extends StatelessWidget {
  final ChatConfigureArguments arguments;

  const ChatConfigureBottomSheet({
    super.key,
    required this.arguments,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      child: SafeArea(
        bottom: false,
        minimum: const EdgeInsets.all(16),
        child: Column(
          children: [
            OllamaBottomSheetHeader(title: 'Настройки чата ${AppConstants.buildMarker}'),
            const Divider(),
            Expanded(
              child: _ChatConfigureBottomSheetContent(arguments: arguments),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatConfigureBottomSheetContent extends StatefulWidget {
  final ChatConfigureArguments arguments;

  const _ChatConfigureBottomSheetContent({
    required this.arguments,
  });

  @override
  State<_ChatConfigureBottomSheetContent> createState() => _ChatConfigureBottomSheetContentState();
}

class _ChatConfigureBottomSheetContentState extends State<_ChatConfigureBottomSheetContent> {
  late OllamaChatOptions _chatOptions;
  late String _systemPrompt;

  final _scrollController = ScrollController();
  bool _showAdvancedConfigurations = false;

  @override
  void initState() {
    super.initState();
    _chatOptions = widget.arguments.chatOptions;
    _systemPrompt = widget.arguments.systemPrompt ?? '';
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.arguments.systemPrompt = _systemPrompt;
    widget.arguments.chatOptions = _chatOptions;

    return ListView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Expanded(child: _RenameButton()),
            SizedBox(width: 16),
            Expanded(child: _SaveAsNewModelButton()),
            SizedBox(width: 16),
            Expanded(child: _DeleteButton()),
          ],
        ),
        const SizedBox(height: 16),
        _BottomSheetTextField<String>(
          initialValue: _systemPrompt,
          labelText: 'Системный промпт',
          infoText: 'Задает общий стиль и поведение модели для этого чата.',
          type: _BottomSheetTextFieldType.text,
          onChanged: (value) => _systemPrompt = value ?? '',
        ),
        const SizedBox(height: 16),
        _BottomSheetDropdownField<String>(
          value: _chatOptions.rolePresetId,
          labelText: 'Поведение модели',
          infoText:
              'Добавляет к каждому запросу выбранную роль. "По умолчанию" означает, что дополнительная роль не используется.',
          items: ChatRoles.values
              .map(
                (role) => DropdownMenuItem<String>(
                  value: role.id,
                  child: Text(role.label),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _chatOptions.rolePresetId = value);
            }
          },
        ),
        const SizedBox(height: 16),
        _BottomSheetDropdownField<OllamaKeepAliveOption>(
          value: _chatOptions.keepAlive,
          labelText: 'Выгружать модель',
          infoText: 'Сколько времени Ollama должен держать текущую модель в памяти после ответа.',
          items: OllamaKeepAliveOption.values
              .map(
                (option) => DropdownMenuItem<OllamaKeepAliveOption>(
                  value: option,
                  child: Text(option.label),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _chatOptions.keepAlive = value);
            }
          },
        ),
        const SizedBox(height: 16),
        _BottomSheetDropdownField<bool>(
          value: _chatOptions.thinkingEnabled,
          labelText: 'Мышление',
          infoText: 'Включает или отключает вывод размышлений модели. При отключении клиент отправляет think: false.',
          items: const [
            DropdownMenuItem<bool>(
              value: true,
              child: Text('Включено'),
            ),
            DropdownMenuItem<bool>(
              value: false,
              child: Text('Отключено'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _chatOptions.thinkingEnabled = value);
            }
          },
        ),
        const SizedBox(height: 16),
        _BottomSheetTextField<double>(
          initialValue: _chatOptions.temperature,
          labelText: 'Температура',
          infoText: 'Чем выше значение, тем свободнее и креативнее ответы модели.',
          type: _BottomSheetTextFieldType.decimalBetween0And1,
          onChanged: (value) => _chatOptions.temperature = value ?? 0.8,
        ),
        const SizedBox(height: 16),
        _BottomSheetTextField<int>(
          initialValue: _chatOptions.seed,
          labelText: 'Сид',
          infoText: 'Позволяет получать более повторяемые ответы при одинаковом запросе.',
          type: _BottomSheetTextFieldType.number,
          onChanged: (value) => _chatOptions.seed = value ?? 0,
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _toggleAdvancedConfigurations,
          child: Text(
            _showAdvancedConfigurations ? 'Скрыть расширенные настройки' : 'Показать расширенные настройки',
          ),
        ),
        if (_showAdvancedConfigurations) ...[
          _BottomSheetTextField<int>(
            initialValue: _chatOptions.maxTokens,
            labelText: 'Макс. токенов',
            infoText: 'Максимальное количество токенов в ответе. -1 означает без ограничения.',
            type: _BottomSheetTextFieldType.number,
            onChanged: (value) => _chatOptions.maxTokens = value ?? -1,
          ),
          const SizedBox(height: 16),
          _BottomSheetTextField<int>(
            initialValue: _chatOptions.repeatLastN,
            labelText: 'Повтор последних N',
            infoText: 'Сколько последних токенов учитывается для защиты от повторов.',
            type: _BottomSheetTextFieldType.number,
            onChanged: (value) => _chatOptions.repeatLastN = value ?? 64,
          ),
          const SizedBox(height: 16),
          _BottomSheetTextField<int>(
            initialValue: _chatOptions.contextSize,
            labelText: 'Размер контекста',
            infoText: 'Размер окна контекста, доступного модели при генерации ответа.',
            type: _BottomSheetTextFieldType.number,
            onChanged: (value) => _chatOptions.contextSize = value ?? 2048,
          ),
          const SizedBox(height: 16),
          _BottomSheetTextField<double>(
            initialValue: _chatOptions.repeatPenalty,
            labelText: 'Штраф за повторы',
            infoText: 'Насколько сильно модель должна избегать повторения уже использованных токенов.',
            type: _BottomSheetTextFieldType.decimal,
            onChanged: (value) => _chatOptions.repeatPenalty = value ?? 1.1,
          ),
          const SizedBox(height: 16),
          _BottomSheetTextField<double>(
            initialValue: _chatOptions.tailFreeSampling,
            labelText: 'Tail Free Sampling',
            infoText: 'Уменьшает влияние маловероятных токенов и сглаживает выбор ответа.',
            type: _BottomSheetTextFieldType.decimal,
            onChanged: (value) => _chatOptions.tailFreeSampling = value ?? 1.0,
          ),
          const SizedBox(height: 16),
          _BottomSheetTextField<int>(
            initialValue: _chatOptions.topK,
            labelText: 'Top K',
            infoText: 'Ограничивает выбор следующего токена только наиболее вероятными вариантами.',
            type: _BottomSheetTextFieldType.number,
            onChanged: (value) => _chatOptions.topK = value ?? 40,
          ),
          const SizedBox(height: 16),
          _BottomSheetTextField<double>(
            initialValue: _chatOptions.topP,
            labelText: 'Top P',
            infoText: 'Оставляет только те токены, которые попадают в накопленную вероятность P.',
            type: _BottomSheetTextFieldType.decimalBetween0And1,
            onChanged: (value) => _chatOptions.topP = value ?? 0.9,
          ),
          const SizedBox(height: 16),
          _BottomSheetTextField<double>(
            initialValue: _chatOptions.minP,
            labelText: 'Min P',
            infoText: 'Фильтрует токены с очень низкой вероятностью относительно самого вероятного варианта.',
            type: _BottomSheetTextFieldType.decimalBetween0And1,
            onChanged: (value) => _chatOptions.minP = value ?? 0.0,
          ),
          const SizedBox(height: 16),
          _BottomSheetTextField<int>(
            initialValue: _chatOptions.mirostat,
            labelText: 'Mirostat',
            infoText: '0 = выключено, 1 = Mirostat, 2 = Mirostat 2.0.',
            type: _BottomSheetTextFieldType.number,
            onChanged: (value) => _chatOptions.mirostat = value ?? 0,
          ),
          const SizedBox(height: 16),
          _BottomSheetTextField<double>(
            initialValue: _chatOptions.mirostatEta,
            labelText: 'Mirostat Eta',
            infoText: 'Скорость реакции алгоритма Mirostat на изменение текста.',
            type: _BottomSheetTextFieldType.decimalBetween0And1,
            onChanged: (value) => _chatOptions.mirostatEta = value ?? 0.1,
          ),
          const SizedBox(height: 16),
          _BottomSheetTextField<double>(
            initialValue: _chatOptions.mirostatTau,
            labelText: 'Mirostat Tau',
            infoText: 'Целевой уровень неожиданности текста для Mirostat.',
            type: _BottomSheetTextFieldType.decimal,
            onChanged: (value) => _chatOptions.mirostatTau = value ?? 5.0,
          ),
          const SizedBox(height: 16),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline_rounded),
              SizedBox(width: 8),
              FlexibleText(
                'Оставь поле пустым, чтобы использовать значение по умолчанию',
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _resetToDefaults,
            icon: const Icon(Icons.settings_backup_restore_rounded),
            label: const Text('Сбросить по умолчанию'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
          ),
        ],
      ],
    );
  }

  void _toggleAdvancedConfigurations() {
    setState(() {
      _showAdvancedConfigurations = !_showAdvancedConfigurations;
    });

    if (_showAdvancedConfigurations) {
      _scrollController.animateTo(
        _scrollController.position.pixels + 120,
        duration: const Duration(milliseconds: 350),
        curve: Curves.ease,
      );
    } else {
      _scrollController.animateTo(
        _scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.ease,
      );
    }
  }

  void _resetToDefaults() {
    setState(() {
      final defaults = ChatConfigureArguments.defaultArguments;
      _systemPrompt = defaults.systemPrompt ?? '';
      _chatOptions = defaults.chatOptions;
    });
  }
}

class _RenameButton extends StatelessWidget {
  const _RenameButton();

  @override
  Widget build(BuildContext context) {
    return _BottomSheetButton(
      icon: const Icon(Icons.edit_outlined),
      title: 'Переименовать',
      isDisabled: context.read<ChatProvider>().currentChat == null,
      onPressed: () async {
        final chatProvider = context.read<ChatProvider>();
        final newTitle = await _showRenameDialog(
          context,
          currentTitle: chatProvider.currentChat?.title,
        );

        if (newTitle != null) {
          await chatProvider.updateCurrentChat(newTitle: newTitle);
        }
      },
    );
  }

  Future<String?> _showRenameDialog(
    BuildContext context, {
    String? currentTitle,
  }) {
    String currentValue = currentTitle ?? '';

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать чат'),
        content: TextFormField(
          initialValue: currentTitle,
          decoration: const InputDecoration(
            labelText: 'Новое имя',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
          onChanged: (value) => currentValue = value,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              final trimmed = currentValue.trim();
              if (trimmed.isNotEmpty) {
                Navigator.of(context).pop(trimmed);
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}

class _SaveAsNewModelButton extends StatelessWidget {
  const _SaveAsNewModelButton();

  @override
  Widget build(BuildContext context) {
    return _BottomSheetButton(
      icon: const Icon(Icons.save_as_outlined),
      title: 'Сохранить модель',
      onPressed: () async {
        final chatProvider = context.read<ChatProvider>();
        final newModelName = await _showSaveAsNewModelDialog(context);
        if (newModelName == null) return;

        bool success = false;
        String errorMessage = '';

        try {
          await chatProvider.saveAsNewModel(newModelName);
          success = true;
        } on OllamaException catch (error) {
          errorMessage = error.message;
        }

        if (!context.mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Модель "$newModelName" успешно сохранена.'
                  : 'Не удалось сохранить модель "$newModelName": $errorMessage',
            ),
            showCloseIcon: true,
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );

        if (success) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  Future<String?> _showSaveAsNewModelDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SaveAsNewModelDialog(),
    );
  }
}

class _SaveAsNewModelDialog extends StatefulWidget {
  const _SaveAsNewModelDialog();

  @override
  State<_SaveAsNewModelDialog> createState() => _SaveAsNewModelDialogState();
}

class _SaveAsNewModelDialogState extends State<_SaveAsNewModelDialog> {
  static final _modelNamePattern = RegExp(
    r'^[a-zA-Z0-9][a-zA-Z0-9._-]*(/[a-zA-Z0-9][a-zA-Z0-9._-]*)?(:[a-zA-Z0-9][a-zA-Z0-9._-]*)?$',
  );

  String _modelName = '';
  String? _errorText;

  bool get _isValid => _modelName.trim().isNotEmpty && _errorText == null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Сохранить как новую модель',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: TextField(
          decoration: InputDecoration(
            labelText: 'Имя новой модели',
            errorText: _errorText,
            helperText: 'Формат: model, namespace/model или model:tag',
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) {
            setState(() {
              _modelName = value;
              _errorText = _validateModelName(value);
            });
          },
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: _isValid ? () => Navigator.of(context).pop(_modelName.trim()) : null,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  String? _validateModelName(String value) {
    if (value.trim().isEmpty) return null;
    if (value.contains(' ')) {
      return 'Имя модели не должно содержать пробелы';
    }
    if (!_modelNamePattern.hasMatch(value.trim())) {
      return 'Используй формат [namespace/]model[:tag]';
    }
    return null;
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton();

  @override
  Widget build(BuildContext context) {
    return _BottomSheetButton(
      icon: const Icon(Icons.delete_outline),
      title: 'Удалить',
      isDestructive: true,
      isDisabled: context.read<ChatProvider>().currentChat == null,
      onPressed: () => _showDeleteDialog(context),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить чат?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              context.read<ChatProvider>().deleteCurrentChat();
              Navigator.of(context)
                ..pop()
                ..pop(ChatConfigureBottomSheetAction.delete);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}

class _BottomSheetButton extends StatelessWidget {
  final Icon icon;
  final String title;
  final VoidCallback? onPressed;
  final bool isDisabled;
  final bool isDestructive;

  const _BottomSheetButton({
    required this.icon,
    required this.title,
    required this.onPressed,
    this.isDisabled = false,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isDisabled ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        foregroundColor: isDestructive ? Colors.red : null,
        iconColor: isDestructive ? Colors.red : null,
        padding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          FlexibleText(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _BottomSheetDropdownField<T> extends StatelessWidget {
  final T value;
  final String labelText;
  final String infoText;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _BottomSheetDropdownField({
    required this.value,
    required this.labelText,
    required this.infoText,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _BottomSheetFieldShell(
      trailing: const Icon(Icons.arrow_drop_down_rounded),
      onInfoPressed: () => _showInfoDialog(context, labelText, infoText),
      child: DropdownButtonFormField<T>(
        key: ValueKey<Object?>(value),
        initialValue: value,
        icon: const SizedBox.shrink(),
        decoration: _buildBottomSheetFieldDecoration(
          labelText: labelText,
          contentPadding: const EdgeInsets.fromLTRB(16, 22, 88, 18),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

class _BottomSheetTextField<T> extends StatefulWidget {
  final T? initialValue;
  final String labelText;
  final String infoText;
  final _BottomSheetTextFieldType type;
  final Function(T?)? onChanged;

  const _BottomSheetTextField({
    this.initialValue,
    required this.labelText,
    required this.infoText,
    required this.type,
    this.onChanged,
  });

  @override
  State<_BottomSheetTextField<T>> createState() => _BottomSheetTextFieldState<T>();
}

class _BottomSheetTextFieldState<T> extends State<_BottomSheetTextField<T>> {
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    return _BottomSheetFieldShell(
      onInfoPressed: () => _showInfoDialog(context, widget.labelText, widget.infoText),
      child: TextFormField(
        initialValue: widget.initialValue?.toString(),
        decoration: _buildBottomSheetFieldDecoration(
          labelText: widget.labelText,
          hintText: _hintText,
          errorText: _errorText,
        ),
        onChanged: (value) {
          final (validValue, errorText) = _validator(value);
          setState(() => _errorText = errorText);
          widget.onChanged?.call(validValue);
        },
        keyboardType: _keyboardType,
        textCapitalization: TextCapitalization.sentences,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      ),
    );
  }

  String get _hintText {
    switch (widget.type) {
      case _BottomSheetTextFieldType.text:
        return 'Введите текст';
      case _BottomSheetTextFieldType.number:
        return 'Введите число';
      case _BottomSheetTextFieldType.decimal:
        return 'Введите значение';
      case _BottomSheetTextFieldType.decimalBetween0And1:
        return 'Введите значение от 0 до 1';
    }
  }

  (T?, String?) Function(String?) get _validator {
    switch (widget.type) {
      case _BottomSheetTextFieldType.text:
        return (value) {
          if (value == null) return (null, 'Поле не должно быть пустым');
          if (value.isEmpty) return (null, null);
          return (value as T?, null);
        };
      case _BottomSheetTextFieldType.number:
        return (value) {
          if (value == null) return (null, 'Поле не должно быть пустым');
          if (value.isEmpty) return (null, null);
          final parsed = int.tryParse(value);
          if (parsed == null) {
            return (null, 'Нужно ввести целое число');
          }
          return (parsed as T?, null);
        };
      case _BottomSheetTextFieldType.decimal:
        return (value) {
          final normalized = value?.replaceAll(',', '.');
          if (normalized == null) return (null, 'Поле не должно быть пустым');
          if (normalized.isEmpty) return (null, null);
          final parsed = double.tryParse(normalized);
          if (parsed == null) {
            return (null, 'Нужно ввести число');
          }
          return (parsed as T?, null);
        };
      case _BottomSheetTextFieldType.decimalBetween0And1:
        return (value) {
          final normalized = value?.replaceAll(',', '.');
          if (normalized == null) return (null, 'Поле не должно быть пустым');
          if (normalized.isEmpty) return (null, null);
          final parsed = double.tryParse(normalized);
          if (parsed == null) {
            return (null, 'Нужно ввести число');
          }
          if (parsed < 0 || parsed > 1) {
            return (null, 'Значение должно быть от 0 до 1');
          }
          return (parsed as T?, null);
        };
    }
  }

  TextInputType get _keyboardType {
    switch (widget.type) {
      case _BottomSheetTextFieldType.text:
        return TextInputType.text;
      case _BottomSheetTextFieldType.number:
        return TextInputType.number;
      case _BottomSheetTextFieldType.decimal:
      case _BottomSheetTextFieldType.decimalBetween0And1:
        return const TextInputType.numberWithOptions(decimal: true);
    }
  }
}

class _BottomSheetFieldShell extends StatelessWidget {
  final Widget child;
  final Widget? trailing;
  final VoidCallback onInfoPressed;

  const _BottomSheetFieldShell({
    required this.child,
    required this.onInfoPressed,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        child,
        Positioned(
          right: 8,
          top: 0,
          bottom: 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trailing != null) ...[
                IconTheme(
                  data: IconThemeData(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  child: trailing!,
                ),
                const SizedBox(width: 2),
              ],
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: onInfoPressed,
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

InputDecoration _buildBottomSheetFieldDecoration({
  required String labelText,
  String? hintText,
  String? errorText,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.fromLTRB(16, 22, 56, 18),
}) {
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    errorText: errorText,
    isDense: true,
    contentPadding: contentPadding,
    border: const OutlineInputBorder(),
  );
}

void _showInfoDialog(BuildContext context, String title, String message) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}

enum _BottomSheetTextFieldType {
  text,
  number,
  decimal,
  decimalBetween0And1,
}

enum ChatConfigureBottomSheetAction { delete }
