import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

import 'package:reins/Constants/constants.dart';
import 'package:reins/Pages/chat_search_page.dart';
import 'package:reins/Providers/chat_provider.dart';
import 'package:reins/Widgets/chat_configure_bottom_sheet.dart';
import 'package:reins/Widgets/model_selection_bottom_sheet.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();

    return AppBar(
      title: Column(
        children: [
          Text(AppConstants.appName, style: GoogleFonts.pacifico()),
          if (chatProvider.currentChat != null)
            InkWell(
              onTap: () => _handleModelSelectionButton(context),
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  chatProvider.currentChat!.model,
                  style: GoogleFonts.kodeMono(
                    textStyle: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search_rounded),
          onPressed: () => _handleSearchButton(context),
        ),
        IconButton(
          icon: const Icon(Icons.tune),
          onPressed: () => _handleConfigureButton(context),
        ),
      ],
      forceMaterialTransparency: !ResponsiveBreakpoints.of(context).isMobile,
    );
  }

  Future<void> _handleModelSelectionButton(BuildContext context) async {
    final chatProvider = context.read<ChatProvider>();

    final selectedModel = await showModelSelectionBottomSheet(
      context: context,
      title: 'Сменить модель',
      currentModelName: chatProvider.currentChat?.model,
    );

    if (selectedModel != null) {
      await chatProvider.updateCurrentChat(newModel: selectedModel.name);
    }
  }

  Future<void> _handleSearchButton(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ChatSearchPage(),
      ),
    );
  }

  Future<void> _handleConfigureButton(BuildContext context) async {
    final chatProvider = context.read<ChatProvider>();
    final arguments = chatProvider.currentChatConfiguration;

    final ChatConfigureBottomSheetAction? action = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Padding(
          padding: MediaQuery.of(context).viewInsets,
          child: ChatConfigureBottomSheet(arguments: arguments),
        );
      },
    );

    if (action == ChatConfigureBottomSheetAction.delete) return;

    await chatProvider.updateCurrentChat(
      newSystemPrompt: arguments.systemPrompt,
      newOptions: arguments.chatOptions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
