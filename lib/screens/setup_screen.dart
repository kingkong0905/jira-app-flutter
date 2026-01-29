import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/jira_models.dart';
import '../services/storage_service.dart';
import '../services/jira_api_service.dart';
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
      _showSnack('Please enter your API token', isError: true);
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
      _showSnack('Please enter a valid URL (e.g. https://your-domain.atlassian.net)', isError: true);
      return;
    }

    setState(() => _loading = true);
    try {
      final config = JiraConfig(email: email, jiraUrl: jiraUrl, apiToken: apiToken);
      final api = context.read<JiraApiService>();
      api.initialize(config);

      final connected = await api.testConnection();
      if (!connected) {
        _showSnack('Unable to connect to Jira. Please check your credentials and try again.', isError: true);
        setState(() => _loading = false);
        return;
      }

      await context.read<StorageService>().saveConfig(config);
      _showSnack('Configuration saved successfully!');
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) widget.onComplete();
    } catch (e) {
      _showSnack('Failed to save configuration. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
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
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0052CC), Color(0xFF2684FF)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),
              const Logo(),
              const SizedBox(height: 24),
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
          'Step 1 of 2',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your API Token',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF172B4D)),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _apiTokenController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'API Token',
            hintText: 'Paste your API token',
            prefixIcon: const Icon(Icons.key),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: const Color(0xFFF4F5F7),
          ),
          onSubmitted: (_) => _nextStep(),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFDEEBFF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('💡', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Generate an API token at:\nid.atlassian.com/manage-profile/security/api-tokens',
                  style: TextStyle(fontSize: 13, color: Color(0xFF0052CC), height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _nextStep,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0052CC),
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Next →', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
          label: const Text('Back'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF0052CC)),
        ),
        const SizedBox(height: 8),
        Text(
          'Step 2 of 2',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Connect to your Jira workspace',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF172B4D)),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Email',
            hintText: 'your@email.com',
            prefixIcon: const Icon(Icons.email),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: const Color(0xFFF4F5F7),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _jiraUrlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Jira URL',
            hintText: 'https://your-domain.atlassian.net',
            prefixIcon: const Icon(Icons.link),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: const Color(0xFFF4F5F7),
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _loading ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0052CC),
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _loading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text("Let's Go!", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
