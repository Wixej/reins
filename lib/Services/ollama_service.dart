import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:reins/Constants/constants.dart';
import 'package:reins/Utils/http_error_formatter.dart';
import 'package:reins/Models/api/tags_response.dart';
import 'package:reins/Models/api/show_response.dart';
import 'package:reins/Models/ollama_chat.dart';
import 'package:reins/Models/ollama_exception.dart';
import 'package:reins/Models/ollama_message.dart';
import 'package:reins/Models/ollama_model.dart';
import 'package:reins/Models/api/create_request.dart';

class OllamaService {
  /// The base URL for the Ollama service API.
  ///
  /// This URL is used as the root endpoint for all network requests
  /// made by the Ollama service. It should be set to the base address
  /// of the API server.
  ///
  /// The default value is "http://localhost:11434".
  String _baseUrl;
  String get baseUrl => _baseUrl;
  set baseUrl(String? value) => _baseUrl = value ?? "http://localhost:11434";

  /// The headers to include in all network requests.
  final headers = {'Content-Type': 'application/json'};

  /// Creates a new instance of the Ollama service.
  OllamaService({String? baseUrl}) : _baseUrl = baseUrl ?? "http://localhost:11434";

  /// Constructs a URL by resolving the provided path against the base URL.
  Uri constructUrl(String path) {
    final baseUri = Uri.parse(baseUrl);

    // Split the base URI path into segments, filtering out empty strings
    final segments = baseUri.pathSegments.where((s) => s.isNotEmpty).toList();

    // Split the provided path into segments, filtering out empty strings
    final extraSegments = path.split('/').where((s) => s.isNotEmpty).toList();

    // Combine both sets of segments and create a new URI
    return baseUri.replace(pathSegments: [...segments, ...extraSegments]);
  }

  /// Generates an OllamaMessage.
  ///
  /// This method is responsible for generating an instance of
  /// [OllamaMessage] based on the provided prompt and options.
  ///
  /// [prompt] is the input string used to generate the message.
  /// [options] is a map of additional options that can be used to
  /// customize the generation process. It defaults to an empty map.
  ///
  /// Returns a [Future] that completes with an [OllamaMessage].
  Future<OllamaMessage> generate(
    String prompt, {
    required OllamaChat chat,
    bool includeAppContext = true,
  }) async {
    final url = constructUrl("/api/generate");
    final effectiveSystemPrompt = _buildEffectiveSystemPrompt(
      chat,
      includeAppContext: includeAppContext,
    );

    final response = await http.post(
      url,
      headers: headers,
      body: json.encode({
        "model": chat.model,
        "prompt": prompt,
        "system": effectiveSystemPrompt,
        "options": chat.options.toMap(),
        "keep_alive": chat.options.keepAlive.apiValue,
        if (!chat.options.thinkingEnabled) "think": false,
        "stream": false,
      }),
    );

    if (response.statusCode == 200) {
      final jsonBody = json.decode(response.body);
      return OllamaMessage.fromJson(jsonBody);
    } else if (response.statusCode == 404) {
      throw OllamaException('Модель ${chat.model} не найдена на сервере.');
    } else if (response.statusCode == 500) {
      throw OllamaException('Внутренняя ошибка сервера.');
    } else {
      throw OllamaException(HttpErrorFormatter.formatHttpError(response.statusCode, body: response.body));
    }
  }

  Stream<OllamaMessage> generateStream(
    String prompt, {
    required OllamaChat chat,
    bool includeAppContext = true,
  }) async* {
    final url = constructUrl('/api/generate');
    final effectiveSystemPrompt = _buildEffectiveSystemPrompt(
      chat,
      includeAppContext: includeAppContext,
    );

    final request = http.Request("POST", url);
    request.headers.addAll(headers);
    request.body = json.encode({
      "model": chat.model,
      "prompt": prompt,
      "system": effectiveSystemPrompt,
      "options": chat.options.toMap(),
      "keep_alive": chat.options.keepAlive.apiValue,
      if (!chat.options.thinkingEnabled) "think": false,
      "stream": true,
    });

    http.StreamedResponse response = await request.send();

    if (response.statusCode == 200) {
      await for (final message in _processStream(response.stream)) {
        yield message;
      }
    } else if (response.statusCode == 404) {
      throw OllamaException('Модель ${chat.model} не найдена на сервере.');
    } else if (response.statusCode == 500) {
      throw OllamaException('Внутренняя ошибка сервера.');
    } else {
      final body = await response.stream.bytesToString();
      throw OllamaException(HttpErrorFormatter.formatHttpError(response.statusCode, body: body));
    }
  }

  /// Sends a chat message to the Ollama service and returns the response.
  ///
  /// This method takes a message and sends it to the Ollama service, which
  /// processes the message and returns a response. The response is then
  /// encapsulated in an [OllamaMessage] object.
  ///
  /// Returns an [OllamaMessage] containing the response from the Ollama service.
  ///
  /// Throws an [Exception] if there is an error during the communication with
  /// the Ollama service.
  Future<OllamaMessage> chat(
    List<OllamaMessage> messages, {
    required OllamaChat chat,
    bool includeAppContext = true,
  }) async {
    final url = constructUrl("/api/chat");
    final effectiveSystemPrompt = _buildEffectiveSystemPrompt(
      chat,
      includeAppContext: includeAppContext,
    );

    final response = await http.post(
      url,
      headers: headers,
      body: json.encode({
        "model": chat.model,
        "messages": await _prepareMessagesWithSystemPrompt(messages, effectiveSystemPrompt),
        "options": chat.options.toMap(),
        "keep_alive": chat.options.keepAlive.apiValue,
        if (!chat.options.thinkingEnabled) "think": false,
        "stream": false,
      }),
    );

    if (response.statusCode == 200) {
      final jsonBody = json.decode(response.body);
      return OllamaMessage.fromJson(jsonBody);
    } else if (response.statusCode == 404) {
      throw OllamaException('Модель ${chat.model} не найдена на сервере.');
    } else if (response.statusCode == 500) {
      throw OllamaException('Внутренняя ошибка сервера.');
    } else {
      throw OllamaException(HttpErrorFormatter.formatHttpError(response.statusCode, body: response.body));
    }
  }

