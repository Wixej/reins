import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:reins/Constants/constants.dart';
import 'package:reins/Models/chat_preset.dart';
import 'package:reins/Models/document_attachment.dart';
import 'package:reins/Models/ollama_chat.dart';
import 'package:reins/Models/ollama_exception.dart';
import 'package:reins/Models/ollama_message.dart';
import 'package:reins/Models/ollama_model.dart';
import 'package:reins/Providers/chat_provider.dart';
import 'package:reins/Services/services.dart';

class ChatPageViewModel extends ChangeNotifier {
  final ChatProvider _chatProvider;
  final PermissionService _permissionService;
  final ImageService _imageService;
  final DocumentService _documentService;
  final SpeechService _speechService;
  final TtsService _ttsService;

  ChatPageViewModel({
    required ChatProvider chatProvider,
    required PermissionService permissionService,
    required ImageService imageService,
    required DocumentService documentService,
    required SpeechService speechService,
    required TtsService ttsService,
  })  : _chatProvider = chatProvider,
        _permissionService = permissionService,
        _imageService = imageService,
        _documentService = documentService,
        _speechService = speechService,
        _ttsService = ttsService {
    _initialize();
  }

  OllamaModel? _selectedModel;
  OllamaModel? get selectedModel => _selectedModel;

  List<ChatPreset> _presets = ChatPresets.randomPresets;
  List<ChatPreset> get presets => _presets;

  final TextEditingController textFieldController = TextEditingController();

  bool get hasText => textFieldController.text.trim().isNotEmpty;
  bool get canSend => hasText || hasAttachments;
  bool get supportsVoiceInput => Platform.isAndroid || Platform.isIOS;
  bool get voiceModeEnabled => Hive.box('settings').get('voiceModeEnabled', defaultValue: false) as bool;

  bool _isListening = false;
  bool get isListening => _isListening;

  bool _isVoiceConversationMode = false;
  bool get isVoiceConversationMode => _isVoiceConversationMode;
  bool get isVoiceConversationStarting =>
      (_voiceConversationListenStartInFlight || _voiceConversationWaitingForNativeListening) && !_isListening;

  VoiceConversationPhase _voiceConversationPhase = VoiceConversationPhase.idle;
  VoiceConversationPhase get voiceConversationPhase => _voiceConversationPhase;

  String get voiceConversationStatusLabel {
    if (isVoiceConversationStarting) {
      return 'Включаю микрофон';
    }

    switch (_voiceConversationPhase) {
      case VoiceConversationPhase.listening:
        return 'Слушаю';
      case VoiceConversationPhase.processing:
        return 'Жду ответ модели';
      case VoiceConversationPhase.speaking:
        return 'Озвучиваю ответ';
      case VoiceConversationPhase.idle:
        return 'Голосовой режим';
    }
  }

  String get voiceConversationStatusDescription {
    if (isVoiceConversationStarting) {
      return 'Подключаю распознавание речи. Слушаю только когда появится микрофон.';
    }

    switch (_voiceConversationPhase) {
      case VoiceConversationPhase.listening:
        return 'Скажи фразу, и я отправлю ее в чат автоматически.';
      case VoiceConversationPhase.processing:
        return 'Распознавание завершено, отправляю сообщение в Ollama.';
      case VoiceConversationPhase.speaking:
        return 'Ответ пришел, сейчас проговорю его вслух.';
      case VoiceConversationPhase.idle:
        return 'Включи голосовой режим, чтобы общаться без клавиатуры.';
    }
  }

  String _voiceDraftPrefix = '';
  String _voiceConversationDraft = '';
  String _voiceConversationSpokenText = '';
  String _voiceConversationAssistantEchoText = '';
  bool _voiceConversationTurnInFlight = false;
  bool _voiceConversationTtsActive = false;
  bool _voiceConversationListenStartInFlight = false;
  bool _voiceConversationWaitingForNativeListening = false;
  Timer? _voiceConversationFinalSendTimer;
  String _voiceConversationEchoGuardText = '';
  DateTime? _voiceConversationEchoGuardUntil;
  int _voiceConversationSession = 0;

  Future<void> Function()? _voiceConversationModelSelectionHandler;
  VoidCallback? _voiceConversationServerNotConfiguredHandler;
  ValueChanged<String>? _voiceConversationErrorHandler;

  late final AppLifecycleListener _appLifecycleListener;
  late final StreamSubscription _settingsSubscription;

