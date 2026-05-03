import 'package:reins/Models/ollama_chat.dart';
import 'package:test/test.dart';

void main() {
  test('infinite keepAlive sends numeric -1 to the API', () {
    expect(OllamaKeepAliveOption.infinite.apiValue, -1);
  });

  test('timed keepAlive sends duration strings to the API', () {
    expect(OllamaKeepAliveOption.minutes5.apiValue, '5m');
    expect(OllamaKeepAliveOption.minutes10.apiValue, '10m');
    expect(OllamaKeepAliveOption.minutes30.apiValue, '30m');
  });

  test('thinkingEnabled is stored in chat options', () {
    final options = OllamaChatOptions(thinkingEnabled: false);
    final restored = OllamaChatOptions.fromMap(options.toStorageMap());

    expect(restored.thinkingEnabled, isFalse);
  });

  test('role preset is stored in chat options', () {
    final options = OllamaChatOptions(rolePresetId: 'coder');
    final restored = OllamaChatOptions.fromMap(options.toStorageMap());

    expect(restored.rolePresetId, 'coder');
  });
}
