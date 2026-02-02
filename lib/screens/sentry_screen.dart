import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/storage_service.dart';
import '../services/sentry_api_service.dart';
import '../l10n/app_localizations.dart';
import 'sentry_issue_detail_screen.dart';

/// Sentry page: input for Sentry issue URL, button to fetch and show issue detail via API.
class SentryScreen extends StatefulWidget {
  final VoidCallback onBack;

  const SentryScreen({super.key, required this.onBack});

  @override
  State<SentryScreen> createState() => _SentryScreenState();
}

class _SentryScreenState extends State<SentryScreen> {
  final _urlController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _viewIssue() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _showSnack(AppLocalizations.of(context).invalidSentryLink, isError: true);
      return;
    }

    final parts = SentryApiService.parseIssueUrl(url);
    if (parts == null) {
      _showSnack(AppLocalizations.of(context).invalidSentryLink, isError: true);
      return;
    }

    setState(() => _loading = true);
    try {
      final storage = context.read<StorageService>();
      final api = context.read<SentryApiService>();
      final token = await storage.getSentryApiToken();
      final detail = await api.getIssueDetail(parts: parts, authToken: token);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => SentryIssueDetailScreen(
            detail: detail,
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
      );
    } on SentryApiException catch (e) {
      if (mounted) _showSnack(e.message, isError: true);
    } catch (e) {
      if (mounted) _showSnack(e.toString(), isError: true);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: Text(l10n.sentry),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  hintText: l10n.sentryLinkHint,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                maxLines: 2,
                enabled: !_loading,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loading ? null : _viewIssue,
                icon: _loading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                      )
                    : const Icon(Icons.bug_report, size: 22),
                label: Text(_loading ? l10n.loading : l10n.viewSentryIssue),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