  Stream<OllamaMessage> chatStream(
    List<OllamaMessage> messages, {
    required OllamaChat chat,
    bool includeAppContext = true,
  }) async* {
    final effectiveSystemPrompt = _buildEffectiveSystemPrompt(
      chat,
      includeAppContext: includeAppContext,
    );
    final preparedMessages = await _prepareMessagesWithSystemPrompt(messages, effectiveSystemPrompt);
    if (!includeAppContext || !_isWebSearchEnabled || !_shouldConsiderWebSearch(preparedMessages)) {
      final response = await _sendChatStreamRequest(preparedMessages, chat: chat);
      await for (final message in _processStream(response.stream, responseRoute: 'fast')) {
        yield message;
      }
      return;
    }

    final lastUserPrompt = _lastUserPrompt(preparedMessages);
    final directSourceContent = lastUserPrompt == null ? null : await _buildDirectSourceToolContent(lastUserPrompt);
    if (directSourceContent != null) {
      final response = await _sendChatStreamRequest(
        [
          ...preparedMessages,
          _syntheticWebSearchAssistantMessage(lastUserPrompt ?? ''),
          {
            'role': 'tool',
            'tool_name': 'web_search',
            'content': directSourceContent,
          },
        ],
        chat: chat,
      );

      await for (final message in _processStream(
        response.stream,
        usedWebSearch: true,
        responseRoute: 'web_search',
      )) {
        yield message;
      }
      return;
    }

    final firstRequestMessages = [
      {
        'role': 'system',
        'content': _webSearchStreamingToolSystemPrompt,
      },
      ...preparedMessages,
    ];
    final firstResponse = await _sendChatStreamRequest(
      firstRequestMessages,
      chat: chat,
      tools: _webSearchTools,
    );
    final toolCalls = <_WebToolCall>[];
    var streamedUserVisibleContent = false;

    await for (final jsonBody in _processRawStream(firstResponse.stream)) {
      final message = OllamaMessage.fromJson(jsonBody);
      message.responseRoute = 'tool_check';
      final chunkToolCalls = _extractWebToolCalls(jsonBody);

      if (chunkToolCalls.isNotEmpty) {
        toolCalls.addAll(chunkToolCalls);
        continue;
      }

      // Stream real answer text immediately, but don't show thinking-only
      // chunks before we know whether the model is about to call web_search.
      if (message.content.isEmpty) {
        if (streamedUserVisibleContent) yield message;
        continue;
      }

      streamedUserVisibleContent = true;
      yield message;
    }

    if (streamedUserVisibleContent || toolCalls.isEmpty) {
      return;
    }

    final toolCall = toolCalls.first;
    final content = await _buildWebSearchToolContent(
      toolCall.query,
      maxResults: toolCall.maxResults,
    );
    final response = await _sendChatStreamRequest(
      [
        ...preparedMessages,
        toolCall.assistantMessage,
        {
          'role': 'tool',
          'tool_name': 'web_search',
          'content': content,
        },
      ],
      chat: chat,
    );

    await for (final message in _processStream(
      response.stream,
      usedWebSearch: true,
      responseRoute: 'web_search',
    )) {
      yield message;
    }
    return;
    /*
    if (false) {
      throw OllamaException('Модель ${chat.model} не найдена на сервере.');
    } else if (response.statusCode == 500) {
      throw OllamaException('Внутренняя ошибка сервера.');
    } else {
      final body = await response.stream.bytesToString();
      throw OllamaException(HttpErrorFormatter.formatHttpError(response.statusCode, body: body));
    }
  }

    */
  }

  bool get _isWebSearchEnabled {
    if (!Hive.isBoxOpen('settings')) return false;

    final settingsBox = Hive.box('settings');
    return settingsBox.get('webSearchEnabled', defaultValue: false) as bool;
  }

  bool _shouldConsiderWebSearch(List<Map<String, dynamic>> messages) {
    final prompt = _lastUserPrompt(messages)?.toLowerCase().trim() ?? '';
    if (prompt.isEmpty) return false;

    final explicitSearchTriggers = RegExp(
      r'('
      r'найди|найти|поиск|поищи|ищи|искать|загугли|гугл|гугле|google|duckduckgo|яндекс|yandex|'
      r'интернет|интернете|веб|web|сеть|онлайн|online|сайт|ссылк|источник|источники|'
      r'проверь|проверить|сверь|подтверди|узнай|посмотри|пробей|'
      r'search|find|look\s+up|google|browse|web|internet|source|sources|verify|check'
      r')',
      caseSensitive: false,
      unicode: true,
    );
    if (explicitSearchTriggers.hasMatch(prompt)) return true;

    final freshDataTopics = RegExp(
      r'('
      r'курс|валют|доллар|доллара|евро|рубл|рубль|юань|биткоин|btc|usd|eur|cny|crypto|крипт|'
      r'цена|стоимость|сколько стоит|прайс|акци|бирж|котиров|индекс|'
      r'погода|температура|осадки|прогноз|'
      r'новост|событи|расписани|рейс|поезд|матч|счет|результат|турнир|'
      r'версия|релиз|обновлен|скачать|документац|статус|работает ли|упал|недоступен|'
      r'закон|штраф|налог|правил|регламент|санкци|'
      r'президент|губернатор|мэр|министр|директор|ceo|кто сейчас|'
      r'exchange\s+rate|price|stock|weather|forecast|news|schedule|score|latest|current|today'
      r')',
      caseSensitive: false,
      unicode: true,
    );
    if (freshDataTopics.hasMatch(prompt)) return true;

    return RegExp(r'https?://|www\.|[a-z0-9-]+\.[a-z]{2,}', caseSensitive: false).hasMatch(prompt);
  }

  Map<String, dynamic> _syntheticWebSearchAssistantMessage(String query) {
    return {
      'role': 'assistant',
      'content': '',
      'tool_calls': [
        {
          'function': {
            'name': 'web_search',
            'arguments': {
              'query': query,
              'max_results': 5,
            },
          },
        },
      ],
    };
  }

  Future<http.StreamedResponse> _sendChatStreamRequest(
    List<Map<String, dynamic>> messages, {
    required OllamaChat chat,
    List<Map<String, dynamic>>? tools,
  }) async {
    final request = http.Request("POST", constructUrl('/api/chat'));
    request.headers.addAll(headers);
    request.body = json.encode({
      "model": chat.model,
      "messages": messages,
      if (tools != null) "tools": tools,
      "options": chat.options.toMap(),
      "keep_alive": chat.options.keepAlive.apiValue,
      if (!chat.options.thinkingEnabled) "think": false,
      "stream": true,
    });

    final response = await request.send();
    if (response.statusCode == 200) return response;

    if (response.statusCode == 404) {
      throw OllamaException('РњРѕРґРµР»СЊ ${chat.model} РЅРµ РЅР°Р№РґРµРЅР° РЅР° СЃРµСЂРІРµСЂРµ.');
    } else if (response.statusCode == 500) {
      throw OllamaException('Р’РЅСѓС‚СЂРµРЅРЅСЏСЏ РѕС€РёР±РєР° СЃРµСЂРІРµСЂР°.');
    }

    final body = await response.stream.bytesToString();
    throw OllamaException(HttpErrorFormatter.formatHttpError(response.statusCode, body: body));
  }

  List<_WebToolCall> _extractWebToolCalls(Map<String, dynamic> jsonBody) {
    final message = jsonBody['message'];
    if (message is! Map<String, dynamic>) return const [];

    final toolCalls = message['tool_calls'];
    if (toolCalls is! List || toolCalls.isEmpty) return const [];

    final parsedToolCalls = <_WebToolCall>[];
    for (final rawToolCall in toolCalls) {
      if (rawToolCall is! Map<String, dynamic>) continue;

      final function = rawToolCall['function'];
      if (function is! Map<String, dynamic>) continue;
      if (function['name'] != 'web_search') continue;

      final arguments = _parseToolArguments(function['arguments']);
      final query = (arguments['query'] as String? ?? '').trim();
      final maxResults = arguments['max_results'] is num ? (arguments['max_results'] as num).round() : 5;
      if (query.isEmpty) continue;

      parsedToolCalls.add(
        _WebToolCall(
          assistantMessage: Map<String, dynamic>.from(message),
          query: query,
          maxResults: maxResults.clamp(1, 5),
        ),
      );
    }

    return parsedToolCalls;
  }

