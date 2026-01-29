import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/jira_models.dart';
import '../services/storage_service.dart';
import '../services/jira_api_service.dart';

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
  bool _showLogoutConfirm = false;
  String _boardSearch = '';

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
      _showSnack('Please enter your email', isError: true);
      return;
    }
    if (jiraUrl.isEmpty) {
      _showSnack('Please enter your Jira URL', isError: true);
      return;
    }
    try {
      Uri.parse(jiraUrl);
    } catch (_) {
      _showSnack('Please enter a valid URL', isError: true);
      return;
    }
    if (apiToken.isEmpty) {
      _showSnack('Please enter your API token', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final config = JiraConfig(email: email, jiraUrl: jiraUrl, apiToken: apiToken);
      final api = context.read<JiraApiService>();
      api.initialize(config);
      final connected = await api.testConnection();
      if (!connected) {
        _showSnack('Unable to connect to Jira. Please check your credentials.', isError: true);
        setState(() => _saving = false);
        return;
      }
      await context.read<StorageService>().saveConfig(config);
      _showSnack('Settings saved successfully!');
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) widget.onBack();
    } catch (_) {
      _showSnack('Failed to save settings.', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveDefaultBoard() async {
    if (_tempSelectedBoardId == null) return;
    try {
      await context.read<StorageService>().setDefaultBoardId(_tempSelectedBoardId!);
      setState(() => _defaultBoardId = _tempSelectedBoardId);
      _showSnack('Default board saved');
    } catch (_) {
      _showSnack('Failed to save default board', isError: true);
    }
  }

  void _confirmLogout() async {
    try {
      await context.read<StorageService>().clearConfig();
      context.read<JiraApiService>().reset();
      setState(() => _showLogoutConfirm = false);
      widget.onLogout();
    } catch (_) {
      _showSnack('Failed to logout', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF0052CC),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          leading: IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
          title: const Text('Settings'),
          backgroundColor: const Color(0xFF0052CC),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF0052CC))),
      );
    }

    final scaffold = Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF0052CC),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Jira Configuration',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF333333)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFFF9F9F9),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _jiraUrlController,
              decoration: const InputDecoration(
                labelText: 'Jira URL',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFFF9F9F9),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiTokenController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Token',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFFF9F9F9),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Generate a new API token at:\nhttps://id.atlassian.com/manage-profile/security/api-tokens',
              style: TextStyle(fontSize: 12, color: Color(0xFF666666), height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0052CC),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 32),
            const Text(
              'Default Board',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select a default board to automatically load on startup.',
              style: TextStyle(fontSize: 14, color: Color(0xFF5E6C84), height: 1.3),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => setState(() => _showBoardPicker = true),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F9F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _tempSelectedBoardId != null
                            ? (_boards.where((b) => b.id == _tempSelectedBoardId).firstOrNull?.name ?? 'Select a board')
                            : 'Select a board',
                        style: const TextStyle(fontSize: 15, color: Color(0xFF172B4D)),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Color(0xFF5E6C84)),
                  ],
                ),
              ),
            ),
            if (_tempSelectedBoardId != _defaultBoardId) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _saveDefaultBoard,
                child: const Text('Save Default Board'),
              ),
            ],
            const SizedBox(height: 32),
            const Text(
              'Account',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() => _showLogoutConfirm = true),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDE350B),
                side: const BorderSide(color: Color(0xFFDE350B)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Logout', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 32),
            const Center(
              child: Text('Jira Manager v1.0.0', style: TextStyle(fontSize: 14, color: Color(0xFF999999))),
            ),
          ],
        ),
      ),
      bottomSheet: _showBoardPicker ? _buildBoardPicker() : null,
    );

    return Stack(
      children: [
        scaffold,
        if (_showLogoutConfirm) _buildLogoutDialog(),
      ],
    );
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
                const Text('Select Default Board', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
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
              decoration: const InputDecoration(
                hintText: 'Search boards...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
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
                  trailing: selected ? const Icon(Icons.check, color: Color(0xFF0052CC)) : null,
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

  Widget _buildLogoutDialog() {
    return GestureDetector(
      onTap: () => setState(() => _showLogoutConfirm = false),
      child: Material(
        color: Colors.black54,
        child: Center(
          child: GestureDetector(
            onTap: () {}, // block tap from closing when tapping the card
            child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Logout', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              const Text(
                'Are you sure you want to logout? This will clear all your credentials.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Color(0xFF5E6C84), height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _showLogoutConfirm = false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _confirmLogout,
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDE350B)),
                      child: const Text('Logout'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
        ),
      ),
    );
  }
}
