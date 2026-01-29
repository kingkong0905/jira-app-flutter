import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/jira_models.dart';

/// Jira REST API client with same endpoints and auth as reference app (kingkong0905/jira-app).
class JiraApiService {
  JiraConfig? _config;
  final Map<String, _CacheEntry> _cache = {};
  static const _cacheDurationMs = 5 * 60 * 1000; // 5 min
  static const _issuesCacheMs = 60 * 1000; // 1 min for board issues
  static const _issueDetailsCacheMs = 2 * 60 * 1000; // 2 min
  static const _timeout = Duration(seconds: 25);
  static const _connectionTestTimeout = Duration(seconds: 30);

  /// Set to false to disable connection debug logs (default: true).
  static bool debugLog = true;

  static void _log(String message, [String? detail]) {
    if (!debugLog) return;
    debugPrint('[JiraAPI] $message');
    if (detail != null && detail.isNotEmpty) {
      debugPrint('[JiraAPI]   $detail');
    }
  }

  void initialize(JiraConfig config) {
    _config = config;
  }

  void reset() {
    _config = null;
    _cache.clear();
  }

  /// Normalize Jira URL: trim, no trailing slash, always use https (required on mobile).
  static String normalizeJiraUrl(String url) {
    String u = url.trim().replaceAll(RegExp(r'/$'), '');
    try {
      final uri = Uri.parse(u);
      if (uri.scheme != 'https') {
        u = 'https://${uri.host}${uri.path.isEmpty ? '' : uri.path}${uri.query.isEmpty ? '' : '?${uri.query}'}';
      }
      return u;
    } catch (_) {
      return u;
    }
  }

  String get _baseUrl {
    final c = _config;
    if (c == null) throw StateError('Jira API not initialized. Configure credentials first.');
    return normalizeJiraUrl(c.jiraUrl);
  }

  /// Base Jira URL for building share links (e.g. comment URL). Null if not initialized.
  String? get jiraBaseUrl => _config != null ? normalizeJiraUrl(_config!.jiraUrl) : null;

  Map<String, String> get _headers {
    final c = _config;
    if (c == null) throw StateError('Jira API not initialized.');
    final auth = base64Encode(utf8.encode('${c.email}:${c.apiToken}'));
    return {
      'Authorization': 'Basic $auth',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'JiraManagementFlutter/1.0',
    };
  }

  /// Headers for authenticated media requests (e.g. video playback from attachment URL).
  Map<String, String> get authHeaders {
    final c = _config;
    if (c == null) throw StateError('Jira API not initialized.');
    final auth = base64Encode(utf8.encode('${c.email}:${c.apiToken}'));
    return {
      'Authorization': 'Basic $auth',
      'User-Agent': 'JiraManagementFlutter/1.0',
    };
  }

  String _cacheKey(String endpoint, [Map<String, dynamic>? params]) {
    return '$endpoint${params != null ? jsonEncode(params) : ''}';
  }

  T? _getFromCache<T>(String key, int maxAgeMs) {
    final e = _cache[key];
    if (e == null) return null;
    if (DateTime.now().difference(e.at).inMilliseconds > maxAgeMs) {
      _cache.remove(key);
      return null;
    }
    return e.data as T?;
  }

  void _setCache(String key, dynamic data) {
    _cache[key] = _CacheEntry(data: data, at: DateTime.now());
  }

  void clearCache() {
    _cache.clear();
  }

