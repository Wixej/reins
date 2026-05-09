import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:reins/Models/ollama_chat.dart';
import 'package:reins/Models/document_attachment.dart';
import 'package:reins/Models/ollama_exception.dart';
import 'package:reins/Models/ollama_message.dart';
import 'package:reins/Models/ollama_model.dart';
import 'package:reins/Pages/chat_page/chat_page_view_model.dart';
import 'package:reins/Providers/chat_provider.dart';
import 'package:reins/Services/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeChatProvider fakeChatProvider;
  late FakePermissionService fakePermissionService;
  late FakeImageService fakeImageService;
  late FakeDocumentService fakeDocumentService;
  late FakeSpeechService fakeSpeechService;
  late FakeOfflineAiAsrService fakeOfflineAiAsrService;
  late FakeTtsService fakeTtsService;
  late ChatPageViewModel viewModel;

  setUpAll(() async {
    // Setup fake path provider for Hive
    PathProviderPlatform.instance = FakePathProviderPlatform();

    // Initialize Hive for testing
    final testDir = path.join(Directory.current.path, 'test', 'assets');
    Hive.init(testDir);
    await Hive.openBox('settings');
  });

  setUp(() async {
    fakeChatProvider = FakeChatProvider();
    fakePermissionService = FakePermissionService();
    fakeImageService = FakeImageService();
    fakeDocumentService = FakeDocumentService();
    fakeSpeechService = FakeSpeechService();
    fakeOfflineAiAsrService = FakeOfflineAiAsrService();
    fakeTtsService = FakeTtsService();

    // Ensure server is configured for most tests
    await Hive.box('settings').put('serverAddress', 'http://localhost:11434');

    viewModel = ChatPageViewModel(
      chatProvider: fakeChatProvider,
      permissionService: fakePermissionService,
      imageService: fakeImageService,
      documentService: fakeDocumentService,
      speechService: fakeSpeechService,
      offlineAiAsrService: fakeOfflineAiAsrService,
      ttsService: fakeTtsService,
    );
  });

  tearDown(() {
    viewModel.dispose();
  });

  tearDownAll(() async {
    await Hive.close();
  });

  group('Initial State', () {
    test('selectedModel should be null initially', () {
      expect(viewModel.selectedModel, isNull);
    });

    test('presets should not be empty', () {
      expect(viewModel.presets, isNotEmpty);
    });

    test('hasText should be false initially', () {
      expect(viewModel.hasText, isFalse);
    });

    test('imageFiles should be empty initially', () {
      expect(viewModel.imageFiles, isEmpty);
    });

    test('hasImageAttachments should be false initially', () {
      expect(viewModel.hasImageAttachments, isFalse);
    });
  });

  group('Model Selection', () {
    test('setSelectedModel should update selectedModel', () {
      final model = createTestModel('llama3.2');

      viewModel.setSelectedModel(model);

      expect(viewModel.selectedModel, model);
    });

    test('setSelectedModel should notify listeners', () {
      final model = createTestModel('llama3.2');
      var notified = false;
      viewModel.addListener(() => notified = true);

      viewModel.setSelectedModel(model);

      expect(notified, isTrue);
    });

    test('setSelectedModel with null should clear selection', () {
      final model = createTestModel('llama3.2');
      viewModel.setSelectedModel(model);

      viewModel.setSelectedModel(null);

      expect(viewModel.selectedModel, isNull);
    });
  });

  group('Text Field', () {
    test('setTextFieldValue should update text field', () {
      viewModel.setTextFieldValue('Hello');

      expect(viewModel.textFieldController.text, 'Hello');
    });

    test('hasText should return true when text field has content', () {
      viewModel.setTextFieldValue('Hello');

      expect(viewModel.hasText, isTrue);
    });

    test('hasText should return false for whitespace only', () {
      viewModel.setTextFieldValue('   ');

      expect(viewModel.hasText, isFalse);
    });

    test('textFieldController changes should notify listeners', () {
      var notifyCount = 0;
      viewModel.addListener(() => notifyCount++);

      viewModel.textFieldController.text = 'Test';

      expect(notifyCount, 1);
    });
  });

  group('ChatProvider State (Proxied)', () {
    test('messages should proxy ChatProvider messages', () {
      final messages = [
        OllamaMessage('Hello', role: OllamaMessageRole.user),
      ];
      fakeChatProvider.setMessages(messages);

      expect(viewModel.messages, messages);
    });

    test('currentChat should proxy ChatProvider currentChat', () {
      final chat = createTestChat('test-id');
      fakeChatProvider.setCurrentChat(chat);

      expect(viewModel.currentChat, chat);
    });

    test('isStreaming should proxy ChatProvider isCurrentChatStreaming', () {
      fakeChatProvider.setIsStreaming(true);

      expect(viewModel.isStreaming, isTrue);
    });

    test('isThinking should proxy ChatProvider isCurrentChatThinking', () {
      fakeChatProvider.setIsThinking(true);

      expect(viewModel.isThinking, isTrue);
    });

    test('currentError should proxy ChatProvider currentChatError', () {
      final error = OllamaException('Test error');
      fakeChatProvider.setCurrentError(error);

      expect(viewModel.currentError, error);
    });

    test('ChatProvider changes should notify ViewModel listeners', () {
      var notified = false;
      viewModel.addListener(() => notified = true);

      fakeChatProvider.triggerNotifyListeners();

      expect(notified, isTrue);
    });
  });

  group('ChatProvider Actions (Delegated)', () {
    test('cancelStreaming should delegate to ChatProvider', () {
      viewModel.cancelStreaming();

      expect(fakeChatProvider.cancelStreamingCalled, isTrue);
    });

    test('retryLastPrompt should delegate to ChatProvider', () async {
      await viewModel.retryLastPrompt();

      expect(fakeChatProvider.retryLastPromptCalled, isTrue);
    });

    test('fetchAvailableModels should delegate to ChatProvider', () async {
      final models = [createTestModel('llama3.2')];
      fakeChatProvider.setAvailableModels(models);

      final result = await viewModel.fetchAvailableModels();

      expect(result, models);
    });
  });

  group('sendMessage', () {
    test('should return false when text field is empty', () async {
      final result = await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );

      expect(result, isFalse);
    });

    test('should return false when currently streaming', () async {
      viewModel.setTextFieldValue('Hello');
      fakeChatProvider.setIsStreaming(true);

      final result = await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );

      expect(result, isFalse);
    });

    test('should call onServerNotConfigured when server not configured', () async {
      await Hive.box('settings').delete('serverAddress');
      viewModel.setTextFieldValue('Hello');
      var serverNotConfiguredCalled = false;

      final result = await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () => serverNotConfiguredCalled = true,
      );

      expect(result, isFalse);
      expect(serverNotConfiguredCalled, isTrue);
    });

    test('should call onModelSelectionRequired when no model selected and no current chat', () async {
      viewModel.setTextFieldValue('Hello');
      var modelSelectionCalled = false;

      await viewModel.sendMessage(
        onModelSelectionRequired: () async {
          modelSelectionCalled = true;
        },
        onServerNotConfigured: () {},
      );

      expect(modelSelectionCalled, isTrue);
    });

    test('should return false if no model selected after selection callback', () async {
      viewModel.setTextFieldValue('Hello');

      final result = await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );

      expect(result, isFalse);
    });

    test('should create new chat and send message when model selected', () async {
      viewModel.setTextFieldValue('Hello');
      final model = createTestModel('llama3.2');
      viewModel.setSelectedModel(model);

      final result = await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );

      expect(result, isTrue);
      expect(fakeChatProvider.createNewChatCalled, isTrue);
      expect(fakeChatProvider.sendPromptCalled, isTrue);
      expect(fakeChatProvider.generateTitleCalled, isTrue);
    });

    test('should preserve first prompt when chat creation triggers input reset', () async {
      viewModel.setTextFieldValue('Hello after keep alive change');
      viewModel.setSelectedModel(createTestModel('llama3.2'));
      fakeChatProvider.onCreateNewChat = () {
        viewModel.textFieldController.clear();
      };

      final result = await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );

      expect(result, isTrue);
      expect(fakeChatProvider.lastSentPrompt, 'Hello after keep alive change');
    });

    test('should preserve draft across model selection callback before first send', () async {
      viewModel.setTextFieldValue('Prompt should survive model picker');

      final result = await viewModel.sendMessage(
        onModelSelectionRequired: () async {
          viewModel.textFieldController.clear();
          viewModel.setSelectedModel(createTestModel('llama3.2'));
        },
        onServerNotConfigured: () {},
      );

      expect(result, isTrue);
      expect(fakeChatProvider.lastSentPrompt, 'Prompt should survive model picker');
    });

    test('should clear text field after sending', () async {
      viewModel.setTextFieldValue('Hello');
      viewModel.setSelectedModel(createTestModel('llama3.2'));

      await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );

      expect(viewModel.textFieldController.text, isEmpty);
    });

    test('should send message directly when current chat exists', () async {
      viewModel.setTextFieldValue('Hello');
      fakeChatProvider.setCurrentChat(createTestChat('test-id'));

      final result = await viewModel.sendMessage(
        onModelSelectionRequired: () async {},
        onServerNotConfigured: () {},
      );

      expect(result, isTrue);
      expect(fakeChatProvider.createNewChatCalled, isFalse);
      expect(fakeChatProvider.sendPromptCalled, isTrue);
      expect(fakeChatProvider.generateTitleCalled, isFalse);
    });
  });

  group('isServerConfigured', () {
    test('should return true when serverAddress is set', () {
      expect(viewModel.isServerConfigured, isTrue);
    });

    test('should return false when serverAddress is null', () async {
      await Hive.box('settings').delete('serverAddress');

      expect(viewModel.isServerConfigured, isFalse);
    });
  });
}