  Stream<Map<String, dynamic>> _processRawStream(Stream stream) async* {
    String buffer = '';

    await for (var chunk in stream.transform(utf8.decoder)) {
      chunk = buffer + chunk;
      buffer = '';

      final lines = LineSplitter.split(chunk);

      for (var line in lines) {
        try {
          yield json.decode(line) as Map<String, dynamic>;
        } on FormatException {
          buffer = line;
        }
      }
    }

    if (buffer.trim().isNotEmpty) {
      yield json.decode(buffer) as Map<String, dynamic>;
    }
  }

  Stream<OllamaMessage> _processStream(
    Stream stream, {
    bool usedWebSearch = false,
    String? responseRoute,
  }) async* {
    // Buffer to store the incomplete JSON object. This is necessary because
    // the Ollama service may send partial JSON objects in a single response.
    // We need to buffer the partial JSON objects and combine them to form
    // complete JSON objects.
    String buffer = '';

    await for (var chunk in stream.transform(utf8.decoder)) {
      chunk = buffer + chunk;
      buffer = '';

      // Split the chunk into lines and parse each line as JSON. This is
      // necessary because the Ollama service may send multiple JSON objects
      // in a single response.
      final lines = LineSplitter.split(chunk);

      for (var line in lines) {
        try {
          final jsonBody = json.decode(line) as Map<String, dynamic>;
          final message = OllamaMessage.fromJson(jsonBody);
          message.usedWebSearch = usedWebSearch;
          message.responseRoute = responseRoute;
          yield message;
        } on FormatException {
          buffer = line;
        }
      }
    }

    if (buffer.trim().isNotEmpty) {
      final jsonBody = json.decode(buffer) as Map<String, dynamic>;
      final message = OllamaMessage.fromJson(jsonBody);
      message.usedWebSearch = usedWebSearch;
      message.responseRoute = responseRoute;
      yield message;
    }
  }

  // Serializes chat messages with a system prompt.
  Future<List<Map<String, dynamic>>> _prepareMessagesWithSystemPrompt(
    List<OllamaMessage> messages,
    String? systemPrompt,
  ) async {
    final jsonMessages = await Future.wait(messages.map((m) async => await m.toChatJson()));

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      final sp = OllamaMessage(systemPrompt, role: OllamaMessageRole.system);
      jsonMessages.insert(0, await sp.toChatJson());
    }

