import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/jira_models.dart';
import '../services/storage_service.dart';
import '../services/jira_api_service.dart';
import '../l10n/app_localizations.dart';

/// Settings: email, Jira URL, API token, default board (native only), save, logout (same as reference app).
class SettingsScreen extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onLogout;

  const SettingsScreen({super.key, required this.onBack, required this.onLogout});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _emailController = TextEditingController();
  final _jiraUrlController = TextEditingController();
  final _apiTokenController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  List<JiraBoard> _boards = [];
  int? _defaultBoardId;
  int? _tempSelectedBoardId;
  bool _showBoardPicker = false;
  String _boardSearch = '';
  bool _apiTokenObscured = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _jiraUrlController.dispose();
    _apiTokenController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final storage = context.read<StorageService>();
    final api = context.read<JiraApiService>();
    try {
      final config = await storage.getConfig();
      if (config != null) {
        _emailController.text = config.email;
        _jiraUrlController.text = config.jiraUrl;
        _apiTokenController.text = config.apiToken;
        api.initialize(config);
        final boardId = await storage.getDefaultBoardId();
        setState(() {
          _defaultBoardId = boardId;
          _tempSelectedBoardId = boardId;
        });
        await _loadBoards();
        // Ensure default board is in the list so it displays as selected (it may not be in first page)
        if (mounted && boardId != null && _boards.where((b) => b.id == boardId).isEmpty) {
          try {
            final b = await api.getBoardById(boardId);
            if (b != null && mounted) setState(() => _boards = [b, ..._boards]);
          } catch (_) {}
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadBoards() async {
    final api = context.read<JiraApiService>();
    try {
      final res = await api.getBoards(startAt: 0, maxResults: 50, searchQuery: _boardSearch.isEmpty ? null : _boardSearch);
      setState(() => _boards = res.boards);
    } catch (_) {
      setState(() => _boards = []);
    }
  }

  Future<void> _save() async {
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
      _showSnack(AppLocalizations.of(context).pleaseEnterValidUrl, isError: true);
      return;
    }
    if (apiToken.isEmpty) {
      _showSnack(AppLocalizations.of(context).pleaseEnterApiToken, isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final normalizedUrl = JiraApiService.normalizeJiraUrl(jiraUrl);
      final config = JiraConfig(email: email, jiraUrl: normalizedUrl, apiToken: apiToken);
      final api = context.read<JiraApiService>();
      api.initialize(config);
      final errorMessage = await api.testConnectionResult();
      if (errorMessage != null) {
        _showSnack(errorMessage, isError: true);
        setState(() => _saving = false);
        return;
      }
      await context.read<StorageService>().saveConfig(config);
      _showSnack(AppLocalizations.of(context).settingsSavedSuccess);
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) widget.onBack();
    } catch (_) {
      _showSnack(AppLocalizations.of(context).failedToSaveSettings, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveDefaultBoard() async {
    if (_tempSelectedBoardId == null) return;
    try {
      await context.read<StorageService>().setDefaultBoardId(_tempSelectedBoardId!);
      setState(() => _defaultBoardId = _tempSelectedBoardId);
      _showSnack(AppLocalizations.of(context).defaultBoardSaved);
    } catch (_) {
      _showSnack(AppLocalizations.of(context).failedToSaveDefaultBoard, isError: true);
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

  Widget _buildSection({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppTheme.textPrimary),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
          ),
        ],
        const SizedBox(height: AppTheme.spaceLg),
        ...children,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back), tooltip: AppLocalizations.of(context).back),
          title: Text(AppLocalizations.of(context).settings),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final scaffold = Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back), tooltip: 'Back'),
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spaceXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSection(
              title: AppLocalizations.of(context).jiraConfiguration,
              children: [
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).email,
                    prefixIcon: Icon(Icons.email_outlined, size: 20),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: AppTheme.spaceLg),
                TextField(
                  controller: _jiraUrlController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).jiraUrl,
                    prefixIcon: Icon(Icons.link, size: 20),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: AppTheme.spaceLg),
                TextField(
                  controller: _apiTokenController,
                  obscureText: _apiTokenObscured,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).apiToken,
                    prefixIcon: const Icon(Icons.key, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(_apiTokenObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 22),
                      onPressed: () => setState(() => _apiTokenObscured = !_apiTokenObscured),
                      tooltip: _apiTokenObscured ? AppLocalizations.of(context).showToken : AppLocalizations.of(context).hideToken,
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spaceSm),
                Text(
                  AppLocalizations.of(context).apiTokenHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
                ),
                const SizedBox(height: AppTheme.spaceLg),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _saving
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(AppLocalizations.of(context).saveChanges, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceXxl),
            _buildSection(
              title: AppLocalizations.of(context).defaultBoard,
              subtitle: AppLocalizations.of(context).defaultBoardSubtitle,
              children: [
                InkWell(
                  onTap: () => setState(() => _showBoardPicker = true),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color ?? AppTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.dashboard_outlined, size: 22, color: AppTheme.textMuted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _tempSelectedBoardId != null
                                ? (_boards.where((b) => b.id == _tempSelectedBoardId).firstOrNull?.name ?? AppLocalizations.of(context).selectBoard)
                                : AppLocalizations.of(context).selectBoard,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
                      ],
                    ),
                  ),
                ),
                if (_tempSelectedBoardId != _defaultBoardId) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  OutlinedButton(
                    onPressed: _saveDefaultBoard,
                    child: Text(AppLocalizations.of(context).saveDefaultBoard),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppTheme.spaceXxl),
            Center(
              child: Text(
                '${AppTheme.appName} ${AppTheme.appVersion}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: _showBoardPicker ? _buildBoardPicker() : null,
    );

    return scaffold;
  }

  Widget _buildBoardPicker() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(AppLocalizations.of(context).selectDefaultBoard, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  onPressed: () => setState(() => _showBoardPicker = false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: (v) async {
                setState(() => _boardSearch = v);
                await _loadBoards();
              },
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).searchBoards,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _boards.length,
              itemBuilder: (context, i) {
                final b = _boards[i];
                final selected = _tempSelectedBoardId == b.id;
                return ListTile(
                  leading: Icon(b.type.toLowerCase() == 'kanban' ? Icons.view_kanban : Icons.directions_run),
                  title: Text(b.name),
                  subtitle: b.location?.projectName != null ? Text(b.location!.projectName!) : null,
                  trailing: selected ? const Icon(Icons.check, color: AppTheme.primary) : null,
                  onTap: () {
                    setState(() {
                      _tempSelectedBoardId = b.id;
                      _showBoardPicker = false;
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

}
