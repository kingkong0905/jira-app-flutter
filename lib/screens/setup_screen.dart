import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/jira_models.dart';
import '../services/storage_service.dart';
import '../services/jira_api_service.dart';
import '../l10n/app_localizations.dart';
import '../widgets/logo.dart';

/// Setup: Step 1 = API Token, Step 2 = Email + Jira URL, then test connection and save.
class SetupScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SetupScreen({super.key, required this.onComplete});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _step = 1;
  final _apiTokenController = TextEditingController();
  final _emailController = TextEditingController();
  final _jiraUrlController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _apiTokenController.dispose();
    _emailController.dispose();
    _jiraUrlController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_apiTokenController.text.trim().isEmpty) {
      _showSnack(AppLocalizations.of(context).pleaseEnterApiToken, isError: true);
      return;
    }
    setState(() => _step = 2);
  }

  void _back() {
    setState(() => _step = 1);
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final jiraUrl = _jiraUrlController.text.trim().replaceAll(RegExp(r'/$'), '');
    final apiToken = _apiTokenController.text.trim();

    if (email.isEmpty) {
      _showSnack(AppLocalizations.of(context).pleaseEnterEmail, isError: true);
      return;
    }
    if (jiraUrl.isEmpty) {
      _showSnack(AppLocalizations.of(context).pleaseEnterJiraUrl, isError: true);
      return;
    }
    try {
      Uri.parse(jiraUrl);
    } catch (_) {
      _showSnack(AppLocalizations.of(context).pleaseEnterValidUrlExample, isError: true);
      return;
    }

    setState(() => _loading = true);
    try {
      final normalizedUrl = JiraApiService.normalizeJiraUrl(jiraUrl);
      final config = JiraConfig(email: email, jiraUrl: normalizedUrl, apiToken: apiToken);
      final api = context.read<JiraApiService>();
      api.initialize(config);

      final errorMessage = await api.testConnectionResult();
      if (errorMessage != null) {
        _showSnack(errorMessage, isError: true);
        setState(() => _loading = false);
        return;
      }

      await context.read<StorageService>().saveConfig(config);
      _showSnack(AppLocalizations.of(context).configurationSavedSuccess);
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) widget.onComplete();
    } catch (e, stack) {
      debugPrint('[SetupScreen] saveConfig error: $e');
      debugPrint('[SetupScreen] $stack');
      final msg = e.toString();
      _showSnack(AppLocalizations.of(context).failedToSave(msg.length > 60 ? '${msg.substring(0, 60)}...' : msg), isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : AppTheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _stepDot(active: _step >= 1, completed: _step > 1),
        Container(
          width: 32,
          height: 2,
          color: _step > 1 ? Colors.white : Colors.white.withValues(alpha: 0.4),
        ),
        _stepDot(active: _step >= 2, completed: false),
      ],
    );
  }

  Widget _stepDot({required bool active, required bool completed}) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: completed ? Colors.white : (active ? Colors.white : Colors.white.withValues(alpha: 0.4)),
        border: active && !completed ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: completed
          ? const Icon(Icons.check, size: 18, color: AppTheme.primary)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.primary, AppTheme.primaryLight],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Logo(),
              const SizedBox(height: 16),
              _buildStepIndicator(),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Card(
                    elevation: 10,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: _step == 1 ? _buildStep1() : _buildStep2(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppLocalizations.of(context).step1Of2,
          style: TextStyle(fontSize: 14, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          AppLocalizations.of(context).enterApiToken,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _apiTokenController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).apiToken,
            hintText: AppLocalizations.of(context).pasteApiToken,
            prefixIcon: const Icon(Icons.key),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: AppTheme.surfaceMuted,
          ),
          onSubmitted: (_) => _nextStep(),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primaryBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('💡', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).getApiTokenFrom,
                  style: TextStyle(fontSize: 13, color: AppTheme.primary, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _nextStep,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(AppLocalizations.of(context).next, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: _loading ? null : _back,
          icon: const Icon(Icons.arrow_back, size: 20),
          label: Text(AppLocalizations.of(context).back),
          style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
        ),
        const SizedBox(height: 8),
        Text(
          AppLocalizations.of(context).step2Of2,
          style: TextStyle(fontSize: 14, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          AppLocalizations.of(context).connectToJiraWorkspace,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).email,
            hintText: AppLocalizations.of(context).yourEmail,
            prefixIcon: const Icon(Icons.email),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: AppTheme.surfaceMuted,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _jiraUrlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).jiraUrl,
            hintText: AppLocalizations.of(context).jiraUrlPlaceholder,
            helperText: AppLocalizations.of(context).jiraCloudOnlyHint,
            prefixIcon: const Icon(Icons.link),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: AppTheme.surfaceMuted,
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _loading ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _loading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(AppLocalizations.of(context).letsGo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
