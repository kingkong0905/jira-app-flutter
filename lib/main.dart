import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/storage_service.dart';
import 'services/jira_api_service.dart';
import 'services/sentry_api_service.dart';
import 'l10n/app_localizations.dart';
import 'l10n/locale_notifier.dart';

void main() {
  runApp(const JiraApp());
}

class JiraApp extends StatelessWidget {
  const JiraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => StorageService()),
        Provider(create: (_) => JiraApiService()),
        Provider(create: (_) => SentryApiService()),
        ChangeNotifierProvider(
          create: (c) => LocaleNotifier(c.read<StorageService>()),
        ),
      ],
      child: Consumer<LocaleNotifier>(
        builder: (context, localeNotifier, _) => MaterialApp(
          title: AppTheme.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.system,
          locale: localeNotifier.locale,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            AppLocalizationsDelegate(),
            ...FlutterQuillLocalizations.localizationsDelegates,
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('vi'),
          ],
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
