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
    String? projectKeyOrId,
  }) async {
    final params = <String, String>{
      'startAt': startAt.toString(),
      'maxResults': maxResults.toString(),
    };
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      params['name'] = searchQuery.trim();
    }
    if (projectKeyOrId != null && projectKeyOrId.trim().isNotEmpty) {
      params['projectKeyOrId'] = projectKeyOrId.trim();
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

  /// Fetches all board issues (paginated). Jira Agile API may cap maxResults at 50 per page.
  Future<List<JiraIssue>> getBoardIssuesAll(int boardId, {String? assignee}) async {
    final results = <JiraIssue>[];
    int startAt = 0;
    const maxResults = 50;
    while (true) {
      final params = <String, String>{
        'startAt': '$startAt',
        'maxResults': '$maxResults',
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
      for (final e in list) {
        if (e is Map<String, dynamic>) {
          try {
            results.add(JiraIssue.fromJson(e));
          } catch (_) {}
        }
      }
      if (list.length < maxResults) break;
      startAt += maxResults;
    }
    return results;
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

  /// Create a new sprint. POST /rest/agile/1.0/sprint
  Future<String?> createSprint({
    required int boardId,
    required String name,
    String? goal,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final body = <String, dynamic>{
        'name': name,
        'originBoardId': boardId,
      };

      if (goal != null && goal.isNotEmpty) {
        body['goal'] = goal;
      }

      if (startDate != null && startDate.isNotEmpty) {
        body['startDate'] = startDate;
      }

      if (endDate != null && endDate.isNotEmpty) {
        body['endDate'] = endDate;
      }

      final r = await http.post(
        Uri.parse('$_baseUrl/rest/agile/1.0/sprint'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(_timeout);

      if (r.statusCode >= 200 && r.statusCode < 300) {
        clearCache();
        return null; // Success
      }

      // Parse error message
      try {
        final errorJson = jsonDecode(r.body) as Map<String, dynamic>;
        final errorMessages = errorJson['errorMessages'] as List<dynamic>?;
        if (errorMessages != null && errorMessages.isNotEmpty) {
          return errorMessages.join(', ');
        }
        final errors = errorJson['errors'] as Map<String, dynamic>?;
        if (errors != null && errors.isNotEmpty) {
          return errors.values.join(', ');
        }
      } catch (_) {}

      return 'Failed to create sprint: ${r.statusCode}';
    } catch (e) {
      return e.toString();
    }
  }

  /// Fetches all issues in a sprint (paginated). Jira Agile API may cap maxResults at 50.
  Future<List<JiraIssue>> getSprintIssues(
    int boardId,
    int sprintId, {
    String? assignee,
  }) async {
    final results = <JiraIssue>[];
    int startAt = 0;
    const maxResults = 50;
    while (true) {
      final params = <String, String>{
        'startAt': '$startAt',
        'maxResults': '$maxResults',
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
      for (final e in list) {
        if (e is Map<String, dynamic>) {
          try {
            results.add(JiraIssue.fromJson(e));
          } catch (_) {}
        }
      }
      if (list.length < maxResults) break;
      startAt += maxResults;
    }
    return results;
  }

  /// Fetches one page of backlog issues (board backlog API). Returns issues and whether more pages exist.
  Future<({List<JiraIssue> issues, bool hasMore})> getBacklogIssuesPage(
    int boardId, {
    int startAt = 0,
    int maxResults = 50,
    String? assignee,
  }) async {
    final params = <String, String>{
      'startAt': '$startAt',
      'maxResults': '$maxResults',
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
    List<dynamic> list = (json['issues'] as List<dynamic>?) ?? (json['values'] as List<dynamic>?) ?? [];
    if (list.isEmpty && json['contents'] is Map) {
      final contents = json['contents'] as Map<String, dynamic>;
      list = (contents['issues'] as List<dynamic>?) ?? (contents['values'] as List<dynamic>?) ?? [];
    }
    final issues = <JiraIssue>[];
    for (final e in list) {
      if (e is Map<String, dynamic>) {
        try {
          issues.add(JiraIssue.fromJson(e));
        } catch (parseErr) {
          if (debugLog) debugPrint('[JiraAPI] getBacklogIssuesPage skip issue parse: $parseErr');
        }
      }
    }
    final hasMore = list.length >= maxResults;
    return (issues: issues, hasMore: hasMore);
  }

  /// Fetches all backlog issues (paginated). Board backlog = issues not in any sprint.
  /// Jira Agile API may cap maxResults at 50 per page; may return 'issues' or 'values'.
  Future<List<JiraIssue>> getBacklogIssues(int boardId, {String? assignee}) async {
    final results = <JiraIssue>[];
    int startAt = 0;
    const maxResults = 50;
    while (true) {
      final page = await getBacklogIssuesPage(boardId, startAt: startAt, maxResults: maxResults, assignee: assignee);
      results.addAll(page.issues);
      if (!page.hasMore) break;
      startAt += maxResults;
    }
    return results;
  }

  /// Fetches one page of backlog issues via JQL (project = X AND sprint is EMPTY). Use when board backlog returns empty.
  Future<({List<JiraIssue> issues, bool hasMore, int total})> getBacklogIssuesByJqlPage(
    String projectKey, {
    int startAt = 0,
    int maxResults = 50,
    String? assignee,
  }) async {
    final jql = StringBuffer('project = $projectKey AND sprint is EMPTY');
    if (assignee != null && assignee.isNotEmpty && assignee != 'all') {
      if (assignee == 'unassigned') {
        jql.write(' AND assignee is EMPTY');
      } else {
        jql.write(' AND assignee = "$assignee"');
      }
    }
    const fields = 'summary,status,priority,assignee,issuetype,created,updated,duedate,sprint';
    final uri = Uri.parse('$_baseUrl/rest/api/3/search').replace(queryParameters: {
      'jql': jql.toString(),
      'startAt': '$startAt',
      'maxResults': '$maxResults',
      'fields': fields,
    });
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != 200) return (issues: <JiraIssue>[], hasMore: false, total: 0);
    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (json['issues'] as List<dynamic>?) ?? [];
    final total = (json['total'] as int?) ?? 0;
    final issues = <JiraIssue>[];
    for (final e in list) {
      if (e is Map<String, dynamic>) {
        try {
          issues.add(JiraIssue.fromJson(e));
        } catch (_) {}
      }
    }
    final hasMore = (startAt + list.length) < total;
    return (issues: issues, hasMore: hasMore, total: total);
  }

  /// Fallback: get issues with no sprint via JQL (project = X AND sprint is EMPTY). Use when board backlog returns empty.
  Future<List<JiraIssue>> getBacklogIssuesByJql(String projectKey, {String? assignee}) async {
    final results = <JiraIssue>[];
    int startAt = 0;
    const maxResults = 50;
    while (true) {
      final page = await getBacklogIssuesByJqlPage(projectKey, startAt: startAt, maxResults: maxResults, assignee: assignee);
      results.addAll(page.issues);
      if (!page.hasMore) break;
      startAt += maxResults;
    }
    return results;
  }

  Future<JiraIssue?> getIssueDetails(String issueKey) async {
    final key = _cacheKey('/rest/api/3/issue/$issueKey', {});
    final cached = _getFromCache<JiraIssue>(key, _issueDetailsCacheMs);
    if (cached != null) return cached;

    final params = {
      'fields': 'summary,description,status,priority,assignee,reporter,issuetype,created,updated,duedate,customfield_10016,comment,parent,attachment,project,sprint,customfield_10020,subtasks,issuelinks',
    };
    final uri = Uri.parse('$_baseUrl/rest/api/3/issue/$issueKey').replace(queryParameters: params);
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != 200) throw JiraApiException(r.statusCode, r.body);

    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final issue = JiraIssue.fromJson(json);
    _setCache(key, issue);
    return issue;
  }

  /// Get remote issue links (e.g. Confluence pages). GET /rest/api/3/issue/{key}/remotelink.
  Future<List<JiraRemoteLink>> getRemoteLinks(String issueKey) async {
    try {
      final r = await http.get(
        Uri.parse('$_baseUrl/rest/api/3/issue/$issueKey/remotelink'),
        headers: _headers,
      ).timeout(_timeout);
      if (r.statusCode != 200) return [];
      final list = jsonDecode(r.body);
      if (list is! List) return [];
      return (list as List<dynamic>)
          .map((e) => JiraRemoteLink.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Try to get Confluence application id from applinks (for creating Confluence remote link).
  Future<String?> getConfluenceAppId() async {
    try {
      final r = await http.get(
        Uri.parse('$_baseUrl/rest/applinks/3.0/applinks'),
        headers: _headers,
      ).timeout(_timeout);
      if (r.statusCode != 200) return null;
      final list = jsonDecode(r.body);
      if (list is! List) return null;
      for (final e in list as List<dynamic>) {
        if (e is! Map) continue;
        final type = stringFromJson(e['type']);
        if (type != null && type.toLowerCase().contains('confluence')) {
          final id = stringFromJson(e['id']);
          if (id != null && id.isNotEmpty) return id;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Create a Confluence page remote link. POST /rest/api/3/issue/{key}/remotelink.
  /// [pageUrl] full Confluence page URL; [title] display title; [pageId] optional, parsed from URL if not provided.
  Future<String?> createConfluenceRemoteLink(
    String issueKey, {
    required String pageUrl,
    required String title,
    String? pageId,
  }) async {
    String? pid = pageId;
    if (pid == null || pid.isEmpty) {
      final match = RegExp(r'/pages/(\d+)|pageId=(\d+)').firstMatch(pageUrl);
      if (match != null) pid = match.group(1) ?? match.group(2);
    }
    if (pid == null || pid.isEmpty) return 'Could not parse Confluence page ID from URL';
    final appId = await getConfluenceAppId();
    final globalId = appId != null
        ? 'appId=$appId&pageId=$pid'
        : 'confluencePageId=$pid';
    final url = pageUrl.trim().isNotEmpty
        ? pageUrl.trim()
        : '$_baseUrl/wiki/pages/viewpage.action?pageId=$pid';
    final body = {
      'globalId': globalId,
      'application': {
        'type': 'com.atlassian.confluence',
        'name': 'Confluence',
      },
      'relationship': 'Wiki Page',
      'object': {
        'url': url,
        'title': title.isNotEmpty ? title : 'Confluence Page',
      },
    };
    try {
      final r = await http.post(
        Uri.parse('$_baseUrl/rest/api/3/issue/$issueKey/remotelink'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(_timeout);
      if (r.statusCode == 200 || r.statusCode == 201) return null;
      return r.body;
    } catch (e) {
      return e.toString();
    }
  }

  /// Delete a remote issue link. DELETE /rest/api/3/issue/{key}/remotelink/{linkId}.
  Future<String?> deleteRemoteLink(String issueKey, int linkId) async {
    try {
      final r = await http.delete(
        Uri.parse('$_baseUrl/rest/api/3/issue/$issueKey/remotelink/$linkId'),
        headers: _headers,
      ).timeout(_timeout);
      if (r.statusCode == 204 || r.statusCode == 200) return null;
      return r.body;
    } catch (e) {
      return e.toString();
    }
  }

  /// Fetch subtasks for an issue (JQL: parent = issueKey). Quoting the key for JQL safety.
  Future<List<JiraIssue>> getSubtasks(String issueKey) async {
    final jql = 'parent = "$issueKey"';
    final uri = Uri.parse('$_baseUrl/rest/api/3/search').replace(
      queryParameters: {
        'jql': jql,
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

  /// Fetch all issues that belong to an Epic (Task, Sub-task, Bug, Story, etc.). Tries parentEpic first, then parent = key.
  Future<List<JiraIssue>> getEpicChildren(String issueKey) async {
    const fields = 'summary,status,priority,assignee,issuetype,created,updated,duedate';
    final params = (String jql) => {'jql': jql, 'maxResults': '100', 'fields': fields};

    // 1) parentEpic = key returns direct children + nested sub-tasks (all types) in Jira Cloud
    try {
      final uri = Uri.parse('$_baseUrl/rest/api/3/search').replace(queryParameters: params('parentEpic = "$issueKey"'));
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode == 200) {
        final json = jsonDecode(r.body) as Map<String, dynamic>;
        final list = (json['issues'] as List<dynamic>?) ?? [];
        if (list.isNotEmpty) {
          return list.map((e) => JiraIssue.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}

    // 2) Fallback: parent = key (direct children – Task, Bug, Story, Sub-task under Epic)
    try {
      final uri = Uri.parse('$_baseUrl/rest/api/3/search').replace(queryParameters: params('parent = "$issueKey"'));
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode == 200) {
        final json = jsonDecode(r.body) as Map<String, dynamic>;
        final list = (json['issues'] as List<dynamic>?) ?? [];
        if (list.isNotEmpty) {
          return list.map((e) => JiraIssue.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}

    // 3) Fallback: "Epic Link" = key (classic/company-managed projects using Epic Link field)
    try {
      final jql = '"Epic Link" = "$issueKey"';
      final uri = Uri.parse('$_baseUrl/rest/api/3/search').replace(queryParameters: {'jql': jql, 'maxResults': '100', 'fields': fields});
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode == 200) {
        final json = jsonDecode(r.body) as Map<String, dynamic>;
        final list = (json['issues'] as List<dynamic>?) ?? [];
        return list.map((e) => JiraIssue.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}

    return [];
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

  /// Invisible markers in comment text: zwsp~zwsp + accountId + sep + displayName + zwsp~zwsp (user sees only "@displayName").
  static const String _mentionMarkerZwsp = '\u200B';
  static const String _mentionMarkerSep = '\u200C';

  /// Remove visible "@DisplayName" before each mention marker so we send clean text to the API (no duplicate when building ADF).
  static String _removeDuplicateMentionDisplay(String text) {
    final pattern = RegExp(
      '${RegExp.escape(_mentionMarkerZwsp)}~$_mentionMarkerZwsp([^$_mentionMarkerSep]+)$_mentionMarkerSep([^$_mentionMarkerZwsp]*)$_mentionMarkerZwsp~$_mentionMarkerZwsp',
    );
    final matches = pattern.allMatches(text).toList();
    if (matches.isEmpty) return text;
    final buffer = StringBuffer();
    int lastEnd = 0;
    for (final match in matches) {
      final displayName = match.group(2) ?? '';
      final visibleMention = '@$displayName';
      final segmentEnd = match.start;
      if (segmentEnd > lastEnd) {
        String segment = text.substring(lastEnd, segmentEnd);
        if (segment.endsWith(visibleMention)) {
          segment = segment.substring(0, segment.length - visibleMention.length);
        }
        buffer.write(segment);
      }
      buffer.write(text.substring(match.start, match.end));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      buffer.write(text.substring(lastEnd));
    }
    return buffer.toString();
  }

  /// Build ADF body from comment text. Parses mention markers into ADF mention nodes (id + display text).
  static Map<String, dynamic> _commentBodyAdf(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return {
        'body': {
          'type': 'doc',
          'version': 1,
          'content': [
            {'type': 'paragraph', 'content': []},
          ],
        },
      };
    }
    final normalized = _removeDuplicateMentionDisplay(trimmed);
    final pattern = RegExp(
      '${RegExp.escape(_mentionMarkerZwsp)}~$_mentionMarkerZwsp([^$_mentionMarkerSep]+)$_mentionMarkerSep([^$_mentionMarkerZwsp]*)$_mentionMarkerZwsp~$_mentionMarkerZwsp',
    );
    final List<Map<String, dynamic>> paragraphContent = [];
    int lastEnd = 0;
    for (final match in pattern.allMatches(normalized)) {
      if (match.start > lastEnd) {
        final segment = normalized.substring(lastEnd, match.start);
        if (segment.isNotEmpty) {
          paragraphContent.add({'type': 'text', 'text': segment});
        }
      }
      final accountId = match.group(1) ?? '';
      final displayName = match.group(2) ?? '';
      paragraphContent.add({
        'type': 'mention',
        'attrs': {'id': accountId, 'text': displayName.isEmpty ? '@$accountId' : '@$displayName'},
      });
      lastEnd = match.end;
    }
    if (lastEnd < normalized.length) {
      final segment = normalized.substring(lastEnd);
      if (segment.isNotEmpty) {
        paragraphContent.add({'type': 'text', 'text': segment});
      }
    }
    if (paragraphContent.isEmpty) {
      paragraphContent.add({'type': 'text', 'text': normalized});
    }
    return {
      'body': {
        'type': 'doc',
        'version': 1,
        'content': [
          {'type': 'paragraph', 'content': paragraphContent},
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

  /// Update sprint. PUT /rest/agile/1.0/sprint/{sprintId}
  Future<String?> updateSprint({
    required int sprintId,
    required String name,
    String? goal,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final body = <String, dynamic>{'name': name};
      if (goal != null) body['goal'] = goal;
      if (startDate != null) body['startDate'] = startDate;
      if (endDate != null) body['endDate'] = endDate;
      final r = await http
          .put(
            Uri.parse('$_baseUrl/rest/agile/1.0/sprint/$sprintId'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (r.statusCode != 200) return 'Failed to update sprint: ${r.statusCode}';
      clearCache();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Delete sprint. DELETE /rest/agile/1.0/sprint/{sprintId}
  /// Accepts 200 OK or 204 No Content as success.
  Future<String?> deleteSprint(int sprintId) async {
    try {
      final r = await http
          .delete(Uri.parse('$_baseUrl/rest/agile/1.0/sprint/$sprintId'), headers: _headers)
          .timeout(_timeout);
      if (r.statusCode != 200 && r.statusCode != 204) return 'Failed to delete sprint: ${r.statusCode}';
      clearCache();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Get issue types for a project. GET /rest/api/3/project/{projectKey}/statuses
  Future<List<Map<String, dynamic>>> getIssueTypesForProject(String projectKey) async {
    try {
      final r = await http.get(
        Uri.parse('$_baseUrl/rest/api/3/project/$projectKey/statuses'),
        headers: _headers,
      ).timeout(_timeout);
      if (r.statusCode != 200) return [];
      final list = jsonDecode(r.body) as List<dynamic>?;
      if (list == null) return [];
      return list.map((e) => {
        'id': e['id'].toString(),
        'name': stringFromJson(e['name']) ?? '',
        'description': stringFromJson(e['description']) ?? '',
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get assignable users for a project. GET /rest/api/3/user/assignable/search
  Future<List<JiraUser>> getAssignableUsersForProject(String projectKey, {String? query}) async {
    try {
      final params = <String, String>{'project': projectKey, 'maxResults': '50'};
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

  /// Search issues with JQL. POST /rest/api/3/search/jql (matching React Native implementation)
  Future<List<JiraIssue>> searchIssues(String jql, {int maxResults = 50}) async {
    try {
      final uri = Uri.parse('$_baseUrl/rest/api/3/search/jql');
      final body = jsonEncode({
        'jql': jql,
        'maxResults': maxResults,
        'fields': ['summary', 'description', 'status', 'priority', 'assignee', 'issuetype', 'created', 'updated'],
      });
      final r = await http.post(
        uri,
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: body,
      ).timeout(_timeout);
      
      if (r.statusCode != 200) {
        debugPrint('JQL search error: ${r.statusCode} ${r.body}');
        return [];
      }
      
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      final list = (json['issues'] as List<dynamic>?) ?? [];
      return list.map((e) => JiraIssue.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('JQL search exception: $e');
      return [];
    }
  }

  /// Create a new issue. POST /rest/api/3/issue
  Future<String?> createIssue({
    required String projectKey,
    required String issueTypeId,
    required String summary,
    String? description,
    Map<String, dynamic>? descriptionAdf,
    String? assigneeAccountId,
    String? priorityId,
    String? dueDate,
    double? storyPoints,
    int? sprintId,
    String? parentKey,
  }) async {
    try {
      final fields = <String, dynamic>{
        'project': {'key': projectKey},
        'issuetype': {'id': issueTypeId},
        'summary': summary,
      };

      if (descriptionAdf != null) {
        fields['description'] = descriptionAdf;
      } else if (description != null && description.isNotEmpty) {
        fields['description'] = descriptionAdfFromPlainText(description);
      }

      if (assigneeAccountId != null && assigneeAccountId.isNotEmpty) {
        fields['assignee'] = {'accountId': assigneeAccountId};
      }

      if (priorityId != null && priorityId.isNotEmpty) {
        fields['priority'] = {'id': priorityId};
      }

      if (dueDate != null && dueDate.isNotEmpty) {
        fields['duedate'] = dueDate;
      }

      if (storyPoints != null) {
        fields['customfield_10016'] = storyPoints;
      }

      if (parentKey != null && parentKey.isNotEmpty) {
        fields['parent'] = {'key': parentKey};
      }

      final body = jsonEncode({'fields': fields});
      final r = await http.post(
        Uri.parse('$_baseUrl/rest/api/3/issue'),
        headers: _headers,
        body: body,
      ).timeout(_timeout);

      if (r.statusCode >= 200 && r.statusCode < 300) {
        final responseJson = jsonDecode(r.body) as Map<String, dynamic>;
        final issueKey = responseJson['key'] as String?;
        
        // If sprint is specified, move the issue to the sprint
        if (sprintId != null && issueKey != null) {
          await _moveIssueToSprint(issueKey, sprintId);
        }
        
        clearCache();
        return null;
      }

      // Parse error message
      try {
        final errorJson = jsonDecode(r.body) as Map<String, dynamic>;
        final errorMessages = errorJson['errorMessages'] as List<dynamic>?;
        if (errorMessages != null && errorMessages.isNotEmpty) {
          return errorMessages.join(', ');
        }
        final errors = errorJson['errors'] as Map<String, dynamic>?;
        if (errors != null && errors.isNotEmpty) {
          return errors.values.join(', ');
        }
      } catch (_) {}
      
      return 'Failed to create issue: ${r.statusCode}';
    } catch (e) {
      return e.toString();
    }
  }

  /// Move an issue to a sprint. POST /rest/agile/1.0/sprint/{sprintId}/issue
  Future<void> _moveIssueToSprint(String issueKey, int sprintId) async {
    try {
      final body = jsonEncode({'issues': [issueKey]});
      await http.post(
        Uri.parse('$_baseUrl/rest/agile/1.0/sprint/$sprintId/issue'),
        headers: _headers,
        body: body,
      ).timeout(_timeout);
    } catch (_) {
      // Ignore errors when moving to sprint
    }
  }

  /// Move an issue to a sprint (public). Returns error message or null on success.
  Future<String?> moveIssueToSprint(String issueKey, int sprintId) async {
    try {
      final body = jsonEncode({'issues': [issueKey]});
      final r = await http.post(
        Uri.parse('$_baseUrl/rest/agile/1.0/sprint/$sprintId/issue'),
        headers: _headers,
        body: body,
      ).timeout(_timeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _cache.remove(_cacheKey('/rest/api/3/issue/$issueKey', {}));
        return null;
      }
      try {
        final err = jsonDecode(r.body) as Map<String, dynamic>;
        final msgs = err['errorMessages'] as List<dynamic>?;
        if (msgs != null && msgs.isNotEmpty) return msgs.join(', ');
      } catch (_) {}
      return 'Failed to move issue: ${r.statusCode}';
    } catch (e) {
      return e.toString();
    }
  }

  /// Move an issue to the backlog for a board. POST /rest/agile/1.0/backlog/{boardId}/issue
  Future<String?> moveIssueToBacklog(String issueKey, int boardId) async {
    try {
      final body = jsonEncode({'issues': [issueKey]});
      final r = await http.post(
        Uri.parse('$_baseUrl/rest/agile/1.0/backlog/$boardId/issue'),
        headers: _headers,
        body: body,
      ).timeout(_timeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _cache.remove(_cacheKey('/rest/api/3/issue/$issueKey', {}));
        return null;
      }
      try {
        final err = jsonDecode(r.body) as Map<String, dynamic>;
        final msgs = err['errorMessages'] as List<dynamic>?;
        if (msgs != null && msgs.isNotEmpty) return msgs.join(', ');
      } catch (_) {}
      return 'Failed to move to backlog: ${r.statusCode}';
    } catch (e) {
      return e.toString();
    }
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