// ============================================================
// Test Helpers
// ============================================================

OllamaModel createTestModel(String name) {
  return OllamaModel(
    name: name,
    model: name,
    modifiedAt: DateTime.now(),
    size: 1000,
    digest: 'test-digest-$name',
    parameterSize: '1B',
  );
}

OllamaChat createTestChat(String id) {
  return OllamaChat(
    id: id,
    model: 'llama3.2',
    title: 'Test Chat',
    options: OllamaChatOptions(),
    systemPrompt: null,
  );
}

// ============================================================
// Fake Classes
// ============================================================

class FakeChatProvider extends ChangeNotifier implements ChatProvider {
  List<OllamaMessage> _messages = [];
  OllamaChat? _currentChat;
  bool _isStreaming = false;
  bool _isThinking = false;
  OllamaException? _currentError;
  List<OllamaModel> _availableModels = [];

  bool cancelStreamingCalled = false;
  bool retryLastPromptCalled = false;
  bool createNewChatCalled = false;
  bool sendPromptCalled = false;
  bool generateTitleCalled = false;
  VoidCallback? onCreateNewChat;
  String? lastSentPrompt;
  List<File>? lastSentImages;

  void setMessages(List<OllamaMessage> messages) {
    _messages = messages;
  }

  void setCurrentChat(OllamaChat? chat) {
    _currentChat = chat;
  }

