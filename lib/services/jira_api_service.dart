import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/jira_models.dart';

/// Jira REST API client with same endpoints and auth as reference app (kingkong0905/jira-app).
class JiraApiService {
  JiraConfig? _config;
  final Map<String, _CacheEntry> _cache = {};
  static const _cacheDurationMs = 5 * 60 * 1000; // 5 min
  static const _issuesCacheMs = 60 * 1000; // 1 min for board issues
  static const _issueDetailsCacheMs = 2 * 60 * 1000; // 2 min
  static const _timeout = Duration(seconds: 15);

  void initialize(JiraConfig config) {
    _config = config;
  }

  void reset() {
    _config = null;
    _cache.clear();
  }

  String get _baseUrl {
    final c = _config;
    if (c == null) throw StateError('Jira API not initialized. Configure credentials first.');
    return c.jiraUrl.replaceAll(RegExp(r'/$'), '');
  }

  Map<String, String> get _headers {
    final c = _config;
    if (c == null) throw StateError('Jira API not initialized.');
    final auth = base64Encode(utf8.encode('${c.email}:${c.apiToken}'));
    return {
      'Authorization': 'Basic $auth',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
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

  Future<bool> testConnection() async {
    try {
      final r = await http
          .get(
            Uri.parse('$_baseUrl/rest/api/3/myself'),
            headers: _headers,
          )
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
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
    final total = json['total'] as int? ?? 0;
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

  Future<List<JiraIssue>> getBoardIssues(int boardId, {int maxResults = 50}) async {
    final key = _cacheKey('/rest/agile/1.0/board/$boardId/issue', {'maxResults': maxResults});
    final cached = _getFromCache<List<JiraIssue>>(key, _issuesCacheMs);
    if (cached != null) return cached;

    final params = {
      'maxResults': maxResults.toString(),
      'fields': 'summary,status,priority,assignee,issuetype,created,updated,sprint',
    };
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
        final email = assignee['emailAddress'] as String?;
        final name = assignee['displayName'] as String? ?? '';
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
      'fields': 'summary,description,status,priority,assignee,reporter,issuetype,created,updated,duedate,comment,parent',
    };
    final uri = Uri.parse('$_baseUrl/rest/api/3/issue/$issueKey').replace(queryParameters: params);
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != 200) throw JiraApiException(r.statusCode, r.body);

    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final issue = JiraIssue.fromJson(json);
    _setCache(key, issue);
    return issue;
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
