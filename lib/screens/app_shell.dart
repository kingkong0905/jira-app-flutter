import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/jira_models.dart';
import '../services/storage_service.dart';
import '../services/jira_api_service.dart';
import 'setup_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// Root shell: checks config on start, shows Setup / Home / Settings.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _loading = true;
  bool _showSetup = true;

  @override
  void initState() {
    super.initState();
    _checkConfiguration();
  }

  Future<void> _checkConfiguration() async {
    final storage = context.read<StorageService>();
    final api = context.read<JiraApiService>();
    try {
      final configured = await storage.isConfigured();
      if (configured) {
        final config = await storage.getConfig();
        if (config != null) {
          api.initialize(config);
          if (mounted) setState(() { _showSetup = false; });
        }
      }
    } catch (_) {}
    if (mounted) setState(() { _loading = false; });
  }

  void _onSetupComplete() {
    setState(() { _showSetup = false; });
  }

  void _onLogout() {
    context.read<JiraApiService>().reset();
    setState(() { _showSetup = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F5),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF0052CC)),
              SizedBox(height: 16),
              Text('Loading...', style: TextStyle(color: Color(0xFF666666), fontSize: 16)),
            ],
          ),
        ),
      );
    }

    if (_showSetup) {
      return SetupScreen(onComplete: _onSetupComplete);
    }

    return HomeScreen(
      onOpenSettings: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => SettingsScreen(
            onBack: () => Navigator.of(context).pop(),
            onLogout: () {
              Navigator.of(context).pop();
              _onLogout();
            },
          ),
        ),
      ),
    );
  }
}
