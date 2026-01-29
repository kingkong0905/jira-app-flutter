import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import '../models/jira_models.dart';

/// Local SQLite storage for Jira config (no keychain; works on all platforms including macOS).
class StorageService {
  StorageService();

  static const _email = 'jira_email';
  static const _jiraUrl = 'jira_url';
  static const _apiToken = 'jira_api_token';
  static const _isConfigured = 'jira_is_configured';
  static const _defaultBoardId = 'jira_default_board_id';

  Database? _db;
  Future<void>? _initFuture;

  Future<void> _ensureDb() async {
    if (_db != null) return;
    _initFuture ??= _openDb();
    await _initFuture;
  }

  Future<void> _openDb() async {
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'jira_config.db');
    _db = sqlite3.open(path);
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS config (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<void> _set(String key, String value) async {
    await _ensureDb();
    _db!.execute(
      'INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)',
      [key, value],
    );
  }

  Future<String?> _get(String key) async {
    await _ensureDb();
    final result = _db!.select('SELECT value FROM config WHERE key = ?', [key]);
    if (result.isEmpty) return null;
    return result.first['value'] as String?;
  }

  Future<void> _delete(String key) async {
    await _ensureDb();
    _db!.execute('DELETE FROM config WHERE key = ?', [key]);
  }

  Future<void> saveConfig(JiraConfig config) async {
    await _set(_email, config.email);
    await _set(_jiraUrl, config.jiraUrl);
    await _set(_apiToken, config.apiToken);
    await _set(_isConfigured, 'true');
  }

  Future<JiraConfig?> getConfig() async {
    final email = await _get(_email);
    final jiraUrl = await _get(_jiraUrl);
    final apiToken = await _get(_apiToken);
    if (email != null && jiraUrl != null && apiToken != null) {
      return JiraConfig(email: email, jiraUrl: jiraUrl, apiToken: apiToken);
    }
    return null;
  }

  Future<bool> isConfigured() async {
    final v = await _get(_isConfigured);
    return v == 'true';
  }

  Future<void> clearConfig() async {
    await _ensureDb();
    _db!.execute('DELETE FROM config');
  }

  Future<void> setDefaultBoardId(int boardId) async {
    await _set(_defaultBoardId, boardId.toString());
  }

  Future<int?> getDefaultBoardId() async {
    final v = await _get(_defaultBoardId);
    if (v == null) return null;
    return int.tryParse(v);
  }

  Future<void> clearDefaultBoard() async {
    await _delete(_defaultBoardId);
  }
}