  void setIsStreaming(bool value) {
    _isStreaming = value;
  }

  void setIsThinking(bool value) {
    _isThinking = value;
  }

  void setCurrentError(OllamaException? error) {
    _currentError = error;
  }

  void setAvailableModels(List<OllamaModel> models) {
    _availableModels = models;
  }

  void triggerNotifyListeners() {
    notifyListeners();
  }

  @override
  List<OllamaMessage> get messages => _messages;

  @override
  OllamaChat? get currentChat => _currentChat;

  @override
  bool get isCurrentChatStreaming => _isStreaming;

  @override
  bool get isCurrentChatThinking => _isThinking;

  @override
  OllamaException? get currentChatError => _currentError;

  @override
  void cancelCurrentStreaming() {
    cancelStreamingCalled = true;
  }

  @override
  Future<void> retryLastPrompt() async {
    retryLastPromptCalled = true;
  }

  @override
  Future<List<OllamaModel>> fetchAvailableModels() async {
    return _availableModels;
  }

  @override
  Future<void> createNewChat(OllamaModel model) async {
    createNewChatCalled = true;
    onCreateNewChat?.call();
    _currentChat = createTestChat('new-chat-id');
  }

  @override
  Future<void> sendPrompt(
    String prompt, {
    List<File>? images,
    List<DocumentAttachment>? documents,
    String? hiddenContext,
  }) async {
    sendPromptCalled = true;
    lastSentPrompt = prompt;
    lastSentImages = images;
  }

  @override
  Future<void> generateTitleForCurrentChat() async {
    generateTitleCalled = true;
  }

  // Unused ChatProvider methods - stub implementations
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePermissionService implements PermissionService {
  bool shouldGrantPermission = true;
  bool permissionRequested = false;
  bool cameraPermissionRequested = false;
  bool microphonePermissionRequested = false;

  @override
  Future<bool> requestPhotoPermission({VoidCallback? onDenied}) async {
    permissionRequested = true;
    if (!shouldGrantPermission) {
      onDenied?.call();
    }
    return shouldGrantPermission;
  }

  @override
  Future<bool> requestCameraPermission({VoidCallback? onDenied}) async {
    cameraPermissionRequested = true;
    if (!shouldGrantPermission) {
      onDenied?.call();
    }
    return shouldGrantPermission;
  }

  @override
  Future<bool> requestMicrophonePermission({VoidCallback? onDenied}) async {
    microphonePermissionRequested = true;
    if (!shouldGrantPermission) {
      onDenied?.call();
    }
    return shouldGrantPermission;
  }
}

class FakeImageService implements ImageService {
  List<File> deletedImages = [];
  File? compressedFile;

  @override
  Future<File?> compressAndSave(
    String sourcePath, {
    int quality = ImageService.defaultImageQuality,
    int minWidth = ImageService.defaultMinImageWidth,
    int minHeight = ImageService.defaultMinImageHeight,
  }) async {
    return compressedFile;
  }

