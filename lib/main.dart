import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'screens/app_shell.dart';
import 'services/storage_service.dart';
import 'services/jira_api_service.dart';

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
      ],
      child: MaterialApp(
        title: 'Jira Management',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0052CC), brightness: Brightness.light),
          useMaterial3: true,
        ),
        localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
        supportedLocales: FlutterQuillLocalizations.supportedLocales,
        home: const AppShell(),
      ),
    );
  }
}