  bool get isServerConfigured {
    return Hive.box('settings').get('serverAddress') != null;
  }

  String get currentVoiceDraft => textFieldController.text.trim();

  String get latestAssistantReply {
    return _lastAssistantMessage?.content.trim() ?? '';
  }

  void _initialize() {
    _chatProvider.addListener(_onChatProviderChanged);
    textFieldController.addListener(_onTextFieldChanged);

    _settingsSubscription = Hive.box('settings').watch().listen((event) {
      if (event.key == 'serverAddress') {
        _selectedModel = null;
      }
      notifyListeners();
    });

    _appLifecycleListener = AppLifecycleListener(onExitRequested: () async {
      await _imageService.deleteImages(imageFiles);
      await _speechService.cancelListening();
      await _ttsService.stop();
      return AppExitResponse.exit;
    });
  }

  void _onChatProviderChanged() {
    notifyListeners();
  }

  void _onTextFieldChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _chatProvider.removeListener(_onChatProviderChanged);
    textFieldController.removeListener(_onTextFieldChanged);
    textFieldController.dispose();
    _voiceConversationFinalSendTimer?.cancel();
    unawaited(_speechService.cancelListening());
    unawaited(_ttsService.stop());
    _appLifecycleListener.dispose();
    _settingsSubscription.cancel();
    super.dispose();
  }

  List<OllamaMessage> get messages => _chatProvider.messages;
  OllamaChat? get currentChat => _chatProvider.currentChat;
  bool get isStreaming => _chatProvider.isCurrentChatStreaming;
  bool get isThinking => _chatProvider.isCurrentChatThinking;
  OllamaException? get currentError => _chatProvider.currentChatError;

  void cancelStreaming() {
    _chatProvider.cancelCurrentStreaming();
  }

  Future<void> retryLastPrompt() async {
    await _chatProvider.retryLastPrompt();
  }

  Future<List<OllamaModel>> fetchAvailableModels() async {
    return _chatProvider.fetchAvailableModels();
  }

  void setSelectedModel(OllamaModel? model) {
    _selectedModel = model;
    notifyListeners();
  }

  void setTextFieldValue(String value) {
    textFieldController.text = value;
    textFieldController.selection = TextSelection.collapsed(offset: value.length);
  }

  String _takeTextFieldValue() {
    final value = textFieldController.text;
    textFieldController.clear();
    return value;
  }

  final List<File> _imageFiles = [];
  final List<DocumentAttachment> _documents = [];

  List<File> get imageFiles => List.unmodifiable(_imageFiles);
  List<DocumentAttachment> get documents => List.unmodifiable(_documents);
  bool get hasImageAttachments => _imageFiles.isNotEmpty;
  bool get hasDocumentAttachments => _documents.isNotEmpty;
  bool get hasAttachments => hasImageAttachments || hasDocumentAttachments;

  Future<void> pickImages({
    VoidCallback? onPermissionDenied,
    ImageSource source = ImageSource.gallery,
    int quality = ImageService.defaultImageQuality,
  }) async {
    final hasPermission = source == ImageSource.camera
        ? await _permissionService.requestCameraPermission(
            onDenied: onPermissionDenied,
          )
        : await _permissionService.requestPhotoPermission(
            onDenied: onPermissionDenied,
          );
    if (!hasPermission) return;

    final picker = ImagePicker();
    final pickedImage = await picker.pickImage(source: source);
    if (pickedImage == null) return;

    final compressedFile = await _imageService.compressAndSave(
      pickedImage.path,
      quality: quality,
    );

    if (compressedFile != null) {
      _imageFiles.add(compressedFile);
    } else {
      _imageFiles.add(File(''));
    }

    notifyListeners();
  }

  Future<void> removeImage(File imageFile) async {
    await _imageService.deleteImage(imageFile);
    _imageFiles.remove(imageFile);
    notifyListeners();
  }

  Future<void> pickDocuments({
    ValueChanged<String>? onError,
  }) async {
    try {
      final pickedDocuments = await _documentService.pickDocuments();
      if (pickedDocuments.isEmpty) {
        if (_documentService.lastSkippedDocuments.isNotEmpty) {
          onError?.call('Р¤Р°Р№Р» РЅРµ РїСЂРёРєСЂРµРїР»РµРЅ: ${_documentService.lastSkippedDocuments.first}');
        }
        return;
      }

      _documents.addAll(pickedDocuments);
      if (_documentService.lastSkippedDocuments.isNotEmpty) {
        onError?.call('Р§Р°СЃС‚СЊ С„Р°Р№Р»РѕРІ РїСЂРѕРїСѓС‰РµРЅР°: ${_documentService.lastSkippedDocuments.first}');
      }
      notifyListeners();
    } catch (error) {
      onError?.call('РќРµ СѓРґР°Р»РѕСЃСЊ РїСЂРѕС‡РёС‚Р°С‚СЊ РґРѕРєСѓРјРµРЅС‚: $error');
    }
  }

  void removeDocument(DocumentAttachment document) {
    _documents.remove(document);
    notifyListeners();
  }

  List<File> _takeImages() {
    final images = _imageFiles.toList();
    _imageFiles.clear();
    return images;
  }

  List<DocumentAttachment> _takeDocuments() {
    final documents = _documents.toList();
    _documents.clear();
    return documents;
  }

  String _buildPromptContext(List<DocumentAttachment> documents) {
    return _documentService.buildPromptContext(documents);
  }

  Future<void> toggleVoiceInput({
    required VoidCallback onPermissionDenied,
    required ValueChanged<String> onError,
  }) async {
    if (_isVoiceConversationMode) {
      await stopVoiceConversation();
    }

    if (!supportsVoiceInput) {
      onError('Р“РѕР»РѕСЃРѕРІРѕР№ РІРІРѕРґ РґРѕСЃС‚СѓРїРµРЅ С‚РѕР»СЊРєРѕ РЅР° Android Рё iOS.');
      return;
    }

    if (_isListening) {
      await stopVoiceInput();
      return;
    }

    final hasPermission = await _permissionService.requestMicrophonePermission(
      onDenied: onPermissionDenied,
    );
    if (!hasPermission) return;

    final isInitialized = await _speechService.initialize(
      onError: onError,
      onStatusChanged: _handleSpeechStatus,
    );
    if (!isInitialized) {
      onError(
          'РќРµ СѓРґР°Р»РѕСЃСЊ РёРЅРёС†РёР°Р»РёР·РёСЂРѕРІР°С‚СЊ РіРѕР»РѕСЃРѕРІРѕР№ РІРІРѕРґ РЅР° СЌС‚РѕРј СѓСЃС‚СЂРѕР№СЃС‚РІРµ.');
      return;
    }

    _voiceDraftPrefix = textFieldController.text.trim();

    final didStart = await _speechService.startListening(
      onResult: _handleSpeechResult,
      onError: onError,
    );
    if (!didStart) {
      _voiceDraftPrefix = '';
      onError('РќРµ СѓРґР°Р»РѕСЃСЊ Р·Р°РїСѓСЃС‚РёС‚СЊ РіРѕР»РѕСЃРѕРІРѕР№ РІРІРѕРґ.');
      return;
    }

    _isListening = true;
    notifyListeners();
  }

  Future<void> stopVoiceInput() async {
    await _speechService.stopListening();
    _setListening(false);
  }

  Future<void> toggleVoiceConversation({
    required Future<void> Function() onModelSelectionRequired,
    required VoidCallback onServerNotConfigured,
    required VoidCallback onPermissionDenied,
    required ValueChanged<String> onError,
  }) async {
    if (_isVoiceConversationMode) {
      await stopVoiceConversation();
      return;
    }

    if (!supportsVoiceInput) {
      onError('Р“РѕР»РѕСЃРѕРІРѕР№ СЂРµР¶РёРј РґРѕСЃС‚СѓРїРµРЅ С‚РѕР»СЊРєРѕ РЅР° Android Рё iOS.');
      return;
    }

    if (!isServerConfigured) {
      onServerNotConfigured();
      return;
    }

    if (currentChat == null && _selectedModel == null) {
      await onModelSelectionRequired();
      if (_selectedModel == null) {
        return;
      }
    }

    final hasPermission = await _permissionService.requestMicrophonePermission(
      onDenied: onPermissionDenied,
    );
    if (!hasPermission) return;

    final isSpeechInitialized = await _speechService.initialize(
      onError: onError,
      onStatusChanged: _handleVoiceConversationSpeechStatus,
    );
    if (!isSpeechInitialized) {
      onError(
          'РќРµ СѓРґР°Р»РѕСЃСЊ РїРѕРґРіРѕС‚РѕРІРёС‚СЊ СЂР°СЃРїРѕР·РЅР°РІР°РЅРёРµ СЂРµС‡Рё РґР»СЏ РіРѕР»РѕСЃРѕРІРѕРіРѕ СЂРµР¶РёРјР°.');
      return;
    }

    try {
      await _ttsService.initialize();
    } catch (error) {
      onError('РќРµ СѓРґР°Р»РѕСЃСЊ РїРѕРґРіРѕС‚РѕРІРёС‚СЊ СЃРёРЅС‚РµР· СЂРµС‡Рё: $error');
      return;
    }

    if (_isListening) {
      await _speechService.cancelListening();
      _setListening(false);
    }

    _voiceConversationModelSelectionHandler = onModelSelectionRequired;
    _voiceConversationServerNotConfiguredHandler = onServerNotConfigured;
    _voiceConversationErrorHandler = onError;
    _voiceConversationTurnInFlight = false;
    _voiceConversationDraft = '';
    _voiceConversationSpokenText = '';
    _voiceConversationAssistantEchoText = '';
    _voiceConversationTtsActive = false;
    _voiceConversationListenStartInFlight = false;
    _voiceConversationWaitingForNativeListening = false;
    _voiceConversationFinalSendTimer?.cancel();
    _voiceConversationFinalSendTimer = null;
    _voiceConversationEchoGuardText = '';
    _voiceConversationEchoGuardUntil = null;
    _isVoiceConversationMode = true;
    _voiceConversationSession += 1;
    _setVoiceConversationPhase(VoiceConversationPhase.listening, shouldNotify: false);
    notifyListeners();

    await _startVoiceConversationListening(_voiceConversationSession);
  }

  Future<void> stopVoiceConversation() async {
    _isVoiceConversationMode = false;
    _voiceConversationTurnInFlight = false;
    _voiceConversationDraft = '';
    _voiceConversationSpokenText = '';
    _voiceConversationAssistantEchoText = '';
    _voiceConversationTtsActive = false;
    _voiceConversationListenStartInFlight = false;
    _voiceConversationWaitingForNativeListening = false;
    _voiceConversationFinalSendTimer?.cancel();
    _voiceConversationFinalSendTimer = null;
    _voiceConversationEchoGuardText = '';
    _voiceConversationEchoGuardUntil = null;
    _voiceConversationModelSelectionHandler = null;
    _voiceConversationServerNotConfiguredHandler = null;
    _voiceConversationErrorHandler = null;
    _voiceConversationSession += 1;

    await _speechService.cancelListening();
    await _ttsService.stop();

    _setListening(false);
    _setVoiceConversationPhase(VoiceConversationPhase.idle, shouldNotify: false);
    notifyListeners();
  }

  Future<bool> sendMessage({
    required Future<void> Function() onModelSelectionRequired,
    required void Function() onServerNotConfigured,
  }) async {
    final draftPrompt = textFieldController.text.trim();

    if ((draftPrompt.isEmpty && !hasAttachments) || isStreaming) {
      return false;
    }

    final promptToSend = draftPrompt.isEmpty ? 'РР·СѓС‡Рё РїСЂРёРєСЂРµРїР»РµРЅРЅС‹Рµ С„Р°Р№Р»С‹.' : draftPrompt;
    final draftImages = _imageFiles.toList();
    final draftDocuments = _documents.toList();
    final hiddenContext = _buildPromptContext(draftDocuments);

    if (_isListening) {
      await stopVoiceInput();
    }

    if (!isServerConfigured) {
      onServerNotConfigured();
      return false;
    }

    if (_chatProvider.currentChat == null) {
      if (_selectedModel == null) {
        await onModelSelectionRequired();
      }

      if (_selectedModel == null) {
        return false;
      }

      _takeTextFieldValue();
      _takeImages();
      _takeDocuments();

      await _chatProvider.createNewChat(_selectedModel!);
      _presets = ChatPresets.randomPresets;

      notifyListeners();

      await _chatProvider.sendPrompt(
        promptToSend,
        images: draftImages,
        documents: draftDocuments,
        hiddenContext: hiddenContext,
      );
      unawaited(_chatProvider.generateTitleForCurrentChat());
    } else {
      _takeTextFieldValue();
      _takeImages();
      _takeDocuments();

      notifyListeners();

      await _chatProvider.sendPrompt(
        promptToSend,
        images: draftImages,
        documents: draftDocuments,
        hiddenContext: hiddenContext,
      );
    }

    return true;
  }

  void _handleSpeechResult(String recognizedText, bool isFinal) {
    final mergedText = _mergeVoiceDraft(recognizedText);
    textFieldController.value = textFieldController.value.copyWith(
      text: mergedText,
      selection: TextSelection.collapsed(offset: mergedText.length),
      composing: TextRange.empty,
    );

    if (isFinal) {
      _setListening(false);
    }
  }

  void _handleSpeechStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      _setListening(false);
    }
  }

  Future<void> _startVoiceConversationListening(
    int session, {
    bool keepCurrentPhase = false,
    bool allowCurrentPhase = false,
  }) async {
    if (!_isCurrentVoiceConversationSession(session) ||
        _voiceConversationListenStartInFlight ||
        _voiceConversationTurnInFlight ||
        _voiceConversationTtsActive ||
        (!allowCurrentPhase && _voiceConversationPhase != VoiceConversationPhase.listening)) {
      return;
    }

    _voiceConversationListenStartInFlight = true;
    try {
      _voiceConversationFinalSendTimer?.cancel();
      _voiceConversationFinalSendTimer = null;
      _voiceConversationDraft = '';
      await _speechService.cancelListening();
      _voiceConversationWaitingForNativeListening = true;
      notifyListeners();

      if (!_isCurrentVoiceConversationSession(session) ||
          (!allowCurrentPhase && _voiceConversationPhase != VoiceConversationPhase.listening) ||
          _voiceConversationTurnInFlight ||
          _voiceConversationTtsActive) {
        _voiceConversationWaitingForNativeListening = false;
        return;
      }

      final didStart = await _speechService.startListening(
        onResult: (recognizedText, isFinal) {
          _handleVoiceConversationSpeechResult(session, recognizedText, isFinal);
        },
        onError: (message) {
          _handleVoiceConversationSpeechError(session, message);
        },
        listenMode: ListenMode.dictation,
        partialResults: true,
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(seconds: 90),
        cancelOnError: false,
      );

      if (!didStart) {
        _voiceConversationWaitingForNativeListening = false;
        _setListening(false);
        if (_canRestartVoiceConversationListening) {
          unawaited(_restartVoiceConversationListening(
            session,
            keepCurrentPhase: false,
            delay: const Duration(milliseconds: 1500),
          ));
        }
        return;
      }

      // Android can report a successful start before the microphone is ready.
      // The UI switches to "listening" only from the native status callback.
    } finally {
      _voiceConversationListenStartInFlight = false;
    }
  }

  void _handleVoiceConversationSpeechResult(int session, String recognizedText, bool isFinal) {
    if (!_isCurrentVoiceConversationSession(session)) return;

    _voiceConversationFinalSendTimer?.cancel();
    _voiceConversationFinalSendTimer = null;

    final normalizedText = recognizedText.trim();
    if (_voiceConversationTurnInFlight ||
        _voiceConversationPhase == VoiceConversationPhase.processing ||
        _voiceConversationPhase == VoiceConversationPhase.speaking ||
        _voiceConversationTtsActive) {
      _voiceConversationDraft = '';
      return;
    }

    if (normalizedText.isNotEmpty && _looksLikeTtsEcho(normalizedText)) {
      _voiceConversationDraft = '';
      return;
    }

    _voiceConversationDraft = normalizedText;

    if (normalizedText.isNotEmpty) {
      textFieldController.value = textFieldController.value.copyWith(
        text: normalizedText,
        selection: TextSelection.collapsed(offset: normalizedText.length),
        composing: TextRange.empty,
      );
    }

    if (!isFinal || _voiceConversationTurnInFlight) {
      return;
    }

    _voiceConversationFinalSendTimer = Timer(const Duration(milliseconds: 900), () {
      if (!_isCurrentVoiceConversationSession(session) || _voiceConversationTurnInFlight) {
        return;
      }

      final finalText = _voiceConversationDraft.trim();
      if (finalText.isEmpty) {
        return;
      }

      _voiceConversationTurnInFlight = true;
      _setListening(false);
      _voiceConversationSession += 1;
      unawaited(_processVoiceConversationTurn(_voiceConversationSession, finalText));
    });
  }

  void _handleVoiceConversationSpeechError(int session, String message) {
    if (!_isCurrentVoiceConversationSession(session)) return;

    _voiceConversationFinalSendTimer?.cancel();
    _voiceConversationFinalSendTimer = null;

    if (_isQuietSpeechError(message)) {
      _voiceConversationDraft = '';
      _voiceConversationWaitingForNativeListening = false;
      _setListening(false);

      if (_canRestartVoiceConversationListening) {
        unawaited(_restartVoiceConversationListening(
          session,
          keepCurrentPhase: false,
        ));
      }

      return;
    }

    _voiceConversationErrorHandler?.call(message);
    _voiceConversationWaitingForNativeListening = false;
    _voiceConversationTurnInFlight = false;
    _setListening(false);
    unawaited(_restartVoiceConversationListening(session));
  }

  void _handleVoiceConversationSpeechStatus(String status) {
    if (!_isVoiceConversationMode) {
      if (status == 'done' || status == 'notListening') {
        _setListening(false);
      }
      return;
    }

    if (status == 'listening') {
      if (!_voiceConversationTurnInFlight && !_voiceConversationTtsActive) {
        _voiceConversationWaitingForNativeListening = false;
        _setVoiceConversationPhase(VoiceConversationPhase.listening, shouldNotify: false);
        _setListening(true);
      }
      return;
    }

    if (status == 'done' || status == 'notListening') {
      _voiceConversationWaitingForNativeListening = false;
      _setListening(false);

      if (_canRestartVoiceConversationListening && _voiceConversationDraft.isEmpty) {
        unawaited(_restartVoiceConversationListening(
          _voiceConversationSession,
          keepCurrentPhase: false,
        ));
      }
    }
  }

  Future<void> _processVoiceConversationTurn(int session, String prompt) async {
    final normalizedPrompt = prompt.trim();
    if (!_isCurrentVoiceConversationSession(session)) return;

    if (normalizedPrompt.isEmpty) {
      _voiceConversationTurnInFlight = false;
      await _restartVoiceConversationListening(session);
      return;
    }

    _setVoiceConversationPhase(VoiceConversationPhase.processing);
    await _speechService.cancelListening();
    _setListening(false);
    setTextFieldValue(normalizedPrompt);

    final shouldSpeakReplies = Hive.box('settings').get('voiceReplyEnabled', defaultValue: true) as bool;
    var pendingSpeech = '';
    var consumedTextLength = 0;
    var queuedAnySpeech = false;
    Future<void> speechQueue = Future.value();

    void queueSpeechSegment(String segment) {
      final normalizedSegment = segment.trim();
      if (normalizedSegment.isEmpty) {
        return;
      }

      queuedAnySpeech = true;
      _voiceConversationSpokenText = [
        _voiceConversationSpokenText,
        normalizedSegment,
      ].where((part) => part.trim().isNotEmpty).join(' ');

      speechQueue = speechQueue.then((_) async {
        if (!_isCurrentVoiceConversationSession(session)) {
          return;
        }

        _setVoiceConversationPhase(VoiceConversationPhase.speaking);

        if (_isListening) {
          await _speechService.cancelListening();
          _setListening(false);
        }

        if (!_isCurrentVoiceConversationSession(session)) {
          return;
        }

        try {
          _rememberVoiceConversationEcho(
            normalizedSegment,
            const Duration(seconds: 4),
          );
          _voiceConversationTtsActive = true;
          await _ttsService.speakQueued(normalizedSegment);
        } catch (error) {
          if (_isCurrentVoiceConversationSession(session)) {
            _voiceConversationErrorHandler?.call('РќРµ СѓРґР°Р»РѕСЃСЊ РѕР·РІСѓС‡РёС‚СЊ РѕС‚РІРµС‚: $error');
          }
        } finally {
          if (_isCurrentVoiceConversationSession(session)) {
            _voiceConversationTtsActive = false;
            _rememberVoiceConversationEcho(
              _voiceConversationAssistantEchoText,
              const Duration(milliseconds: 2200),
            );
          }
        }
      });
    }

    void handleAssistantStream(OllamaMessage message) {
      if (!_isCurrentVoiceConversationSession(session)) {
        return;
      }

      final content = message.content;
      _voiceConversationAssistantEchoText = content;

      if (!shouldSpeakReplies || content.length <= consumedTextLength) {
        return;
      }

      pendingSpeech += content.substring(consumedTextLength);
      consumedTextLength = content.length;

      final split = _splitSpeakableSpeech(pendingSpeech, force: false);
      pendingSpeech = split.rest;

      for (final segment in split.segments) {
        queueSpeechSegment(segment);
      }
    }

    final assistantMessage = await _sendVoiceConversationPrompt(
      normalizedPrompt,
      onAssistantMessageChanged: handleAssistantStream,
    );

    if (!_isCurrentVoiceConversationSession(session)) return;

    if (assistantMessage != null && shouldSpeakReplies) {
      final finalContent = assistantMessage.content;
      _voiceConversationAssistantEchoText = finalContent;

      if (finalContent.length > consumedTextLength) {
        pendingSpeech += finalContent.substring(consumedTextLength);
        consumedTextLength = finalContent.length;
      }

      final split = _splitSpeakableSpeech(pendingSpeech, force: true);
      pendingSpeech = split.rest;

      for (final segment in split.segments) {
        queueSpeechSegment(segment);
      }
    }

    if (queuedAnySpeech) {
      await speechQueue;
    }

    if (!_isCurrentVoiceConversationSession(session)) return;

    _voiceConversationTurnInFlight = false;
    _voiceConversationSpokenText = '';
    _voiceConversationAssistantEchoText = '';
    await _startVoiceConversationListening(
      session,
      allowCurrentPhase: true,
    );
  }

  Future<OllamaMessage?> _sendVoiceConversationPrompt(
    String prompt, {
    required ValueChanged<OllamaMessage> onAssistantMessageChanged,
  }) async {
    final draftPrompt = prompt.trim();

    if ((draftPrompt.isEmpty && !hasAttachments) || isStreaming) {
      return null;
    }

    final promptToSend = draftPrompt.isEmpty ? 'РР·СѓС‡Рё РїСЂРёРєСЂРµРїР»РµРЅРЅС‹Рµ С„Р°Р№Р»С‹.' : draftPrompt;
    final draftImages = _imageFiles.toList();
    final draftDocuments = _documents.toList();
    final hiddenContext = _buildPromptContext(draftDocuments);

    if (!isServerConfigured) {
      _voiceConversationServerNotConfiguredHandler?.call();
      return null;
    }

    var shouldGenerateTitle = false;

    if (_chatProvider.currentChat == null) {
      if (_selectedModel == null) {
        await (_voiceConversationModelSelectionHandler ?? () async {})();
      }

      if (_selectedModel == null) {
        return null;
      }

      _takeTextFieldValue();
      _takeImages();
      _takeDocuments();

      await _chatProvider.createNewChat(_selectedModel!);
      _presets = ChatPresets.randomPresets;
      shouldGenerateTitle = true;

      notifyListeners();
    } else {
      _takeTextFieldValue();
      _takeImages();
      _takeDocuments();

      notifyListeners();
    }

    final assistantMessage = await _chatProvider.sendPromptWithAssistantStream(
      promptToSend,
      images: draftImages,
      documents: draftDocuments,
      hiddenContext: hiddenContext,
      onAssistantMessageChanged: onAssistantMessageChanged,
    );

    if (shouldGenerateTitle) {
      unawaited(_chatProvider.generateTitleForCurrentChat());
    }

    return assistantMessage;
  }

  Future<void> _restartVoiceConversationListening(
    int session, {
    bool keepCurrentPhase = false,
    Duration? delay,
  }) async {
    if (!_isCurrentVoiceConversationSession(session)) {
      return;
    }

    final restartDelay = delay ??
        (_voiceConversationPhase == VoiceConversationPhase.speaking ||
                _voiceConversationPhase == VoiceConversationPhase.processing
            ? const Duration(milliseconds: 300)
            : const Duration(milliseconds: 450));
    await Future<void>.delayed(restartDelay);

    if (!_isCurrentVoiceConversationSession(session) ||
        _isListening ||
        _voiceConversationPhase != VoiceConversationPhase.listening ||
        _voiceConversationTurnInFlight ||
        _voiceConversationTtsActive) {
      return;
    }

    await _startVoiceConversationListening(session, keepCurrentPhase: keepCurrentPhase);
  }

  bool _isQuietSpeechError(String message) {
    final normalized = message.toLowerCase().trim();
    return normalized.contains('error_') ||
        normalized.startsWith('error ') ||
        normalized.contains('busy') ||
        normalized.contains('error_no_match') ||
        normalized.contains('error_no_mach') ||
        normalized.contains('error_speech_timeout') ||
        normalized.contains('error_client') ||
        normalized.contains('error_busy') ||
        normalized.contains('no_match') ||
        normalized.contains('speech_timeout');
  }

  bool _looksLikeTtsEcho(String recognizedText) {
    final spoken = _normalizeSpeechComparable(
      [
        _voiceConversationSpokenText,
        _voiceConversationAssistantEchoText,
        if (_isVoiceConversationEchoGuardActive) _voiceConversationEchoGuardText,
      ].join(' '),
    );
    final recognized = _normalizeSpeechComparable(recognizedText);

    if (spoken.isEmpty || recognized.length < 6) {
      return false;
    }

    if (spoken.contains(recognized)) {
      return true;
    }

    final recognizedWords = recognized.split(' ').where((word) => word.length > 2).toList();
    if (recognizedWords.length < 2) {
      return false;
    }

    final matchingWords = recognizedWords.where(spoken.contains).length;
    return matchingWords / recognizedWords.length >= 0.75;
  }

  ({List<String> segments, String rest}) _splitSpeakableSpeech(String text, {required bool force}) {
    var rest = text.replaceAll(RegExp(r'\s+'), ' ');
    final segments = <String>[];

    while (rest.trim().isNotEmpty) {
      rest = rest.trimLeft();

      final sentenceMatch = RegExp(r'[.!?вЂ¦]\s+').firstMatch(rest);
      if (sentenceMatch != null && sentenceMatch.end >= 18) {
        segments.add(rest.substring(0, sentenceMatch.end).trim());
        rest = rest.substring(sentenceMatch.end);
        continue;
      }

      final softPauseMatch = RegExp(r'[,;:]\s+').firstMatch(rest);
      if (softPauseMatch != null && softPauseMatch.end >= 28) {
        segments.add(rest.substring(0, softPauseMatch.end).trim());
        rest = rest.substring(softPauseMatch.end);
        continue;
      }

      if (rest.length >= 40) {
        final splitAt = rest.lastIndexOf(' ', 40);
        if (splitAt >= 22) {
          segments.add(rest.substring(0, splitAt).trim());
          rest = rest.substring(splitAt + 1);
          continue;
        }
      }

      if (force) {
        final segment = rest.trim();
        if (segment.isNotEmpty) {
          segments.add(segment);
        }
        rest = '';
      }

      break;
    }

    return (segments: segments, rest: rest);
  }

  String _normalizeSpeechComparable(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^Р°-СЏС‘a-z0-9 ]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _mergeVoiceDraft(String recognizedText) {
    final normalizedVoiceText = recognizedText.trim();
    if (_voiceDraftPrefix.isEmpty) {
      return normalizedVoiceText;
    }

    if (normalizedVoiceText.isEmpty) {
      return _voiceDraftPrefix;
    }

    return '$_voiceDraftPrefix $normalizedVoiceText';
  }

  void _setListening(bool value) {
    if (_isListening == value) return;

    _isListening = value;
    if (!value) {
      _voiceDraftPrefix = '';
    }
    notifyListeners();
  }

  void _setVoiceConversationPhase(VoiceConversationPhase value, {bool shouldNotify = true}) {
    if (_voiceConversationPhase == value) return;

    _voiceConversationPhase = value;
    if (shouldNotify) {
      notifyListeners();
    }
  }

  bool _isCurrentVoiceConversationSession(int session) {
    return _isVoiceConversationMode && _voiceConversationSession == session;
  }

  bool get _canRestartVoiceConversationListening {
    return _isVoiceConversationMode &&
        !_voiceConversationTurnInFlight &&
        !_voiceConversationTtsActive &&
        _voiceConversationPhase != VoiceConversationPhase.processing &&
        _voiceConversationPhase != VoiceConversationPhase.speaking;
  }

  bool get _isVoiceConversationEchoGuardActive {
    final guardUntil = _voiceConversationEchoGuardUntil;
    return guardUntil != null && DateTime.now().isBefore(guardUntil);
  }

  void _rememberVoiceConversationEcho(String text, Duration ttl) {
    final normalized = _normalizeSpeechComparable(text);
    if (normalized.isEmpty) {
      return;
    }

    final combined = [
      if (_isVoiceConversationEchoGuardActive) _voiceConversationEchoGuardText,
      normalized,
    ].where((part) => part.trim().isNotEmpty).join(' ');

    _voiceConversationEchoGuardText = combined.length > 900 ? combined.substring(combined.length - 900) : combined;
    _voiceConversationEchoGuardUntil = DateTime.now().add(ttl);
  }

  OllamaMessage? get _lastAssistantMessage {
    for (final message in _chatProvider.messages.reversed) {
      if (message.role == OllamaMessageRole.assistant) {
        return message;
      }
    }

    return null;
  }
}

enum VoiceConversationPhase {
  idle,
  listening,
  processing,
  speaking,
}