  @override
  Future<void> deleteImage(File imageFile) async {
    deletedImages.add(imageFile);
  }

  @override
  Future<void> deleteImages(List<File> imageFiles) async {
    deletedImages.addAll(imageFiles);
  }

  @override
  Future<Directory> getImagesDirectory() async {
    return Directory.systemTemp;
  }
}

class FakeDocumentService implements DocumentService {
  List<DocumentAttachment> pickedDocuments = [];
  List<String> skippedDocuments = [];

  @override
  List<String> get lastSkippedDocuments => skippedDocuments;

  @override
  Future<List<DocumentAttachment>> pickDocuments() async {
    return pickedDocuments;
  }

  @override
  Future<DocumentAttachment?> extractDocument(File file) async {
    return null;
  }

  @override
  String buildPromptContext(List<DocumentAttachment> documents) {
    return documents.map((document) => document.text).join('\n');
  }
}

class FakeSpeechService implements SpeechService {
  bool initialized = false;
  bool startedListening = false;
  bool stoppedListening = false;
  bool available = true;

  @override
  bool get isListening => startedListening && !stoppedListening;

  @override
  Future<bool> initialize({
    ValueChanged<String>? onError,
    ValueChanged<String>? onStatusChanged,
  }) async {
    initialized = true;
    return available;
  }

  @override
  Future<bool> startListening({
    required void Function(String recognizedText, bool isFinal) onResult,
    ValueChanged<String>? onError,
    ListenMode listenMode = ListenMode.dictation,
    bool partialResults = true,
    Duration? pauseFor,
    Duration? listenFor,
    String? localeId,
    bool cancelOnError = true,
  }) async {
    startedListening = available;
    return available;
  }

  @override
  Future<void> stopListening() async {
    stoppedListening = true;
  }

  @override
  Future<void> cancelListening() async {
    stoppedListening = true;
  }
}

class FakeOfflineAiAsrService implements OfflineAiAsrService {
  bool startedListening = false;
  bool stoppedListening = false;

  @override
  bool get isListening => startedListening && !stoppedListening;

  @override
  OfflineAiAsrModel modelById(String? id) => OfflineAiAsrService.models.first;

  @override
  Future<bool> isModelDownloaded(String? modelId) async => true;

  @override
  Future<void> downloadModel(
    String? modelId, {
    void Function(OfflineAiAsrDownloadProgress progress)? onProgress,
  }) async {}

  @override
  Future<void> deleteModel(String? modelId) async {}

  @override
  Future<bool> startListening({
    required void Function(String recognizedText, bool isFinal) onResult,
    void Function(String message)? onError,
    void Function(String status)? onStatusChanged,
    Duration pauseFor = const Duration(seconds: 7),
    Duration listenFor = const Duration(seconds: 120),
    String? modelId,
  }) async {
    startedListening = true;
    stoppedListening = false;
    onStatusChanged?.call('listening');
    return true;
  }

  @override
  Future<void> stopListening() async {
    stoppedListening = true;
  }

  @override
  Future<void> cancelListening() async {
    stoppedListening = true;
  }

  @override
  Future<void> dispose() async {}
}

class FakeTtsService implements TtsService {
  bool initialized = false;
  bool stopped = false;
  String? lastSpokenText;

  @override
  String get currentMode => TtsService.systemMode;

  @override
  double get currentSpeechRate => 1.0;

  @override
  double get currentVoicePitch => 1.0;

  @override
  String get currentOfflineVoiceId => OfflineAiTtsService.defaultVoiceId;

  @override
  List<OfflineAiVoice> get offlineAiVoices => OfflineAiTtsService.voices;

  @override
  Future<void> deleteOfflineVoice([String? voiceId]) async {}

  @override
  Future<void> downloadOfflineVoice(
    String? voiceId, {
    void Function(OfflineAiTtsDownloadProgress progress)? onProgress,
  }) async {}

  @override
  Future<List<TtsEngineInfo>> getAvailableEngines() async {
    return const [];
  }

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<bool> isOfflineVoiceDownloaded([String? voiceId]) async {
    return false;
  }

  @override
  Future<void> setEngine(String? engineId) async {}

  @override
  Future<void> setMode(String value) async {}

  @override
  Future<void> setOfflineVoice(String voiceId) async {}

  @override
  Future<void> setSpeechRate(double value) async {}

  @override
  Future<void> setVoicePitch(double value) async {}

  @override
  Future<void> speak(String text) async {
    lastSpokenText = text;
  }

  @override
  Future<void> speakQueued(String text) async {
    lastSpokenText = text;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

class FakePathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return path.join(Directory.current.path, 'test', 'assets');
  }
}
