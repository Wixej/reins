import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:reins/Models/settings_route_arguments.dart';

import 'subwidgets/subwidgets.dart';

class SettingsPage extends StatelessWidget {
  final SettingsRouteArguments? arguments;

  const SettingsPage({
    super.key,
    this.arguments,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Настройки',
          style: GoogleFonts.pacifico(),
        ),
      ),
      body: SafeArea(
        child: _SettingsPageContent(arguments: arguments),
      ),
    );
  }
}

class _SettingsPageContent extends StatelessWidget {
  final SettingsRouteArguments? arguments;

  const _SettingsPageContent({
    required this.arguments,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const ReinsSettings(),
        const SizedBox(height: 16),
        ThemesSettings(),
        const SizedBox(height: 16),
        ServerSettings(
          autoFocusServerAddress: arguments?.autoFocusServerAddress ?? false,
        ),
        const SizedBox(height: 16),
        const VoiceSettings(),
        const SizedBox(height: 16),
        const UserFactsSettings(),
        const SizedBox(height: 16),
        const InternetSearchSettings(),
      ],
    );
  }
}
