import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import 'presentation/screens/home_screen.dart';
import 'presentation/widgets/theme_manager.dart';
import 'data/services/analytics_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await AnalyticsService().initializeIfConsented();
  
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US'), Locale('es'), Locale('fr', 'FR')],
      path: 'assets/i18n',
      fallbackLocale: const Locale('en', 'US'),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeManager(),
      builder: (context, child) {
        return MaterialApp(
          title: 'Docker Manager',
          navigatorObservers: [PosthogObserver()],
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              elevation: 1,
            ),
            cardTheme: const CardThemeData(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFF121212),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              elevation: 1,
            ),
            cardTheme: const CardThemeData(
              elevation: 4,
              color: Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              elevation: 8,
            ),
          ),
          themeMode: ThemeManager().themeMode,
          home: const HomeScreen(),
        );
      },
    );
  }
}
