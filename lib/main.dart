import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:reins/Constants/constants.dart';
import 'package:reins/Models/settings_route_arguments.dart';
import 'package:reins/Pages/chat_page/chat_page_view_model.dart';
import 'package:reins/Pages/main_page.dart';
import 'package:reins/Pages/settings_page/settings_page.dart';
import 'package:reins/Providers/chat_provider.dart';
import 'package:reins/Services/services.dart';
import 'package:reins/Utils/material_color_adapter.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:reins/Utils/request_review_helper.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize PathManager
  await PathManager.initialize();

  // Initialize Hive
  if (Platform.isLinux) {
    Hive.init(PathManager.instance.documentsDirectory.path);
  } else {
    await Hive.initFlutter();
  }

  Hive.registerAdapter(MaterialColorAdapter());

  await Hive.openBox('settings');

  // Initialize RequestReviewHelper and request review if needed
  final reviewHelper = await RequestReviewHelper.initialize();

  await reviewHelper.incrementCount(isLaunch: true);

  final inAppReview = InAppReview.instance;
  if (await inAppReview.isAvailable() && reviewHelper.shouldRequestReview()) {
    await inAppReview.requestReview();
  }

  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => OllamaService()),
        Provider(create: (_) => DatabaseService()),
        Provider(create: (_) => PermissionService()),
        Provider(create: (_) => ImageService()),
        Provider(create: (_) => DocumentService()),
        Provider(create: (_) => SpeechService()),
        Provider(create: (_) => TtsService()),
        ChangeNotifierProvider(
          create: (context) => ChatProvider(
            ollamaService: context.read(),
            databaseService: context.read(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => ChatPageViewModel(
            chatProvider: context.read(),
            permissionService: context.read(),
            imageService: context.read(),
            documentService: context.read(),
            speechService: context.read(),
            ttsService: context.read(),
          ),
        ),
      ],
      child: const ReinsApp(),
    ),
  );
}

class ReinsApp extends StatelessWidget {
  const ReinsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('settings').listenable(
        keys: ['color', 'brightness'],
      ),
      builder: (context, box, _) {
        final seedColor = box.get('color', defaultValue: Colors.grey) as Color;

        return MaterialApp(
          title: AppConstants.appName,
          theme: _buildThemeData(
            seedColor: seedColor,
            platformBrightness: MediaQuery.platformBrightnessOf(context),
          ),
          builder: (context, child) => ResponsiveBreakpoints.builder(
            breakpoints: [
              const Breakpoint(start: 0, end: 450, name: MOBILE),
              const Breakpoint(start: 451, end: 800, name: TABLET),
              const Breakpoint(start: 801, end: 1920, name: DESKTOP),
            ],
            useShortestSide: true,
            child: child!,
          ),
          onGenerateRoute: (settings) {
            if (settings.name == '/') {
              return MaterialPageRoute(
                builder: (context) => const ReinsMainPage(),
              );
            }

            if (settings.name == '/settings') {
              final args = settings.arguments as SettingsRouteArguments?;

              return MaterialPageRoute(
                builder: (context) => SettingsPage(arguments: args),
              );
            }

            assert(false, 'Need to implement ${settings.name}');
            return null;
          },
        );
      },
    );
  }

  Brightness? get _brightness {
    final brightnessValue = Hive.box('settings').get('brightness');
    if (brightnessValue == null) return null;
    if (brightnessValue == 2) return Brightness.dark;
    return brightnessValue == 1 ? Brightness.light : Brightness.dark;
  }

  ThemeData _buildThemeData({
    required Color seedColor,
    required Brightness platformBrightness,
  }) {
    final brightnessValue = Hive.box('settings').get('brightness');
    final isBlackTheme = brightnessValue == 2;

    final colorScheme = isBlackTheme
        ? _buildBlackColorScheme(seedColor)
        : ColorScheme.fromSeed(
            brightness: _brightness ?? platformBrightness,
            dynamicSchemeVariant: DynamicSchemeVariant.neutral,
            seedColor: seedColor,
          );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isBlackTheme ? colorScheme.surface : null,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: isBlackTheme ? colorScheme.surfaceContainerLow : null,
        foregroundColor: isBlackTheme ? colorScheme.onSurface : null,
        surfaceTintColor: isBlackTheme ? Colors.transparent : null,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isBlackTheme ? colorScheme.surfaceContainerLow : null,
        surfaceTintColor: isBlackTheme ? Colors.transparent : null,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isBlackTheme ? colorScheme.surfaceContainerHigh : null,
        surfaceTintColor: isBlackTheme ? Colors.transparent : null,
      ),
      cardTheme: CardThemeData(
        color: isBlackTheme ? colorScheme.surfaceContainer : null,
        surfaceTintColor: isBlackTheme ? Colors.transparent : null,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: isBlackTheme ? colorScheme.surfaceContainerLow : null,
        surfaceTintColor: isBlackTheme ? Colors.transparent : null,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: isBlackTheme,
        fillColor: isBlackTheme ? colorScheme.surfaceContainerLow : null,
      ),
      useMaterial3: true,
    );
  }

  ColorScheme _buildBlackColorScheme(Color seedColor) {
    final base = ColorScheme.fromSeed(
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.neutral,
      seedColor: seedColor,
    );

    return base.copyWith(
      brightness: Brightness.dark,
      surface: const Color(0xFF050606),
      onSurface: const Color(0xFFE7ECEA),
      surfaceDim: const Color(0xFF030404),
      surfaceBright: const Color(0xFF1E2525),
      surfaceContainerLowest: const Color(0xFF030404),
      surfaceContainerLow: const Color(0xFF090C0C),
      surfaceContainer: const Color(0xFF101414),
      surfaceContainerHigh: const Color(0xFF161C1C),
      surfaceContainerHighest: const Color(0xFF1D2525),
      onSurfaceVariant: const Color(0xFFBBC8C5),
      outline: const Color(0xFF72807D),
      outlineVariant: const Color(0xFF2B3534),
      inverseSurface: const Color(0xFFE1E7E5),
      onInverseSurface: const Color(0xFF111616),
      primary: base.primary.withValues(alpha: 0.92),
      primaryContainer: Color.alphaBlend(
        base.primary.withValues(alpha: 0.18),
        const Color(0xFF121919),
      ),
      onPrimaryContainer: const Color(0xFFEAF6F3),
      secondaryContainer: Color.alphaBlend(
        base.secondary.withValues(alpha: 0.14),
        const Color(0xFF121919),
      ),
      tertiaryContainer: Color.alphaBlend(
        base.tertiary.withValues(alpha: 0.14),
        const Color(0xFF121919),
      ),
      shadow: Colors.black,
      scrim: Colors.black,
    );
  }
}