  /// Returns null on success, or an error message string on failure.
  Future<String?> testConnectionResult() async {
    final base = _baseUrl;
    final email = _config?.email ?? '(none)';
    _log('testConnectionResult start', 'baseUrl=$base');
    _log('testConnectionResult', 'email=$email (apiToken not logged)');
    try {
      // Jira Cloud uses /rest/api/3; Jira Server/Data Center often uses /rest/api/2
      final urls = [
        '$base/rest/api/3/myself',
        '$base/rest/api/2/myself',
      ];
      for (final url in urls) {
        _log('GET', url);
        try {
          final r = await http
              .get(Uri.parse(url), headers: _headers)
              .timeout(_connectionTestTimeout);
          _log('response', 'statusCode=${r.statusCode} url=$url');
          if (r.statusCode != 200 && r.body.isNotEmpty) {
            final bodyPreview = r.body.length > 300 ? '${r.body.substring(0, 300)}...' : r.body;
            _log('response body', bodyPreview.replaceAll('\n', ' '));
          }
          if (r.statusCode == 200) {
            _log('testConnectionResult', 'SUCCESS');
            return null;
          }
          if (r.statusCode == 401) {
            return 'Invalid email or API token. Check credentials and try again.';
          }
          if (r.statusCode == 403) {
            return 'Access forbidden. Check your Jira permissions.';
          }
          // 404 etc.: try next URL
          if (r.statusCode == 404) {
            _log('testConnectionResult', '404, trying next API version');
            continue;
          }
          try {
            final body = jsonDecode(r.body);
            final raw = body is Map ? (body['errorMessages'] as List?)?.join(' ') ?? r.body : r.body;
            final msg = raw.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
            return 'Jira error (${r.statusCode}): ${msg.length > 80 ? '${msg.substring(0, 80)}...' : msg}';
          } catch (_) {
            return 'Jira returned ${r.statusCode}. Check your Jira URL (e.g. https://your-domain.atlassian.net).';
          }
        } catch (reqErr, stack) {
          _log('request failed', 'url=$url');
          _log('exception', reqErr.toString());
          if (kDebugMode && stack != null) {
            _log('stack', stack.toString().split('\n').take(8).join('\n'));
          }
          rethrow;
        }
      }
      _log('testConnectionResult', 'no API version succeeded');
      return 'Could not reach Jira. Check URL and that you use Jira Cloud (atlassian.net) or correct Server URL.';
    } on Exception catch (e, stack) {
      _log('testConnectionResult FAILED', e.toString());
      if (kDebugMode && stack != null) {
        _log('stack', stack.toString().split('\n').take(10).join('\n'));
      }
      final msg = e.toString();
      if (msg.contains('SocketException') ||
          msg.contains('Connection refused') ||
          msg.contains('Failed host lookup') ||
          msg.contains('Connection reset') ||
          msg.contains('Network is unreachable')) {
        return 'Cannot reach Jira. Open $base in Safari/Chrome to confirm it loads. Use https://your-site.atlassian.net. On VPN, try another network.';
      }
      if (msg.contains('TimeoutException') || msg.contains('timed out')) {
        return 'Connection timed out. Check that $base opens in a browser and try again.';
      }
      if (msg.contains('CertificateException') || msg.contains('handshake')) {
        return 'SSL error. Use https:// and a valid Jira Cloud URL (e.g. https://your-site.atlassian.net).';
      }
      return 'Connection failed: ${msg.length > 60 ? '${msg.substring(0, 60)}...' : msg}';
    }
  }

  /// Current user (for comment Edit/Delete visibility). Same as reference useIssueData currentUser.
  Future<JiraUser?> getMyself() async {
    for (final path in ['/rest/api/3/myself', '/rest/api/2/myself']) {
      try {
        final r = await http.get(Uri.parse('$_baseUrl$path'), headers: _headers).timeout(_timeout);
        if (r.statusCode == 200) {
          final json = jsonDecode(r.body) as Map<String, dynamic>;
          return JiraUser.fromJson(json);
        }
      } catch (_) {}
    }
    return null;
  }

