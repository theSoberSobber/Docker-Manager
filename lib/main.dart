import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'data/services/subscription_service.dart';
import 'data/services/notification_service.dart';
import 'data/repositories/server_repository_impl.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/notification_setup_screen.dart';
import 'presentation/screens/command_prompt_screen.dart';
import 'presentation/widgets/theme_manager.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  
  // Initialize Firebase (required before FCM)
  await Firebase.initializeApp();
  
  // Initialize subscription service (RevenueCat)
  await SubscriptionService().init();
  
  // Initialize notification channels (does NOT request permission)
  await NotificationService().init();
  
  // Setup notification tap routing
  NotificationService().onNotificationTapped.listen((payload) async {
    final serverId = payload['server_id'];
    final action = payload['action'];
    final eventType = payload['event_type'];
    
    if (serverId != null && navigatorKey.currentContext != null) {
      if (eventType == 'system' && action == 'update_available') {
        final repo = ServerRepositoryImpl();
        final server = await repo.getServer(serverId);
        
        if (server != null) {
          final url = payload['changelog_url'];
          Navigator.of(navigatorKey.currentContext!).push(
            MaterialPageRoute(
              builder: (_) => NotificationSetupScreen(
                server: server,
                promptUpdate: true,
                changelogUrl: url,
              ),
            ),
          );
        }
      } else if (eventType == 'system' && action == 'prompt_command') {
        final repo = ServerRepositoryImpl();
        final server = await repo.getServer(serverId);
        
        if (server != null) {
          final title = payload['title'] ?? 'Action Required';
          final body = payload['body'] ?? 'Review the command below.';
          final command = payload['command'] ?? '';
          
          Navigator.of(navigatorKey.currentContext!).push(
            MaterialPageRoute(
              builder: (_) => CommandPromptScreen(
                server: server,
                title: title,
                bodyText: body,
                command: command,
              ),
            ),
          );
        }
      }
      // Future: route container events elsewhere
    }
  });
  
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
          navigatorKey: navigatorKey,
          title: 'Docker Manager',
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
