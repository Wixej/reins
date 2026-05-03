import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

import 'package:reins/Models/settings_route_arguments.dart';
import 'package:reins/Services/services.dart';
import 'package:reins/Widgets/chat_app_bar.dart';
import 'package:reins/Widgets/model_selection_bottom_sheet.dart';

import 'chat_page_view_model.dart';
import 'subwidgets/subwidgets.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatPageViewModel _viewModel;

  var _crossFadeState = CrossFadeState.showFirst;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _viewModel = context.read<ChatPageViewModel>();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ChatPageViewModel>();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (!ResponsiveBreakpoints.of(context).isMobile) const ChatAppBar(),
        Expanded(
          child: Stack(
            alignment: Alignment.bottomLeft,
            children: [
              _buildChatBody(),
              _buildChatFooter(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_viewModel.voiceModeEnabled) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 4),
                  child: _buildVoiceModeButton(),
                ),
              ],
              Expanded(
                child: ChatTextField(
                  key: ValueKey(_viewModel.currentChat?.id),
                  controller: _viewModel.textFieldController,
                  onEditingComplete: _sendMessage,
                  prefixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _handleAttachmentButton,
                  ),
                  suffixIcon: _buildTextFieldSuffixIcon(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatBody() {
    if (_viewModel.messages.isEmpty) {
      if (_viewModel.currentChat == null) {
        if (!_viewModel.isServerConfigured) {
          return ChatEmpty(
            child: ChatWelcome(
              showingState: _crossFadeState,
              onFirstChildFinished: () => setState(() => _crossFadeState = CrossFadeState.showSecond),
              secondChildScale: _scale,
              onSecondChildScaleEnd: () => setState(() => _scale = 1.0),
            ),
          );
        }

        return ChatEmpty(
          child: ChatSelectModelButton(
            currentModelName: _viewModel.selectedModel?.name,
            onPressed: _showModelSelectionBottomSheet,
          ),
        );
      }

      return const ChatEmpty(
        child: Text('Пока нет сообщений'),
      );
    }

    return ChatListView(
      key: PageStorageKey<String>(_viewModel.currentChat?.id ?? 'empty'),
      messages: _viewModel.messages,
      isAwaitingReply: _viewModel.isThinking,
      error: _viewModel.currentError != null
          ? ChatError(
              message: _viewModel.currentError!.message,
              onRetry: () => _viewModel.retryLastPrompt(),
            )
          : null,
      bottomPadding: _viewModel.hasAttachments ? MediaQuery.of(context).size.height * 0.15 : null,
    );
  }

  Widget _buildChatFooter() {
    if (_viewModel.hasAttachments) {
      final imageCount = _viewModel.imageFiles.length;

      return ChatAttachmentRow(
        itemCount: imageCount + _viewModel.documents.length,
        itemBuilder: (context, index) {
          if (index >= imageCount) {
            return ChatAttachmentDocument(
              document: _viewModel.documents[index - imageCount],
              onRemove: _viewModel.removeDocument,
            );
          }

          return ChatAttachmentImage(
            imageFile: _viewModel.imageFiles[index],
            onRemove: (imageFile) => _viewModel.removeImage(imageFile),
          );
        },
      );
    }

    if (_viewModel.messages.isEmpty) {
      return ChatAttachmentRow(
        itemCount: _viewModel.presets.length,
        itemBuilder: (context, index) {
          final preset = _viewModel.presets[index];
          return ChatAttachmentPreset(
            preset: preset,
            onPressed: () async {
              _viewModel.setTextFieldValue(preset.prompt);
              await _sendMessage();
            },
          );
        },
      );
    }

    return const SizedBox();
  }

  Widget _buildVoiceModeButton() {
    if (_viewModel.isVoiceConversationMode) {
      return FilledButton.icon(
        onPressed: _toggleVoiceConversation,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF0A7CFF),
          foregroundColor: Colors.white,
          minimumSize: const Size(132, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        icon: const Icon(Icons.graphic_eq_rounded, size: 20),
        label: const Text(
          'Завершить',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      );
    }

    return IconButton.filledTonal(
      onPressed: _toggleVoiceConversation,
      icon: const Icon(
        Icons.headphones_rounded,
        semanticLabel: 'voice-button-v67',
      ),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(48),
        iconSize: 24,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget? _buildTextFieldSuffixIcon() {
    if (_viewModel.isStreaming) {
      return IconButton(
        icon: const Icon(Icons.stop_rounded),
        color: Theme.of(context).colorScheme.onSurface,
        onPressed: _viewModel.cancelStreaming,
      );
    }

    if (_viewModel.isListening && _viewModel.isVoiceConversationMode) {
      return IconButton(
        icon: const Icon(Icons.hearing_rounded),
        color: Theme.of(context).colorScheme.primary,
        onPressed: _toggleVoiceConversation,
      );
    }

    if (_viewModel.isListening) {
      return IconButton(
        icon: const Icon(Icons.mic),
        color: Theme.of(context).colorScheme.primary,
        onPressed: () => _viewModel.toggleVoiceInput(
          onPermissionDenied: _showMicrophoneDeniedAlert,
          onError: _showVoiceInputError,
        ),
      );
    }

    if (_viewModel.canSend) {
      return IconButton(
        icon: const Icon(Icons.arrow_upward_rounded),
        color: Theme.of(context).colorScheme.onSurface,
        onPressed: _sendMessage,
      );
    }

    if (_viewModel.isVoiceConversationMode) {
      return IconButton(
        icon: const Icon(Icons.graphic_eq_rounded),
        color: Theme.of(context).colorScheme.primary,
        onPressed: _toggleVoiceConversation,
      );
    }

    if (_viewModel.supportsVoiceInput) {
      return IconButton(
        icon: const Icon(Icons.mic_none_rounded),
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        onPressed: () => _viewModel.toggleVoiceInput(
          onPermissionDenied: _showMicrophoneDeniedAlert,
          onError: _showVoiceInputError,
        ),
      );
    }

    return null;
  }

  Future<void> _sendMessage() async {
    await _viewModel.sendMessage(
      onModelSelectionRequired: _showModelSelectionBottomSheet,
      onServerNotConfigured: _onServerNotConfigured,
    );
  }

  Future<void> _toggleVoiceConversation() async {
    await _viewModel.toggleVoiceConversation(
      onModelSelectionRequired: _showModelSelectionBottomSheet,
      onServerNotConfigured: _openServerSettings,
      onPermissionDenied: _showMicrophoneDeniedAlert,
      onError: _showVoiceInputError,
    );
  }

  Future<void> _showModelSelectionBottomSheet() async {
    final selectedModel = await showModelSelectionBottomSheet(
      context: context,
      title: 'Выбор модели',
      currentModelName: _viewModel.selectedModel?.name,
    );

    if (selectedModel != null) {
      _viewModel.setSelectedModel(selectedModel);
    }
  }

  Future<void> _handleAttachmentButton() async {
    final action = await showModalBottomSheet<_AttachmentAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Сделать фото'),
              onTap: () => Navigator.of(context).pop(_AttachmentAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Выбрать из галереи'),
              onTap: () => Navigator.of(context).pop(_AttachmentAction.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_outlined),
              title: const Text('Прикрепить документ'),
              subtitle: const Text('PDF, TXT, MD'),
              onTap: () => Navigator.of(context).pop(_AttachmentAction.document),
            ),
          ],
        ),
      ),
    );

    if (action == null) {
      return;
    }

    if (action == _AttachmentAction.document) {
      await _viewModel.pickDocuments(onError: _showVoiceInputError);
      return;
    }

    final source = action == _AttachmentAction.camera ? ImageSource.camera : ImageSource.gallery;

    await _viewModel.pickImages(
      source: source,
      onPermissionDenied: source == ImageSource.camera ? _showCameraDeniedAlert : _showPhotosDeniedAlert,
    );
  }

  void _onServerNotConfigured() {
    setState(() {
      _crossFadeState = CrossFadeState.showSecond;
      _scale = _scale == 1.0 ? 1.05 : 1.0;
    });
  }

  void _openServerSettings() {
    _onServerNotConfigured();
    Navigator.of(context).pushNamed(
      '/settings',
      arguments: SettingsRouteArguments(autoFocusServerAddress: true),
    );
  }

  Future<void> _showPhotosDeniedAlert() async {
    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Нет доступа к фото'),
          content: const Text('Разреши доступ к фотографиям в системных настройках.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ОК'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCameraDeniedAlert() async {
    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Нет доступа к камере'),
          content: const Text('Разреши доступ к камере в системных настройках.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ОК'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMicrophoneDeniedAlert() async {
    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Нет доступа к микрофону'),
          content: const Text('Разреши доступ к микрофону в системных настройках.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ОК'),
            ),
          ],
        );
      },
    );
  }

  void _showVoiceInputError(String message) {
    if (SpeechService.isQuietSpeechErrorMessage(message)) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

enum _AttachmentAction {
  camera,
  gallery,
  document,
}
