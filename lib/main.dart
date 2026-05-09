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
        Provider(
          create: (_) => OfflineAiAsrService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider(
          create: (_) => OfflineAiTtsService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider(create: (context) => TtsService(context.read())),
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
            offlineAiAsrService: context.read(),
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
    return brightnessValue == 1 ? Brightness.light : Brightness.dark;
  }

  ThemeData _buildThemeData({
    required Color seedColor,
    required Brightness platformBrightness,
  }) {
    final brightness = _brightness ?? platformBrightness;
    final isDarkTheme = brightness == Brightness.dark;

    final colorScheme = isDarkTheme
        ? _buildChatGptDarkColorScheme(seedColor)
        : ColorScheme.fromSeed(
            brightness: Brightness.light,
            dynamicSchemeVariant: DynamicSchemeVariant.neutral,
            seedColor: seedColor,
          );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDarkTheme ? colorScheme.surface : null,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: isDarkTheme ? colorScheme.surface : null,
        foregroundColor: isDarkTheme ? colorScheme.onSurface : null,
        surfaceTintColor: isDarkTheme ? Colors.transparent : null,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDarkTheme ? colorScheme.surfaceContainerLow : null,
        surfaceTintColor: isDarkTheme ? Colors.transparent : null,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDarkTheme ? colorScheme.surfaceContainerHigh : null,
        surfaceTintColor: isDarkTheme ? Colors.transparent : null,
      ),
      cardTheme: CardThemeData(
        color: isDarkTheme ? colorScheme.surfaceContainer : null,
        surfaceTintColor: isDarkTheme ? Colors.transparent : null,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: isDarkTheme ? colorScheme.surface : null,
        surfaceTintColor: isDarkTheme ? Colors.transparent : null,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: isDarkTheme,
        fillColor: isDarkTheme ? colorScheme.surfaceContainerLow : null,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: isDarkTheme
            ? colorScheme.primary.withValues(alpha: 0.38)
            : colorScheme.primary.withValues(alpha: 0.24),
        selectionHandleColor: colorScheme.primary,
      ),
      menuTheme: MenuThemeData(
        style: isDarkTheme
            ? MenuStyle(
                backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainer),
                surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
              )
            : null,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDarkTheme ? colorScheme.surfaceContainer : null,
        surfaceTintColor: isDarkTheme ? Colors.transparent : null,
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: isDarkTheme ? colorScheme.surface : null,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: isDarkTheme ? colorScheme.onSurface : null,
        textColor: isDarkTheme ? colorScheme.onSurface : null,
      ),
      useMaterial3: true,
    );
  }

  ColorScheme _buildChatGptDarkColorScheme(Color seedColor) {
    final base = ColorScheme.fromSeed(
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.neutral,
      seedColor: seedColor,
    );

    return base.copyWith(
      brightness: Brightness.dark,
      surface: const Color(0xFF0B0B0B),
      onSurface: const Color(0xFFF4F4F4),
      surfaceDim: const Color(0xFF060606),
      surfaceBright: const Color(0xFF2B2B2B),
      surfaceContainerLowest: const Color(0xFF050505),
      surfaceContainerLow: const Color(0xFF151515),
      surfaceContainer: const Color(0xFF202020),
      surfaceContainerHigh: const Color(0xFF2F2F2F),
      surfaceContainerHighest: const Color(0xFF3A3A3A),
      onSurfaceVariant: const Color(0xFFC8C8C8),
      outline: const Color(0xFF5A5A5A),
      outlineVariant: const Color(0xFF343434),
      inverseSurface: const Color(0xFFF4F4F4),
      onInverseSurface: const Color(0xFF101010),
      primary: base.primary.withValues(alpha: 0.92),
      primaryContainer: Color.alphaBlend(
        base.primary.withValues(alpha: 0.28),
        const Color(0xFF2B2B2B),
      ),
      onPrimaryContainer: const Color(0xFFFFFFFF),
      secondaryContainer: Color.alphaBlend(
        base.secondary.withValues(alpha: 0.12),
        const Color(0xFF303030),
      ),
      tertiaryContainer: Color.alphaBlend(
        base.tertiary.withValues(alpha: 0.12),
        const Color(0xFF303030),
      ),
      shadow: Colors.black,
      scrim: Colors.black,
    );
  }
}