    return jsonMessages;
  }

  String? _buildEffectiveSystemPrompt(
    OllamaChat chat, {
    bool includeAppContext = true,
  }) {
    final parts = <String>[];
    final systemPrompt = chat.systemPrompt;
    final trimmedSystemPrompt = systemPrompt?.trim();

    if (trimmedSystemPrompt != null && trimmedSystemPrompt.isNotEmpty) {
      parts.add(trimmedSystemPrompt);
    }

    final role = ChatRoles.byId(chat.options.rolePresetId);
    if (role.prompt.isNotEmpty) {
      parts.add('Роль модели: ${role.label}.\n${role.prompt}');
    }

    if (includeAppContext) {
      parts.add(_buildAppContextPrompt());
    }

    if (parts.isEmpty) {
      return null;
    }

    return parts.join('\n\n');
  }

  String _buildAppContextPrompt() {
    final settingsBox = Hive.isBoxOpen('settings') ? Hive.box('settings') : null;
    final now = DateTime.now();
    final userFacts = (settingsBox?.get('userFacts', defaultValue: '') as String? ?? '').trim();
    final formattedDateTime = _formatRussianDateTime(now);
    final timezoneOffset = _formatUtcOffset(now.timeZoneOffset);
    final timeZoneName = now.timeZoneName;

    final lines = <String>[
      'Служебный контекст приложения. Считай эти сведения актуальными и достоверными.',
      'Текущие локальные дата и время пользователя: $formattedDateTime ($timeZoneName, UTC$timezoneOffset).',
      'Если пользователь спрашивает про сегодня, завтра, вчера, сейчас или текущее время, ориентируйся на эти данные.',
    ];

    if (userFacts.isNotEmpty) {
      lines.add(
        'Факты о пользователе, которые он сохранил в приложении: $userFacts. '
        'Учитывай их, когда это уместно, и не придумывай новые детали сверх написанного.',
      );
    }

    return lines.join('\n');
  }

  String _formatRussianDateTime(DateTime dateTime) {
    const weekdays = [
      'понедельник',
      'вторник',
      'среда',
      'четверг',
      'пятница',
      'суббота',
      'воскресенье',
    ];
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];

    final weekday = weekdays[dateTime.weekday - 1];
    final month = months[dateTime.month - 1];
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$weekday, ${dateTime.day} $month ${dateTime.year}, $hour:$minute';
  }

  String _formatUtcOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final absoluteOffset = offset.abs();
    final hours = absoluteOffset.inHours.toString().padLeft(2, '0');
    final minutes = (absoluteOffset.inMinutes % 60).toString().padLeft(2, '0');

    return '$sign$hours:$minutes';
  }

  // ignore: unused_element
  Future<_WebToolResult?> _maybeCallWebSearchTool(
    List<Map<String, dynamic>> preparedMessages, {
    required OllamaChat chat,
  }) async {
    if (!Hive.isBoxOpen('settings')) return null;

    final settingsBox = Hive.box('settings');
    final isWebSearchEnabled = settingsBox.get('webSearchEnabled', defaultValue: false) as bool;
    if (!isWebSearchEnabled) return null;

    final toolCall = await _requestWebSearchToolCall(preparedMessages, chat: chat);
    if (toolCall != null) {
      final query = toolCall.query.trim();
      if (query.isEmpty) return null;

      final content = await _buildWebSearchToolContent(
        query,
        maxResults: toolCall.maxResults,
      );

      return _WebToolResult(
        assistantMessage: toolCall.assistantMessage,
        content: content,
      );
    }

    final lastUserPrompt = _lastUserPrompt(preparedMessages);
    if (lastUserPrompt == null || lastUserPrompt.isEmpty) return null;

    final decision = await _decideWebSearch(lastUserPrompt, chat: chat);
    if (!decision.shouldSearch) return null;

    final query = decision.query.trim().isEmpty ? lastUserPrompt : decision.query.trim();
    final content = await _buildWebSearchToolContent(query);

    return _WebToolResult(
      assistantMessage: {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'function': {
              'name': 'web_search',
              'arguments': {'query': query, 'max_results': 5},
            },
          },
        ],
      },
      content: content,
    );
  }

  Future<_WebToolCall?> _requestWebSearchToolCall(
    List<Map<String, dynamic>> preparedMessages, {
    required OllamaChat chat,
  }) async {
    try {
      final response = await http.post(
        constructUrl('/api/chat'),
        headers: headers,
        body: json.encode({
          'model': chat.model,
          'messages': [
            {
              'role': 'system',
              'content': _webSearchToolSystemPrompt,
            },
            ...preparedMessages,
          ],
          'tools': _webSearchTools,
          'options': {
            ...chat.options.toMap(),
            'temperature': 0,
          },
          'keep_alive': chat.options.keepAlive.apiValue,
          if (!chat.options.thinkingEnabled) 'think': false,
          'stream': false,
        }),
      );

      if (response.statusCode != 200) return null;

      final jsonBody = json.decode(response.body) as Map<String, dynamic>;
      final message = jsonBody['message'];
      if (message is! Map<String, dynamic>) return null;

      final toolCalls = message['tool_calls'];
      if (toolCalls is! List || toolCalls.isEmpty) return null;

      for (final rawToolCall in toolCalls) {
        if (rawToolCall is! Map<String, dynamic>) continue;

        final function = rawToolCall['function'];
        if (function is! Map<String, dynamic>) continue;
        if (function['name'] != 'web_search') continue;

        final arguments = _parseToolArguments(function['arguments']);
        final query = (arguments['query'] as String? ?? '').trim();
        final maxResults = arguments['max_results'] is num ? (arguments['max_results'] as num).round() : 5;

        if (query.isEmpty) continue;

        return _WebToolCall(
          assistantMessage: Map<String, dynamic>.from(message),
          query: query,
          maxResults: maxResults.clamp(1, 5),
        );
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Map<String, dynamic> _parseToolArguments(Object? rawArguments) {
    if (rawArguments is Map<String, dynamic>) {
      return rawArguments;
    }

    if (rawArguments is Map) {
      return Map<String, dynamic>.from(rawArguments);
    }

    if (rawArguments is String && rawArguments.trim().isNotEmpty) {
      try {
        final decoded = json.decode(rawArguments);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return const {};
      }
    }

    return const {};
  }

  Future<String> _buildWebSearchToolContent(
    String query, {
    int maxResults = 5,
  }) async {
    final directSourceContent = await _buildDirectSourceToolContent(query);
    if (directSourceContent != null) return directSourceContent;

    final instantAnswerContent = await _buildDuckDuckGoInstantAnswerContent(query);
    if (instantAnswerContent != null) return instantAnswerContent;

    final results = await _searchWeb(query, maxResults: maxResults);
    if (results.isEmpty) {
      return '''
Интернет-поиск был вызван для запроса "$query", но клиент не смог получить результаты.
Не придумывай актуальные факты, курсы, цены, новости или ссылки из памяти.
Скажи пользователю, что поиск не дал результатов или интернет сейчас недоступен, и предложи повторить запрос.
''';
    }

    final buffer = StringBuffer()
      ..writeln('Интернет-поиск включен. Клиент выполнил веб-поиск перед ответом модели.')
      ..writeln('Запрос поиска: "$query".')
      ..writeln('Отвечай на актуальную часть вопроса только по найденным источникам ниже.')
      ..writeln(
          'Не подменяй найденные данные знаниями из памяти, если источники говорят другое или данных недостаточно.')
      ..writeln('Если источники не подтверждают ответ полностью, прямо скажи, чего не хватает.')
      ..writeln('В ответе обязательно упоминай номера источников в квадратных скобках, например [1].')
      ..writeln();

    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      buffer
        ..writeln('[${i + 1}] ${result.title}')
        ..writeln('URL: ${result.url}')
        ..writeln('Фрагмент: ${result.snippet}')
        ..writeln();
    }

    return buffer.toString().trim();
  }

  Future<String?> _buildDirectSourceToolContent(String query) async {
    final currencyContent = await _buildCurrencyToolContent(query);
    if (currencyContent != null) return currencyContent;

    final weatherContent = await _buildWeatherToolContent(query);
    if (weatherContent != null) return weatherContent;

    final cryptoContent = await _buildCryptoToolContent(query);
    if (cryptoContent != null) return cryptoContent;

    final newsContent = await _buildNewsToolContent(query);
    if (newsContent != null) return newsContent;

    return null;
  }

  Future<String?> _buildCurrencyToolContent(String query) async {
    final normalizedQuery = query.toLowerCase();
    final requestedCurrencies = _extractRequestedCurrencies(normalizedQuery);
    if (requestedCurrencies.isEmpty || !_looksLikeFiatExchangeRateQuery(normalizedQuery)) {
      return null;
    }

    final requestedDate = _extractCurrencyDate(normalizedQuery);
    final sourceUrl = _cbrDailyUrl(requestedDate);

    try {
      final response = await http.get(
        Uri.parse(sourceUrl),
        headers: const {
          'User-Agent': 'Mozilla/5.0 Reins Android Currency Lookup',
        },
      );
      if (response.statusCode != 200) return null;

      final xml = latin1.decode(response.bodyBytes);
      final effectiveDate =
          RegExp(r'<ValCurs[^>]*Date="([^"]+)"').firstMatch(xml)?.group(1) ?? _formatCbrDate(requestedDate);
      final rates = _parseCbrRates(xml, requestedCurrencies);
      if (rates.isEmpty) return null;

      final buffer = StringBuffer()
        ..writeln(
            'Internet search is enabled, but this currency question was answered from the official Central Bank of Russia daily rates feed instead of generic search snippets.')
        ..writeln('User query: "$query".')
        ..writeln('Requested date: ${_formatCbrDate(requestedDate)}.')
        ..writeln('Effective CBR rate date from source: $effectiveDate.')
        ..writeln('Answer using the exact numeric rates below. Do not say that the numeric value is missing.')
        ..writeln('Mention source [1].')
        ..writeln()
        ..writeln('[1] Central Bank of Russia daily exchange rates')
        ..writeln('URL: $sourceUrl');

      for (final rate in rates) {
        buffer
          ..writeln('${rate.code}: ${rate.nominal} ${rate.code} = ${rate.valueRub} RUB')
          ..writeln('Rate for 1 ${rate.code}: ${rate.valuePerUnitRub} RUB');
      }

      return buffer.toString().trim();
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeFiatExchangeRateQuery(String query) {
    const rateWords = [
      'курс',
      'валют',
      'рубл',
      'рубль',
      'рублей',
      'exchange rate',
      'rate',
      'cbr',
      'цб',
      'центробанк',
    ];

    return rateWords.any(query.contains);
  }

  List<String> _extractRequestedCurrencies(String query) {
    final currencies = <String>{};
    final patterns = <String, List<String>>{
      'USD': ['доллар', 'доллара', 'бакс', 'usd', '\$'],
      'EUR': ['евро', 'eur'],
      'CNY': ['юань', 'юаня', 'юаней', 'cny'],
      'GBP': ['фунт', 'gbp'],
      'JPY': ['иена', 'йена', 'jpy'],
      'CHF': ['франк', 'chf'],
      'KZT': ['тенге', 'kzt'],
      'TRY': ['лира', 'try'],
      'AED': ['дирхам', 'aed'],
      'BYN': ['белорус', 'byn'],
    };

    for (final entry in patterns.entries) {
      if (entry.value.any(query.contains)) {
        currencies.add(entry.key);
      }
    }

    return currencies.toList();
  }

  DateTime _extractCurrencyDate(String query) {
    final now = DateTime.now();
    if (query.contains('вчера') || query.contains('yesterday')) {
      return now.subtract(const Duration(days: 1));
    }

    final numericDate = RegExp(r'\b(\d{1,2})[./-](\d{1,2})(?:[./-](\d{2,4}))?\b').firstMatch(query);
    if (numericDate != null) {
      final day = int.tryParse(numericDate.group(1) ?? '');
      final month = int.tryParse(numericDate.group(2) ?? '');
      final rawYear = numericDate.group(3);
      var year = rawYear == null ? now.year : int.tryParse(rawYear);
      if (year != null && year < 100) year += 2000;

      if (day != null && month != null && year != null && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime(year, month, day);
      }
    }

    return now;
  }

  String _cbrDailyUrl(DateTime date) {
    return 'https://www.cbr.ru/scripts/XML_daily.asp?date_req=${_formatCbrDate(date)}';
  }

  String _formatCbrDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  List<_CbrCurrencyRate> _parseCbrRates(String xml, List<String> requestedCurrencies) {
    final rates = <_CbrCurrencyRate>[];
    final valuteBlocks = RegExp(r'<Valute[^>]*>.*?</Valute>', dotAll: true).allMatches(xml);

    for (final code in requestedCurrencies) {
      final block = valuteBlocks.map((match) => match.group(0) ?? '').firstWhere(
          (block) => RegExp(r'<CharCode>\s*' + RegExp.escape(code) + r'\s*</CharCode>').hasMatch(block),
          orElse: () => '');
      if (block.isEmpty) continue;

      final nominal = int.tryParse(RegExp(r'<Nominal>(\d+)</Nominal>').firstMatch(block)?.group(1) ?? '') ?? 1;
      final valueText = RegExp(r'<Value>([^<]+)</Value>').firstMatch(block)?.group(1)?.replaceAll(',', '.');
      final value = double.tryParse(valueText ?? '');
      if (value == null) continue;

      rates.add(
        _CbrCurrencyRate(
          code: code,
          nominal: nominal,
          valueRub: value.toStringAsFixed(4),
          valuePerUnitRub: (value / nominal).toStringAsFixed(4),
        ),
      );
    }

    return rates;
  }

  Future<String?> _buildWeatherToolContent(String query) async {
    final normalizedQuery = query.toLowerCase();
    if (!_looksLikeWeatherQuery(normalizedQuery)) return null;

    final location = _extractWeatherLocation(query);
    if (location.isEmpty) return null;

    try {
      final geocodeUri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': location,
        'count': '1',
        'language': 'ru',
        'format': 'json',
      });
      final geocodeResponse = await http.get(geocodeUri);
      if (geocodeResponse.statusCode != 200) return null;

      final geocode = json.decode(utf8.decode(geocodeResponse.bodyBytes)) as Map<String, dynamic>;
      final results = geocode['results'];
      if (results is! List || results.isEmpty || results.first is! Map) return null;

      final place = Map<String, dynamic>.from(results.first as Map);
      final latitude = place['latitude'];
      final longitude = place['longitude'];
      if (latitude == null || longitude == null) return null;

      final forecastUri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': '$latitude',
        'longitude': '$longitude',
        'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m',
        'daily': 'temperature_2m_max,temperature_2m_min,precipitation_sum,weather_code',
        'forecast_days': '3',
        'timezone': 'auto',
      });
      final forecastResponse = await http.get(forecastUri);
      if (forecastResponse.statusCode != 200) return null;

      final forecast = json.decode(utf8.decode(forecastResponse.bodyBytes)) as Map<String, dynamic>;
      final current = forecast['current'] is Map ? Map<String, dynamic>.from(forecast['current'] as Map) : const {};
      final daily = forecast['daily'] is Map ? Map<String, dynamic>.from(forecast['daily'] as Map) : const {};
      final name = [
        place['name'],
        place['admin1'],
        place['country'],
      ].where((part) => part != null && '$part'.trim().isNotEmpty).join(', ');

      final buffer = StringBuffer()
        ..writeln('Weather data source selected instead of generic web snippets.')
        ..writeln('User query: "$query".')
        ..writeln('Location resolved by Open-Meteo geocoding: $name.')
        ..writeln('Answer using the structured weather values below. Mention source [1].')
        ..writeln()
        ..writeln('[1] Open-Meteo Forecast API')
        ..writeln('URL: $forecastUri')
        ..writeln('Current time: ${current['time'] ?? 'unknown'}')
        ..writeln('Temperature: ${current['temperature_2m'] ?? 'unknown'} C')
        ..writeln('Feels like: ${current['apparent_temperature'] ?? 'unknown'} C')
        ..writeln('Humidity: ${current['relative_humidity_2m'] ?? 'unknown'}%')
        ..writeln('Precipitation: ${current['precipitation'] ?? 'unknown'} mm')
        ..writeln('Wind speed: ${current['wind_speed_10m'] ?? 'unknown'} km/h')
        ..writeln(
            'Weather code: ${current['weather_code'] ?? 'unknown'} (${_weatherCodeDescription(current['weather_code'])})');

      final days = daily['time'];
      if (days is List) {
        final maxTemps = daily['temperature_2m_max'] as List? ?? const [];
        final minTemps = daily['temperature_2m_min'] as List? ?? const [];
        final precipitation = daily['precipitation_sum'] as List? ?? const [];
        final codes = daily['weather_code'] as List? ?? const [];
        buffer.writeln();
        buffer.writeln('Daily forecast:');
        for (var i = 0; i < days.length && i < 3; i++) {
          buffer.writeln(
            '${days[i]}: ${_listValue(minTemps, i)}..${_listValue(maxTemps, i)} C, precipitation ${_listValue(precipitation, i)} mm, ${_weatherCodeDescription(_listValue(codes, i))}',
          );
        }
      }

      return buffer.toString().trim();
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeWeatherQuery(String query) {
    const triggers = [
      'погода',
      'температура',
      'прогноз',
      'дождь',
      'снег',
      'ветер',
      'осадки',
      'weather',
      'forecast',
      'temperature',
      'rain',
      'snow',
      'wind',
    ];

    return triggers.any(query.contains);
  }

  String _extractWeatherLocation(String query) {
    var location = query.toLowerCase();
    const removable = [
      'какая',
      'какой',
      'погода',
      'температура',
      'прогноз',
      'сейчас',
      'сегодня',
      'завтра',
      'послезавтра',
      'на улице',
      'weather',
      'forecast',
      'temperature',
      'today',
      'tomorrow',
      '?',
    ];

    for (final word in removable) {
      location = location.replaceAll(word, ' ');
    }

    location = location
        .replaceAll(RegExp(r'\b(в|во|на|для|по|in|at|for)\b', caseSensitive: false, unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return location;
  }

  Object? _listValue(List values, int index) {
    return index >= 0 && index < values.length ? values[index] : 'unknown';
  }

  String _weatherCodeDescription(Object? rawCode) {
    final code = rawCode is num ? rawCode.round() : int.tryParse('$rawCode');
    return switch (code) {
      0 => 'clear sky',
      1 || 2 || 3 => 'partly cloudy',
      45 || 48 => 'fog',
      51 || 53 || 55 => 'drizzle',
      56 || 57 => 'freezing drizzle',
      61 || 63 || 65 => 'rain',
      66 || 67 => 'freezing rain',
      71 || 73 || 75 => 'snow',
      77 => 'snow grains',
      80 || 81 || 82 => 'rain showers',
      85 || 86 => 'snow showers',
      95 => 'thunderstorm',
      96 || 99 => 'thunderstorm with hail',
      _ => 'unknown',
    };
  }

  Future<String?> _buildCryptoToolContent(String query) async {
    final normalizedQuery = query.toLowerCase();
    final coinIds = _extractRequestedCryptoIds(normalizedQuery);
    if (coinIds.isEmpty || !_looksLikeCryptoQuery(normalizedQuery)) return null;

    try {
      final uri = Uri.https('api.coingecko.com', '/api/v3/simple/price', {
        'ids': coinIds.join(','),
        'vs_currencies': 'usd,rub',
        'include_24hr_change': 'true',
        'include_last_updated_at': 'true',
      });
      final response = await http.get(uri, headers: const {'User-Agent': 'Reins Android Crypto Lookup'});
      if (response.statusCode != 200) return null;

      final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data.isEmpty) return null;

      final buffer = StringBuffer()
        ..writeln('Crypto price data source selected instead of generic web snippets.')
        ..writeln('User query: "$query".')
        ..writeln('Answer using the structured prices below. Mention source [1].')
        ..writeln()
        ..writeln('[1] CoinGecko Simple Price API')
        ..writeln('URL: $uri');

      for (final id in coinIds) {
        final coin = data[id];
        if (coin is! Map) continue;
        buffer
          ..writeln('$id USD: ${coin['usd'] ?? 'unknown'}')
          ..writeln('$id RUB: ${coin['rub'] ?? 'unknown'}')
          ..writeln('$id 24h change: ${coin['usd_24h_change'] ?? 'unknown'}%')
          ..writeln('$id last updated unix: ${coin['last_updated_at'] ?? 'unknown'}');
      }

      return buffer.toString().trim();
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeCryptoQuery(String query) {
    const triggers = [
      'крипт',
      'биткоин',
      'эфир',
      'ethereum',
      'bitcoin',
      'btc',
      'eth',
      'sol',
      'ton',
      'usdt',
      'crypto',
      'coin',
      'токен',
    ];

    return triggers.any(query.contains);
  }

  List<String> _extractRequestedCryptoIds(String query) {
    final ids = <String>{};
    final patterns = <String, List<String>>{
      'bitcoin': ['bitcoin', 'биткоин', 'биток', 'btc', 'битка'],
      'ethereum': ['ethereum', 'эфир', 'eth'],
      'solana': ['solana', 'солана', 'sol'],
      'the-open-network': ['toncoin', 'ton', 'тон'],
      'tether': ['usdt', 'tether', 'тезер'],
      'binancecoin': ['bnb', 'бинанс'],
      'ripple': ['xrp', 'ripple'],
      'dogecoin': ['doge', 'dogecoin', 'дог'],
    };

    for (final entry in patterns.entries) {
      if (entry.value.any(query.contains)) {
        ids.add(entry.key);
      }
    }

    return ids.toList();
  }

  Future<String?> _buildNewsToolContent(String query) async {
    final normalizedQuery = query.toLowerCase();
    if (!_looksLikeNewsQuery(normalizedQuery)) return null;

    final newsQuery = _extractNewsQuery(query);
    if (newsQuery.isEmpty) return null;

    try {
      final uri = Uri.https('news.google.com', '/rss/search', {
        'q': newsQuery,
        'hl': 'ru',
        'gl': 'RU',
        'ceid': 'RU:ru',
      });
      final response = await http.get(uri, headers: const {'User-Agent': 'Mozilla/5.0 Reins Android News Lookup'});
      if (response.statusCode != 200) return null;

      final rss = utf8.decode(response.bodyBytes);
      final items = _parseGoogleNewsItems(rss, maxItems: 5);
      if (items.isEmpty) return null;

      final buffer = StringBuffer()
        ..writeln('News source selected instead of generic web snippets.')
        ..writeln('User query: "$query".')
        ..writeln('News search query: "$newsQuery".')
        ..writeln('Summarize only the news items below. Mention source numbers like [1].')
        ..writeln();

      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        buffer
          ..writeln('[${i + 1}] ${item.title}')
          ..writeln('Source: ${item.source}')
          ..writeln('Published: ${item.published}')
          ..writeln('URL: ${item.url}')
          ..writeln();
      }

      return buffer.toString().trim();
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeNewsQuery(String query) {
    const triggers = [
      'новости',
      'новость',
      'что случилось',
      'события',
      'последние',
      'свежие',
      'news',
      'headlines',
      'latest',
      'breaking',
    ];

    return triggers.any(query.contains);
  }

  String _extractNewsQuery(String query) {
    var newsQuery = query.toLowerCase();
    const removable = [
      'новости',
      'новость',
      'последние',
      'свежие',
      'главные',
      'сегодня',
      'сейчас',
      'что случилось',
      'news',
      'headlines',
      'latest',
      'breaking',
      '?',
    ];

    for (final word in removable) {
      newsQuery = newsQuery.replaceAll(word, ' ');
    }

    newsQuery = newsQuery.replaceAll(RegExp(r'\s+'), ' ').trim();
    return newsQuery.isEmpty ? 'мир OR Россия' : newsQuery;
  }

  List<_NewsItem> _parseGoogleNewsItems(String rss, {required int maxItems}) {
    final items = <_NewsItem>[];
    final itemMatches = RegExp(r'<item>(.*?)</item>', dotAll: true).allMatches(rss);

    for (final match in itemMatches) {
      if (items.length >= maxItems) break;

      final block = match.group(1) ?? '';
      final title = _decodeXmlText(RegExp(r'<title><!\[CDATA\[(.*?)\]\]></title>|<title>(.*?)</title>', dotAll: true)
              .firstMatch(block)
              ?.groups([1, 2])
              .whereType<String>()
              .firstOrNull ??
          '');
      final link = _decodeXmlText(RegExp(r'<link>(.*?)</link>', dotAll: true).firstMatch(block)?.group(1) ?? '');
      final pubDate =
          _decodeXmlText(RegExp(r'<pubDate>(.*?)</pubDate>', dotAll: true).firstMatch(block)?.group(1) ?? '');
      final source = _decodeXmlText(
        RegExp(r'<source[^>]*>(.*?)</source>', dotAll: true).firstMatch(block)?.group(1) ?? 'Google News',
      );

      if (title.isEmpty || link.isEmpty) continue;
      items.add(_NewsItem(title: title, url: link, published: pubDate, source: source));
    }

    return items;
  }

  String _decodeXmlText(String value) {
    return html_parser.parseFragment(value).text?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? value.trim();
  }

  String? _lastUserPrompt(List<Map<String, dynamic>> messages) {
    for (final message in messages.reversed) {
      if (message['role'] != 'user') continue;
      return (message['content'] as String? ?? '').trim();
    }

    return null;
  }

  Future<_WebSearchDecision> _decideWebSearch(
    String userPrompt, {
    required OllamaChat chat,
  }) async {
    try {
      final response = await http.post(
        constructUrl('/api/chat'),
        headers: headers,
        body: json.encode({
          'model': chat.model,
          'messages': [
            {
              'role': 'system',
              'content': _webSearchDecisionSystemPrompt,
            },
            {
              'role': 'user',
              'content': userPrompt,
            },
          ],
          'options': {
            ...chat.options.toMap(),
            'temperature': 0,
          },
          'keep_alive': chat.options.keepAlive.apiValue,
          if (!chat.options.thinkingEnabled) 'think': false,
          'stream': false,
          'format': 'json',
        }),
      );

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body) as Map<String, dynamic>;
        final message = jsonBody['message'];
        final content = message is Map<String, dynamic> ? message['content'] as String? : null;
        final decision = _parseWebSearchDecision(content ?? '');
        if (decision != null) return decision;
      }
    } catch (_) {
      // If the model cannot make the routing decision, fall back to simple local rules.
    }

    return const _WebSearchDecision(shouldSearch: false, query: '');
  }

  _WebSearchDecision? _parseWebSearchDecision(String rawContent) {
    final trimmed = rawContent.trim();
    if (trimmed.isEmpty) return null;

    final withoutFence = trimmed
        .replaceAll(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();
    final start = withoutFence.indexOf('{');
    final end = withoutFence.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;

    try {
      final decoded = json.decode(withoutFence.substring(start, end + 1)) as Map<String, dynamic>;
      return _WebSearchDecision(
        shouldSearch: decoded['search'] == true,
        query: (decoded['query'] as String? ?? '').trim(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<_WebSearchResult>> _searchWeb(
    String query, {
    int maxResults = 5,
  }) async {
    try {
      final uri = Uri.https('html.duckduckgo.com', '/html/', {
        'q': query,
        'kl': 'ru-ru',
      });
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'Mozilla/5.0 Reins Android Web Search',
        },
      );

      if (response.statusCode != 200) return const [];

      final document = html_parser.parse(utf8.decode(response.bodyBytes));
      final resultNodes = document.querySelectorAll('.result');
      final results = <_WebSearchResult>[];

      for (final node in resultNodes) {
        if (results.length >= maxResults.clamp(1, 5)) break;

        final titleNode = node.querySelector('.result__a');
        final snippetNode = node.querySelector('.result__snippet');
        final rawTitle = titleNode?.text.trim() ?? '';
        final rawUrl = titleNode?.attributes['href'] ?? '';
        final rawSnippet = snippetNode?.text.trim() ?? '';

        final title = _normalizeWhitespace(rawTitle);
        final url = _normalizeDuckDuckGoUrl(rawUrl);
        final snippet = _normalizeWhitespace(rawSnippet);

        if (title.isEmpty || url.isEmpty) continue;

        results.add(
          _WebSearchResult(
            title: title,
            url: url,
            snippet: snippet.isEmpty ? title : snippet,
          ),
        );
      }

      return await _enrichWebSearchResults(results);
    } catch (_) {
      return const [];
    }
  }

  Future<String?> _buildDuckDuckGoInstantAnswerContent(String query) async {
    try {
      final uri = Uri.https('api.duckduckgo.com', '/', {
        'q': query,
        'format': 'json',
        'no_redirect': '1',
        'no_html': '1',
        'skip_disambig': '1',
        'kl': 'ru-ru',
      });
      final response = await http.get(uri, headers: const {'User-Agent': 'Mozilla/5.0 Reins Android Web Search'});
      if (response.statusCode != 200) return null;

      final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final abstract = _normalizeWhitespace(data['AbstractText'] as String? ?? '');
      final answer = _normalizeWhitespace(data['Answer'] as String? ?? '');
      final definition = _normalizeWhitespace(data['Definition'] as String? ?? '');
      final source = _normalizeWhitespace(data['AbstractSource'] as String? ?? 'DuckDuckGo Instant Answer');
      final url = _normalizeWhitespace(data['AbstractURL'] as String? ?? '');
      final content = [answer, definition, abstract].where((part) => part.isNotEmpty).join('\n');
      if (content.isEmpty) return null;

      return '''
DuckDuckGo Instant Answer returned a structured answer before generic search snippets.
User query: "$query".
Answer using the structured data below. Mention source [1].

[1] $source
URL: ${url.isEmpty ? uri.toString() : url}
Content: $content
'''
          .trim();
    } catch (_) {
      return null;
    }
  }

  Future<List<_WebSearchResult>> _enrichWebSearchResults(List<_WebSearchResult> results) async {
    if (results.isEmpty) return results;

    final enriched = <_WebSearchResult>[];
    for (final result in results) {
      if (enriched.length >= 3) {
        enriched.add(result);
        continue;
      }

      final pageExcerpt = await _fetchReadablePageExcerpt(result.url);
      if (pageExcerpt == null || pageExcerpt.isEmpty) {
        enriched.add(result);
        continue;
      }

      enriched.add(
        _WebSearchResult(
          title: result.title,
          url: result.url,
          snippet: _normalizeWhitespace('${result.snippet}\nPage excerpt: $pageExcerpt'),
        ),
      );
    }

    return enriched;
  }

  Future<String?> _fetchReadablePageExcerpt(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return null;

    try {
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'Mozilla/5.0 Reins Android Web Search',
          'Accept': 'text/html,application/xhtml+xml',
        },
      ).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;

      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('text/html') && !contentType.contains('application/xhtml')) return null;

      final document = html_parser.parse(utf8.decode(response.bodyBytes, allowMalformed: true));
      for (final selector in ['script', 'style', 'noscript', 'svg', 'nav', 'footer', 'header', 'form']) {
        for (final node in document.querySelectorAll(selector)) {
          node.remove();
        }
      }

      final metaDescription = document.querySelector('meta[name="description"]')?.attributes['content'];
      final paragraphs = document
          .querySelectorAll('article p, main p, p')
          .map((node) => _normalizeWhitespace(node.text))
          .where((text) => text.length >= 80)
          .take(4)
          .join(' ');
      final text = _normalizeWhitespace([
        if (metaDescription != null) metaDescription,
        paragraphs,
      ].where((part) => part.trim().isNotEmpty).join(' '));

      if (text.isEmpty) return null;
      return text.length > 1200 ? '${text.substring(0, 1200)}...' : text;
    } catch (_) {
      return null;
    }
  }

  String _normalizeDuckDuckGoUrl(String href) {
    if (href.isEmpty) return '';

    final parsed = Uri.tryParse(href);
    final uddg = parsed?.queryParameters['uddg'];
    if (uddg != null && uddg.isNotEmpty) {
      return uddg;
    }

    if (href.startsWith('//')) {
      return 'https:$href';
    }

    if (href.startsWith('/')) {
      return 'https://duckduckgo.com$href';
    }

    return href;
  }

  String _normalizeWhitespace(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static const String _webSearchDecisionSystemPrompt = '''
Ты решаешь, нужен ли интернет-поиск перед ответом на сообщение пользователя.
Отвечай только JSON без Markdown:
{"search": true/false, "query": "короткий поисковый запрос"}

Включай search=true, если пользователь явно просит найти в интернете, нужны свежие/текущие данные, новости, курсы валют, цены, расписания, версии, погода, события, сегодняшняя дата в контексте внешних фактов или проверка актуальных фактов.
Ставь search=false, если вопрос можно ответить без свежих внешних данных: объяснение, письмо, перевод, код, математика, общие советы, работа с уже данным текстом.
Поисковый запрос пиши на языке пользователя и без лишних слов.
''';

  static const String _webSearchStreamingToolSystemPrompt = '''
You can use the web_search tool inside this same streaming chat request.

Call web_search only when the user explicitly asks to search/check the internet,
or when a good answer depends on fresh/current external data: news, currency
rates, prices, weather, schedules, software versions, laws, events, service
status, or current public facts.

Do not call web_search for questions that can be answered confidently without
fresh external data: explanations, translation, writing, math, coding based on
the provided context, creative text, or general advice.

If web_search is needed, call only the tool with a short precise query and wait
for the tool result before writing the final answer.
If web_search is not needed, answer the user immediately in this same streaming
response. Do not make a separate hidden decision step.
''';

  static const String _webSearchToolSystemPrompt = '''
Ты управляешь инструментом web_search для Android-клиента Ollama.
Твоя задача - решить, нужно ли вызвать web_search перед финальным ответом.

Вызови web_search, если:
- пользователь явно просит поискать, найти в интернете или проверить актуальные сведения;
- ответ зависит от свежих данных: новости, курсы валют, цены, погода, расписания, версии, законы, события, статусы сервисов, текущие должности людей;
- ты не уверен в факте и свежая проверка реально улучшит ответ.

Не вызывай web_search, если вопрос можно уверенно решить без внешних данных: объяснение, перевод, письмо, математика, код по уже данному контексту, творческий текст, общие советы.

Если поиск нужен, вызови только инструмент web_search с коротким точным query.
Если поиск не нужен, не вызывай инструменты.
Не отвечай пользователю в этом шаге.
''';

  static const List<Map<String, dynamic>> _webSearchTools = [
    {
      'type': 'function',
      'function': {
        'name': 'web_search',
        'description':
            'Search the internet for current or uncertain information, then return source titles, URLs, and snippets.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'A short, precise search query in the user language.',
            },
            'max_results': {
              'type': 'integer',
              'description': 'How many search results to return, from 1 to 5.',
            },
          },
          'required': ['query'],
        },
      },
    },
  ];

  /// Lists the available models on the Ollama service.
  ///
  /// Fetches models from /api/tags and enriches each with capabilities
  /// from /api/show. If /api/show fails for a model, capabilities will be null.
  Future<List<OllamaModel>> listModels() async {
    final tagsResponse = await _fetchTags();

    // Fetch capabilities for each model in parallel
    final models = await Future.wait(
      tagsResponse.models.map((model) async {
        final showResponse = await _showModel(model.name);
        return OllamaModel.from(model, showResponse);
      }),
    );

    return models;
  }

  /// Fetches the list of models from /api/tags
  Future<ApiTagsResponse> _fetchTags() async {
    final url = constructUrl("/api/tags");

    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final jsonBody = json.decode(response.body);
      return ApiTagsResponse.fromJson(jsonBody);
    } else if (response.statusCode == 500) {
      throw OllamaException('Внутренняя ошибка сервера.');
    } else {
      throw OllamaException(HttpErrorFormatter.formatHttpError(response.statusCode, body: response.body));
    }
  }

  /// Fetches detailed model information from /api/show
  ///
  /// Returns null if the endpoint is unavailable or returns an error.
  /// This ensures graceful degradation for older Ollama versions.
  Future<ApiShowResponse?> _showModel(String name) async {
    try {
      final url = constructUrl("/api/show");

      final response = await http.post(
        url,
        headers: headers,
        body: json.encode({"model": name}),
      );

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        return ApiShowResponse.fromJson(jsonBody);
      }
    } catch (_) {
      // Silently ignore - endpoint may not exist on older Ollama versions
    }

    return null;
  }

  Future<void> createModel(
    String model, {
    required OllamaChat chat,
    List<OllamaMessage>? messages,
  }) async {
    final url = constructUrl("/api/create");

    final request = ApiCreateRequest.fromChat(
      model,
      chat: chat,
      messages: messages,
    );

    final response = await http.post(
      url,
      headers: headers,
      body: json.encode(await request.toJson()),
    );

    if (response.statusCode == 200) {
      return;
    } else if (response.statusCode == 500) {
      throw OllamaException('Внутренняя ошибка сервера.');
    } else {
      throw OllamaException(HttpErrorFormatter.formatHttpError(response.statusCode, body: response.body));
    }
  }

  Future<void> deleteModel(String model) async {
    final url = constructUrl("/api/delete");

    final response = await http.delete(
      url,
      headers: headers,
      body: json.encode({"model": model}),
    );

    if (response.statusCode == 200) {
      return;
    } else if (response.statusCode == 404) {
      throw OllamaException('Модель $model не найдена на сервере.');
    } else if (response.statusCode == 500) {
      throw OllamaException('Внутренняя ошибка сервера.');
    } else {
      throw OllamaException(HttpErrorFormatter.formatHttpError(response.statusCode, body: response.body));
    }
  }
}

class _WebSearchDecision {
  final bool shouldSearch;
  final String query;

  const _WebSearchDecision({
    required this.shouldSearch,
    required this.query,
  });
}

class _WebSearchResult {
  final String title;
  final String url;
  final String snippet;

  const _WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });
}

class _CbrCurrencyRate {
  final String code;
  final int nominal;
  final String valueRub;
  final String valuePerUnitRub;

  const _CbrCurrencyRate({
    required this.code,
    required this.nominal,
    required this.valueRub,
    required this.valuePerUnitRub,
  });
}

class _NewsItem {
  final String title;
  final String url;
  final String published;
  final String source;

  const _NewsItem({
    required this.title,
    required this.url,
    required this.published,
    required this.source,
  });
}

class _WebToolCall {
  final Map<String, dynamic> assistantMessage;
  final String query;
  final int maxResults;

  const _WebToolCall({
    required this.assistantMessage,
    required this.query,
    required this.maxResults,
  });
}

class _WebToolResult {
  final Map<String, dynamic> assistantMessage;
  final String content;

  const _WebToolResult({
    required this.assistantMessage,
    required this.content,
  });
}