  /// Get user by account ID (for mention tap → user info modal). Jira REST API: GET /rest/api/3/user?accountId=...
  Future<JiraUser?> getUserByAccountId(String accountId) async {
    if (accountId.isEmpty) return null;
    try {
      final uri = Uri.parse('$_baseUrl/rest/api/3/user').replace(queryParameters: {'accountId': accountId});
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode == 200) {
        final json = jsonDecode(r.body) as Map<String, dynamic>;
        return JiraUser.fromJson(json);
      }
    } catch (_) {}
    return null;
  }

  /// Fetch attachment content with auth (for image preview / open file). Content URL from issue attachment.
  Future<List<int>?> fetchAttachmentBytes(String contentUrl) async {
    try {
      final r = await http.get(Uri.parse(contentUrl), headers: _headers).timeout(_timeout);
      if (r.statusCode == 200) return r.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<bool> testConnection() async {
    final err = await testConnectionResult();
    return err == null;
  }

  Future<BoardsResponse> getBoards({
    int startAt = 0,
    int maxResults = 50,
    String? searchQuery,
  }) async {
    final params = <String, String>{
      'startAt': startAt.toString(),
      'maxResults': maxResults.toString(),
    };
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      params['name'] = searchQuery.trim();
    }
    final key = _cacheKey('/rest/agile/1.0/board', params);
    final cached = _getFromCache<BoardsResponse>(key, _cacheDurationMs);
    if (cached != null) return cached;

    final uri = Uri.parse('$_baseUrl/rest/agile/1.0/board').replace(queryParameters: params);
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != 200) throw JiraApiException(r.statusCode, r.body);

    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final boards = (json['values'] as List<dynamic>?)
            ?.map((e) => JiraBoard.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final total = intFromJson(json['total']) ?? 0;
    final isLast = json['isLast'] as bool? ?? true;
    final result = BoardsResponse(boards: boards, total: total, isLast: isLast);
    _setCache(key, result);
    return result;
  }

  Future<JiraBoard?> getBoardById(int boardId) async {
    final r = await http
        .get(
          Uri.parse('$_baseUrl/rest/agile/1.0/board/$boardId'),
          headers: _headers,
        )
        .timeout(_timeout);
    if (r.statusCode != 200) return null;
    final json = jsonDecode(r.body) as Map<String, dynamic>;
    return JiraBoard.fromJson(json);
  }

  Future<List<JiraIssue>> getBoardIssues(int boardId, {int maxResults = 50, String? assignee}) async {
    final key = _cacheKey('/rest/agile/1.0/board/$boardId/issue', {'maxResults': maxResults, 'assignee': assignee ?? 'all'});
    final cached = _getFromCache<List<JiraIssue>>(key, _issuesCacheMs);
    if (cached != null) return cached;

    final params = <String, String>{
      'maxResults': maxResults.toString(),
      'fields': 'summary,status,priority,assignee,issuetype,created,updated,duedate,sprint',
    };
    if (assignee != null && assignee.isNotEmpty && assignee != 'all') {
      if (assignee == 'unassigned') {
        params['jql'] = 'assignee is EMPTY';
      } else {
        params['jql'] = 'assignee = "$assignee"';
      }
    }
    final uri = Uri.parse('$_baseUrl/rest/agile/1.0/board/$boardId/issue').replace(queryParameters: params);
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != 200) throw JiraApiException(r.statusCode, r.body);

    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (json['issues'] as List<dynamic>?) ?? [];
    final issues = list.map((e) => JiraIssue.fromJson(e as Map<String, dynamic>)).toList();
    _setCache(key, issues);
    return issues;
  }

  Future<List<BoardAssignee>> getBoardAssignees(int boardId) async {
    final key = _cacheKey('/rest/agile/1.0/board/$boardId/assignees', {});
    final cached = _getFromCache<List<BoardAssignee>>(key, _cacheDurationMs);
    if (cached != null) return cached;

    final params = {'maxResults': '1000', 'fields': 'assignee'};
    final uri = Uri.parse('$_baseUrl/rest/agile/1.0/board/$boardId/issue').replace(queryParameters: params);
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != 200) return [];

    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (json['issues'] as List<dynamic>?) ?? [];
    final seen = <String, String>{};
    for (final issue in list) {
      final assignee = (issue as Map<String, dynamic>)['fields']?['assignee'];
      if (assignee is Map<String, dynamic>) {
        final email = stringFromJson(assignee['emailAddress']);
        final name = stringFromJson(assignee['displayName']) ?? '';
        final k = email ?? name;
        if (k != null && k.isNotEmpty) seen[k] = name;
      }
    }
    final result = seen.entries.map((e) => BoardAssignee(key: e.key, name: e.value)).toList();
    _setCache(key, result);
    return result;
  }

  Future<List<JiraSprint>> getSprintsForBoard(int boardId) async {
    final key = _cacheKey('/rest/agile/1.0/board/$boardId/sprint', {});
    final cached = _getFromCache<List<JiraSprint>>(key, _cacheDurationMs);
    if (cached != null) return cached;

    try {
      final r = await http
          .get(
            Uri.parse('$_baseUrl/rest/agile/1.0/board/$boardId/sprint'),
            headers: _headers,
          )
          .timeout(_timeout);
      if (r.statusCode == 400 || r.statusCode == 404) return [];
      if (r.statusCode != 200) throw JiraApiException(r.statusCode, r.body);

      final json = jsonDecode(r.body) as Map<String, dynamic>;
      final list = (json['values'] as List<dynamic>?) ?? [];
      final sprints = list.map((e) => JiraSprint.fromJson(e as Map<String, dynamic>)).toList();
      _setCache(key, sprints);
      return sprints;
    } catch (_) {
      return [];
    }
  }

  Future<JiraSprint?> getActiveSprint(int boardId) async {
    final sprints = await getSprintsForBoard(boardId);
    try {
      return sprints.firstWhere((s) => s.state == 'active');
    } catch (_) {
      return null;
    }
  }

  Future<List<JiraIssue>> getSprintIssues(
    int boardId,
    int sprintId, {
    String? assignee,
  }) async {
    final params = <String, String>{
      'maxResults': '100',
      'fields': 'summary,status,priority,assignee,issuetype,created,updated,duedate,sprint',
    };
    if (assignee != null && assignee.isNotEmpty && assignee != 'all') {
      if (assignee == 'unassigned') {
        params['jql'] = 'assignee is EMPTY';
      } else {
        params['jql'] = 'assignee = "$assignee"';
      }
    }
    final uri = Uri.parse('$_baseUrl/rest/agile/1.0/board/$boardId/sprint/$sprintId/issue')
        .replace(queryParameters: params);
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != 200) throw JiraApiException(r.statusCode, r.body);

    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (json['issues'] as List<dynamic>?) ?? [];
    return list.map((e) => JiraIssue.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<JiraIssue>> getBacklogIssues(int boardId, {String? assignee}) async {
    final params = <String, String>{
      'maxResults': '100',
      'fields': 'summary,status,priority,assignee,issuetype,created,updated,duedate,sprint',
    };
    if (assignee != null && assignee.isNotEmpty && assignee != 'all') {
      if (assignee == 'unassigned') {
        params['jql'] = 'assignee is EMPTY';
      } else {
        params['jql'] = 'assignee = "$assignee"';
      }
    }
    final uri = Uri.parse('$_baseUrl/rest/agile/1.0/board/$boardId/backlog').replace(queryParameters: params);
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != 200) throw JiraApiException(r.statusCode, r.body);

    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (json['issues'] as List<dynamic>?) ?? [];
    return list.map((e) => JiraIssue.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<JiraIssue?> getIssueDetails(String issueKey) async {
    final key = _cacheKey('/rest/api/3/issue/$issueKey', {});
    final cached = _getFromCache<JiraIssue>(key, _issueDetailsCacheMs);
    if (cached != null) return cached;

    final params = {
      'fields': 'summary,description,status,priority,assignee,reporter,issuetype,created,updated,duedate,customfield_10016,comment,parent,attachment',
    };
    final uri = Uri.parse('$_baseUrl/rest/api/3/issue/$issueKey').replace(queryParameters: params);
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != 200) throw JiraApiException(r.statusCode, r.body);

    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final issue = JiraIssue.fromJson(json);
    _setCache(key, issue);
    return issue;
  }

  /// Fetch subtasks for an issue (JQL: parent = issueKey). Same logic as reference app.
  Future<List<JiraIssue>> getSubtasks(String issueKey) async {
    final uri = Uri.parse('$_baseUrl/rest/api/3/search').replace(
      queryParameters: {
        'jql': 'parent = $issueKey',
        'maxResults': '50',
        'fields': 'summary,status,priority,assignee,issuetype,created,updated,duedate',
      },
    );
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != 200) return [];
    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (json['issues'] as List<dynamic>?) ?? [];
    return list.map((e) => JiraIssue.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get available transitions for an issue (for status change). GET /rest/api/3/issue/{key}/transitions.
  Future<List<Map<String, dynamic>>> getTransitions(String issueKey) async {
    try {
      final r = await http.get(
        Uri.parse('$_baseUrl/rest/api/3/issue/$issueKey/transitions'),
        headers: _headers,
      ).timeout(_timeout);
      if (r.statusCode != 200) return [];
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      final list = json['transitions'] as List<dynamic>?;
      if (list == null) return [];
      return list.map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  /// Execute a transition (change status). POST /rest/api/3/issue/{key}/transitions.
  Future<String?> transitionIssue(String issueKey, String transitionId) async {
    try {
      final r = await http.post(
        Uri.parse('$_baseUrl/rest/api/3/issue/$issueKey/transitions'),
        headers: _headers,
        body: jsonEncode({'transition': {'id': transitionId}}),
      ).timeout(_timeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _setCache(_cacheKey('/rest/api/3/issue/$issueKey', {}), null);
        return null;
      }
      return r.body;
    } catch (e) {
      return e.toString();
    }
  }

  /// Get users assignable to an issue. GET /rest/api/3/user/assignable/search.
  Future<List<JiraUser>> getAssignableUsers(String issueKey, {String? query}) async {
    try {
      final params = <String, String>{'issueKey': issueKey, 'maxResults': '50'};
      if (query != null && query.isNotEmpty) params['query'] = query;
      final uri = Uri.parse('$_baseUrl/rest/api/3/user/assignable/search').replace(queryParameters: params);
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode != 200) return [];
      final list = jsonDecode(r.body) as List<dynamic>?;
      if (list == null) return [];
      return list.map((e) => JiraUser.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get all priorities. GET /rest/api/3/priority.
  Future<List<Map<String, dynamic>>> getPriorities() async {
    try {
      final r = await http.get(Uri.parse('$_baseUrl/rest/api/3/priority'), headers: _headers).timeout(_timeout);
      if (r.statusCode != 200) return [];
      final list = jsonDecode(r.body) as List<dynamic>?;
      if (list == null) return [];
      return list.map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  /// Update issue fields (assignee, priority, duedate, summary, description, customfield_10016, etc.). Same as reference.
  Future<String?> updateIssueField(String issueKey, Map<String, dynamic> fields) async {
    final body = jsonEncode({'fields': fields});
    final r = await http.put(
      Uri.parse('$_baseUrl/rest/api/3/issue/$issueKey'),
      headers: _headers,
      body: body,
    ).timeout(_timeout);
    if (r.statusCode >= 200 && r.statusCode < 300) {
      _setCache(_cacheKey('/rest/api/3/issue/$issueKey', {}), null);
      return null;
    }
    return r.body;
  }

  Future<List<dynamic>> getIssueComments(String issueKey) async {
    final uri = Uri.parse('$_baseUrl/rest/api/3/issue/$issueKey/comment').replace(
      queryParameters: {'expand': 'renderedBody'},
    );
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != 200) return [];
    final json = jsonDecode(r.body) as Map<String, dynamic>;
    return (json['comments'] as List<dynamic>?) ?? [];
  }

  /// Build simple ADF body from plain text for comment add/update.
  static Map<String, dynamic> _commentBodyAdf(String text) {
    final trimmed = text.trim();
    return {
      'body': {
        'type': 'doc',
        'version': 1,
        'content': [
          {
            'type': 'paragraph',
            'content': trimmed.isEmpty ? [] : [{'type': 'text', 'text': trimmed}],
          },
        ],
      },
    };
  }

  /// Build description ADF from plain text (one paragraph per line). For updateIssueField(issueKey, {'description': adf}).
  static Map<String, dynamic> descriptionAdfFromPlainText(String text) {
    final lines = text.split('\n');
    final content = lines.map((line) => {
      'type': 'paragraph',
      'content': line.isEmpty ? [] : [{'type': 'text', 'text': line}],
    }).toList();
    if (content.isEmpty) content.add({'type': 'paragraph', 'content': []});
    return {'type': 'doc', 'version': 1, 'content': content};
  }

  /// Add comment. Optional [parentCommentId] for reply (Jira comment thread).
  Future<String?> addComment(String issueKey, String text, {String? parentCommentId}) async {
    final payload = _commentBodyAdf(text);
    if (parentCommentId != null && parentCommentId.isNotEmpty) {
      payload['parent'] = {'id': parentCommentId};
    }
    final r = await http.post(
      Uri.parse('$_baseUrl/rest/api/3/issue/$issueKey/comment'),
      headers: _headers,
      body: jsonEncode(payload),
    ).timeout(_timeout);
    if (r.statusCode >= 200 && r.statusCode < 300) {
      _setCache(_cacheKey('/rest/api/3/issue/$issueKey/comment', {}), null);
      return null;
    }
    return r.body;
  }

  /// Update comment. Returns error message or null on success.
  Future<String?> updateComment(String issueKey, String commentId, String text) async {
    final body = _commentBodyAdf(text);
    final r = await http.put(
      Uri.parse('$_baseUrl/rest/api/3/issue/$issueKey/comment/$commentId'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(_timeout);
    if (r.statusCode >= 200 && r.statusCode < 300) {
      _setCache(_cacheKey('/rest/api/3/issue/$issueKey/comment', {}), null);
      return null;
    }
    return r.body;
  }

  /// Delete comment. Returns error message or null on success.
  Future<String?> deleteComment(String issueKey, String commentId) async {
    final r = await http.delete(
      Uri.parse('$_baseUrl/rest/api/3/issue/$issueKey/comment/$commentId'),
      headers: _headers,
    ).timeout(_timeout);
    if (r.statusCode >= 200 && r.statusCode < 300) {
      _setCache(_cacheKey('/rest/api/3/issue/$issueKey/comment', {}), null);
      return null;
    }
    return r.body;
  }

  Future<void> completeSprint(int sprintId) async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl/rest/agile/1.0/sprint/$sprintId'),
          headers: _headers,
          body: jsonEncode({'state': 'closed'}),
        )
        .timeout(_timeout);
    if (r.statusCode != 200) throw JiraApiException(r.statusCode, r.body);
    clearCache();
  }
}

class _CacheEntry {
  final dynamic data;
  final DateTime at;
  _CacheEntry({required this.data, required this.at});
}

class BoardsResponse {
  final List<JiraBoard> boards;
  final int total;
  final bool isLast;
  BoardsResponse({required this.boards, required this.total, required this.isLast});
}

class JiraApiException implements Exception {
  final int statusCode;
  final String body;
  JiraApiException(this.statusCode, this.body);
  @override
  String toString() => 'JiraApiException($statusCode): $body';
}
