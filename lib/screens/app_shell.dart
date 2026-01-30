import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../services/jira_api_service.dart';
import '../l10n/app_localizations.dart';
import 'setup_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// Root shell: checks config on start (or uses initial from Splash), shows Setup / Home / Settings.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.initialLoading,
    this.initialShowSetup,
  });

  /// If set, skip loading and use [initialShowSetup] to show Setup vs Home.
  final bool? initialLoading;
  final bool? initialShowSetup;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _loading = true;
  bool _showSetup = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialLoading != null && widget.initialShowSetup != null) {
      setState(() {
        _loading = false;
        _showSetup = widget.initialShowSetup!;
      });
      return;
    }
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

  Future<void> _onLogout() async {
    try {
      await context.read<StorageService>().clearConfig();
    } catch (_) {}
    context.read<JiraApiService>().reset();
    if (mounted) setState(() { _showSetup = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context).loading,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
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
            onLogout: _onLogout,
          ),
        ),
      ),
      onLogout: _onLogout,
    );
  }
}
