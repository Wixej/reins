import 'dart:async';
import 'dart:io';

/// A utility class for formatting HTTP errors and exceptions into human-readable messages.
///
/// Provides static methods to convert common network exceptions and HTTP status codes
/// into user-friendly error messages.
class HttpErrorFormatter {
  HttpErrorFormatter._(); // Private constructor - use static methods

  /// Converts common exceptions to human-readable error messages.
  static String formatException(Object error) {
    if (error is TimeoutException) {
      return 'Превышено время ожидания соединения. Проверь, запущен ли сервер.';
    } else if (error is SocketException) {
      final message = error.message.toLowerCase();
      if (message.contains('no route to host') || message.contains('network is unreachable')) {
        return 'Сеть недоступна. Проверь подключение к интернету.';
      } else if (message.contains('connection refused')) {
        return 'Соединение отклонено. Возможно, сервер не запущен.';
      } else if (message.contains('no address associated') || message.contains('failed host lookup')) {
        return 'Не удалось найти сервер. Проверь адрес сервера в настройках.';
      }
      return 'Сетевая ошибка: ${error.message}';
    } else if (error is HttpException) {
      return 'Ошибка HTTP: ${error.message}';
    } else if (error is FormatException) {
      return 'Неверный формат адреса сервера. Проверь настройки подключения.';
    } else if (error is HandshakeException) {
      return 'Ошибка SSL/TLS рукопожатия. Проверь сертификат сервера.';
    } else if (error is TlsException) {
      return 'Не удалось установить защищенное соединение. Проверь сертификат сервера.';
    }
    return 'Ошибка подключения: ${error.toString()}';
  }

  /// Converts HTTP status codes to human-readable error messages.
  ///
  /// [statusCode] is the HTTP status code returned by the server.
  /// [body] is the optional response body that will be appended to the message.
  ///
  /// Returns a formatted error message with the status code and optional body.
  static String formatHttpError(int statusCode, {String? body}) {
    final reason = switch (statusCode) {
      400 => 'Некорректный запрос. Проверь адрес сервера.',
      401 => 'Нет авторизации. Проверь API-ключ.',
      403 => 'Доступ запрещен. У тебя нет прав на этот сервер.',
      404 => 'Ресурс не найден. Нужная модель или endpoint отсутствует.',
      408 => 'Время ожидания запроса истекло. Попробуй еще раз.',
      429 => 'Слишком много запросов. Подожди немного и повтори.',
      500 => 'Внутренняя ошибка сервера.',
      502 => 'Ошибка шлюза. Возможно, проблема на сервере или прокси.',
      503 => 'Сервис временно недоступен.',
      504 => 'Сервер слишком долго отвечает.',
      _ => 'Сервер вернул ошибку.',
    };

    final trimmedBody = body?.trim();

    if (trimmedBody == null || trimmedBody.isEmpty) {
      return '$reason\n(HTTP $statusCode)';
    }

    return '$reason\n(HTTP $statusCode)\n\n$trimmedBody';
  }
}
