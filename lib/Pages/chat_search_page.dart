import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reins/Models/chat_search_result.dart';
import 'package:reins/Models/ollama_message.dart';
import 'package:reins/Providers/chat_provider.dart';

class ChatSearchPage extends StatefulWidget {
  const ChatSearchPage({super.key});

  @override
  State<ChatSearchPage> createState() => _ChatSearchPageState();
}

class _ChatSearchPageState extends State<ChatSearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  Future<List<ChatSearchResult>> _resultsFuture = Future.value(const []);

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Поиск по чатам',
            border: InputBorder.none,
          ),
          onChanged: _scheduleSearch,
          onSubmitted: _searchNow,
        ),
        actions: [
          IconButton(
            tooltip: 'Очистить',
            onPressed: () {
              _controller.clear();
              _searchNow('');
            },
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<ChatSearchResult>>(
        future: _resultsFuture,
        builder: (context, snapshot) {
          final query = _controller.text.trim();
          if (query.isEmpty) {
            return const _SearchEmptyState(
              icon: Icons.search_rounded,
              title: 'Введите текст для поиска',
              subtitle: 'Ищу по сообщениям во всех чатах.',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final results = snapshot.data ?? const [];
          if (results.isEmpty) {
            return const _SearchEmptyState(
              icon: Icons.manage_search_rounded,
              title: 'Ничего не найдено',
              subtitle: 'Попробуйте другое слово или фразу.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: results.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final result = results[index];
              return ListTile(
                leading: Icon(_roleIcon(result.role)),
                title: Text(
                  result.chatTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  result.snippetFor(query),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(TimeOfDay.fromDateTime(result.createdAt.toLocal()).format(context)),
                onTap: () => _openResult(result),
              );
            },
          );
        },
      ),
    );
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _searchNow(value));
  }

  void _searchNow(String value) {
    final query = value.trim();
    setState(() {
      _resultsFuture = query.isEmpty ? Future.value(const []) : context.read<ChatProvider>().searchMessages(query);
    });
  }

  Future<void> _openResult(ChatSearchResult result) async {
    await context.read<ChatProvider>().selectChatById(result.chatId);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  IconData _roleIcon(OllamaMessageRole role) {
    return switch (role) {
      OllamaMessageRole.user => Icons.person_outline_rounded,
      OllamaMessageRole.assistant => Icons.smart_toy_outlined,
      OllamaMessageRole.system => Icons.tune_rounded,
    };
  }
}

class _SearchEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SearchEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
