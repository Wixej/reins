import 'dart:convert';
import 'package:uuid/uuid.dart';

import 'package:reins/Constants/constants.dart';

class OllamaChat {
  final String id;
  final String model;
  final String title;
  final String? systemPrompt;
  final OllamaChatOptions options;

  OllamaChat({
    String? id,
    required this.model,
    String? title,
    this.systemPrompt,
    OllamaChatOptions? options,
  })  : id = id ?? Uuid().v4(),
        title = title ?? 'Новый чат',
        options = options ?? OllamaChatOptions();

  factory OllamaChat.fromMap(Map<String, dynamic> map) {
    return OllamaChat(
      id: map['chat_id'],
      model: map['model'],
      title: map['chat_title'],
      systemPrompt: map['system_prompt'],
      options: map['options'] != null ? OllamaChatOptions.fromJson(map['options']) : null,
    );
  }
}

enum OllamaKeepAliveOption {
  minutes5('5m', '5 минут'),
  minutes10('10m', '10 минут'),
  minutes30('30m', '30 минут'),
  infinite('-1', 'Бесконечно');

  final String requestValue;
  final String label;

  const OllamaKeepAliveOption(this.requestValue, this.label);

  Object get apiValue => this == OllamaKeepAliveOption.infinite ? -1 : requestValue;

  factory OllamaKeepAliveOption.fromStoredValue(Object? value) {
    final normalizedValue = value?.toString();

    return OllamaKeepAliveOption.values.firstWhere(
      (option) => option.requestValue == normalizedValue,
      orElse: () => OllamaKeepAliveOption.minutes5,
    );
  }
}

/// Represents configuration options for controlling the behavior of the Ollama chat model.
class OllamaChatOptions {
  /// Enables Mirostat sampling for controlling perplexity.
  /// 0 = disabled, 1 = Mirostat, 2 = Mirostat 2.0.
  int mirostat;

  /// Influences how quickly the algorithm responds to feedback from the generated text.
  /// A lower value results in slower adjustments; a higher value makes the algorithm more responsive.
  double mirostatEta;

  /// Controls the balance between coherence and diversity of the output.
  /// A lower value results in more focused and coherent text.
  double mirostatTau;

  /// Sets the size of the context window used to generate the next token.
  int contextSize;

  /// Sets how far back the model looks to prevent repetition.
  /// 0 = disabled, -1 = full context size.
  int repeatLastN;

  /// Sets the strength of penalizing repetitions.
  /// A higher value (e.g., 1.5) penalizes repetitions more strongly.
  double repeatPenalty;

  /// Controls the temperature of the model.
  /// Higher values result in more creative outputs, lower values in more deterministic outputs.
  double temperature;

  /// Sets the random seed for text generation.
  /// A specific value ensures the same text is generated for the same input.
  int seed;

  /// Controls tail-free sampling to reduce the impact of less probable tokens.
  /// 1.0 disables this setting; higher values reduce the impact more.
  double tailFreeSampling;

  /// Sets the maximum number of tokens to predict during text generation.
  /// -1 = infinite generation.
  int maxTokens;

  /// Limits the probability of generating nonsense.
  /// A higher value (e.g., 100) allows more diverse answers, while a lower value (e.g., 10) is more conservative.
  int topK;

  /// Works with topK to control text diversity.
  /// Higher values lead to more diverse text, lower values to more focused text.
  double topP;

  /// Ensures a balance of quality and variety by setting a minimum token probability relative to the most likely token.
  /// Tokens with lower probability are filtered out.
  double minP;

  /// Controls how long Ollama should keep the model loaded in memory.
  OllamaKeepAliveOption keepAlive;

  /// Controls whether the model should emit reasoning/thinking traces.
  bool thinkingEnabled;

  /// Adds a role-specific system instruction to this chat.
  String rolePresetId;

  /// Creates an instance of [OllamaChatOptions] with default values.
  OllamaChatOptions({
    int? mirostat,
    double? mirostatEta,
    double? mirostatTau,
    int? contextSize,
    int? repeatLastN,
    double? repeatPenalty,
    double? temperature,
    int? seed,
    double? tailFreeSampling,
    int? maxTokens,
    int? topK,
    double? topP,
    double? minP,
    OllamaKeepAliveOption? keepAlive,
    bool? thinkingEnabled,
    String? rolePresetId,
  })  : mirostat = mirostat ?? 0,
        mirostatEta = mirostatEta ?? 0.1,
        mirostatTau = mirostatTau ?? 5.0,
        contextSize = contextSize ?? 2048,
        repeatLastN = repeatLastN ?? 64,
        repeatPenalty = repeatPenalty ?? 1.1,
        temperature = temperature ?? 0.8,
        seed = seed ?? 0,
        tailFreeSampling = tailFreeSampling ?? 1.0,
        maxTokens = maxTokens ?? -1,
        topK = topK ?? 40,
        topP = topP ?? 0.9,
        minP = minP ?? 0.0,
        keepAlive = keepAlive ?? OllamaKeepAliveOption.minutes5,
        thinkingEnabled = thinkingEnabled ?? true,
        rolePresetId = ChatRoles.byId(rolePresetId).id;

  /// Factory method for creating an instance of [OllamaChatOptions] from a map.
  factory OllamaChatOptions.fromMap(Map<String, dynamic> map) {
    return OllamaChatOptions(
      mirostat: map['mirostat'],
      mirostatEta: map['mirostat_eta']?.toDouble(),
      mirostatTau: map['mirostat_tau']?.toDouble(),
      contextSize: map['num_ctx'],
      repeatLastN: map['repeat_last_n'],
      repeatPenalty: map['repeat_penalty']?.toDouble(),
      temperature: map['temperature']?.toDouble(),
      seed: map['seed'],
      tailFreeSampling: map['tfs_z']?.toDouble(),
      maxTokens: map['num_predict'],
      topK: map['top_k'],
      topP: map['top_p']?.toDouble(),
      minP: map['min_p']?.toDouble(),
      keepAlive: OllamaKeepAliveOption.fromStoredValue(map['keep_alive']),
      thinkingEnabled: map['think'] as bool?,
      rolePresetId: map['role_preset'] as String?,
    );
  }

  /// Factory method for creating an instance of [OllamaChatOptions] from a JSON string.
  factory OllamaChatOptions.fromJson(String json) {
    return OllamaChatOptions.fromMap(jsonDecode(json));
  }

  /// Converts the instance of [OllamaChatOptions] to a map.
  Map<String, dynamic> toMap() {
    return {
      'mirostat': mirostat,
      'mirostat_eta': mirostatEta,
      'mirostat_tau': mirostatTau,
      'num_ctx': contextSize,
      'repeat_last_n': repeatLastN,
      'repeat_penalty': repeatPenalty,
      'temperature': temperature,
      'seed': seed,
      'tfs_z': tailFreeSampling,
      if (maxTokens > 0) 'num_predict': maxTokens,
      'top_k': topK,
      'top_p': topP,
      'min_p': minP,
    };
  }

  Map<String, dynamic> toStorageMap() {
    return {
      ...toMap(),
      'keep_alive': keepAlive.requestValue,
      'think': thinkingEnabled,
      'role_preset': rolePresetId,
    };
  }

  OllamaChatOptions copy() {
    return OllamaChatOptions.fromMap(toStorageMap());
  }

  /// Converts the instance of [OllamaChatOptions] to a JSON string.
  String toJson() {
    return jsonEncode(toStorageMap());
  }
}
