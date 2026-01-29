import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/jira_models.dart';

/// Secure storage for Jira config (same keys and behavior as reference app).
class StorageService {
  StorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  static const _email = 'jira_email';
  static const _jiraUrl = 'jira_url';
  static const _apiToken = 'jira_api_token';
  static const _isConfigured = 'jira_is_configured';
  static const _defaultBoardId = 'jira_default_board_id';

  final FlutterSecureStorage _storage;

  Future<void> saveConfig(JiraConfig config) async {
    await _storage.write(key: _email, value: config.email);
    await _storage.write(key: _jiraUrl, value: config.jiraUrl);
    await _storage.write(key: _apiToken, value: config.apiToken);
    await _storage.write(key: _isConfigured, value: 'true');
  }

  Future<JiraConfig?> getConfig() async {
    final email = await _storage.read(key: _email);
    final jiraUrl = await _storage.read(key: _jiraUrl);
    final apiToken = await _storage.read(key: _apiToken);
    if (email != null && jiraUrl != null && apiToken != null) {
      return JiraConfig(email: email, jiraUrl: jiraUrl, apiToken: apiToken);
    }
    return null;
  }

  Future<bool> isConfigured() async {
    final v = await _storage.read(key: _isConfigured);
    return v == 'true';
  }

  Future<void> clearConfig() async {
    await _storage.delete(key: _email);
    await _storage.delete(key: _jiraUrl);
    await _storage.delete(key: _apiToken);
    await _storage.delete(key: _isConfigured);
    await _storage.delete(key: _defaultBoardId);
  }

  Future<void> setDefaultBoardId(int boardId) async {
    await _storage.write(key: _defaultBoardId, value: boardId.toString());
  }

  Future<int?> getDefaultBoardId() async {
    final v = await _storage.read(key: _defaultBoardId);
    if (v == null) return null;
    return int.tryParse(v);
  }

  Future<void> clearDefaultBoard() async {
    await _storage.delete(key: _defaultBoardId);
  }
}
