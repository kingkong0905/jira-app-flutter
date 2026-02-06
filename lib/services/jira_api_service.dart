import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/jira_models.dart';
import 'http_constants.dart';

/// Jira REST API client with same endpoints and auth as reference app (kingkong0905/jira-app).
class JiraApiService {
  // Jira-specific constants
  static const String _userAgent = 'JiraManagementFlutter/1.0';

  // API Endpoints
  static const String _endpointApi3Myself = '/rest/api/3/myself';
  static const String _endpointApi2Myself = '/rest/api/2/myself';
  static const String _endpointApi3User = '/rest/api/3/user';
  static const String _endpointApi3Issue = '/rest/api/3/issue';
  static const String _endpointApi3Search = '/rest/api/3/search';
  static const String _endpointApi3SearchJql = '/rest/api/3/search/jql';
  static const String _endpointApi3Priority = '/rest/api/3/priority';
  static const String _endpointApi3UserAssignableSearch = '/rest/api/3/user/assignable/search';
  static const String _endpointApi3ProjectStatuses = '/rest/api/3/project';
  static const String _endpointAgileBoard = '/rest/agile/1.0/board';
  static const String _endpointAgileSprint = '/rest/agile/1.0/sprint';
  static const String _endpointApplinks = '/rest/applinks/3.0/applinks';
  static const String _endpointWikiPage = '/wiki/pages/viewpage.action';
  static const String _endpointDevStatusDetail = '/rest/dev-status/1.0/issue/detail';
  static const String _endpointApi3IssueLink = '/rest/api/3/issueLink';
  static const String _endpointApi3IssueLinkType = '/rest/api/3/issueLinkType';

  // Query Parameters
  static const String _paramStartAt = 'startAt';
  static const String _paramMaxResults = 'maxResults';
  static const String _paramFields = 'fields';
  static const String _paramJql = 'jql';
  static const String _paramName = 'name';
  static const String _paramProjectKeyOrId = 'projectKeyOrId';
  static const String _paramAssignee = 'assignee';
  static const String _paramAccountId = 'accountId';
  static const String _paramQuery = 'query';
  static const String _paramProject = 'project';
  static const String _paramExpand = 'expand';

  // Field Names
  static const String _fieldSummary = 'summary';
  static const String _fieldStatus = 'status';
  static const String _fieldPriority = 'priority';
  static const String _fieldAssignee = 'assignee';
  static const String _fieldIssueType = 'issuetype';
  static const String _fieldCreated = 'created';
  static const String _fieldUpdated = 'updated';
  static const String _fieldDueDate = 'duedate';
  static const String _fieldSprint = 'sprint';
  static const String _fieldDescription = 'description';
  static const String _fieldReporter = 'reporter';
  static const String _fieldComment = 'comment';
  static const String _fieldParent = 'parent';
  static const String _fieldAttachment = 'attachment';
  static const String _fieldProject = 'project';
  static const String _fieldCustomfield10016 = 'customfield_10016';
  static const String _fieldCustomfield10020 = 'customfield_10020';
  static const String _fieldSubtasks = 'subtasks';
  static const String _fieldIssueLinks = 'issuelinks';

  // Common Field Sets
  static const String _fieldsBasic = 'summary,status,priority,assignee,issuetype,created,updated,duedate,sprint';
  static const String _fieldsEpic = 'summary,status,priority,assignee,issuetype,created,updated,duedate';
  static const String _fieldsIssueDetails = 'summary,description,status,priority,assignee,reporter,issuetype,created,updated,duedate,customfield_10016,comment,parent,attachment,project,sprint,customfield_10020,subtasks,issuelinks';
  static const String _fieldsSearch = 'summary,description,status,priority,assignee,issuetype,created,updated';

  // JSON Keys
  static const String _jsonKeyValues = 'values';
  static const String _jsonKeyTotal = 'total';
  static const String _jsonKeyIsLast = 'isLast';
  static const String _jsonKeyIssues = 'issues';
  static const String _jsonKeyComments = 'comments';
  static const String _jsonKeyTransitions = 'transitions';
  static const String _jsonKeyErrorMessages = 'errorMessages';
  static const String _jsonKeyErrors = 'errors';
  static const String _jsonKeyKey = 'key';
  static const String _jsonKeyFields = 'fields';
  static const String _jsonKeyTransition = 'transition';
  static const String _jsonKeyId = 'id';
  static const String _jsonKeyState = 'state';
  static const String _jsonKeyName = 'name';
  static const String _jsonKeyGoal = 'goal';
  static const String _jsonKeyStartDate = 'startDate';
  static const String _jsonKeyEndDate = 'endDate';
  static const String _jsonKeyOriginBoardId = 'originBoardId';
  static const String _jsonKeyGlobalId = 'globalId';
  static const String _jsonKeyApplication = 'application';
  static const String _jsonKeyType = 'type';
  static const String _jsonKeyRelationship = 'relationship';
  static const String _jsonKeyObject = 'object';
  static const String _jsonKeyUrl = 'url';
  static const String _jsonKeyTitle = 'title';
  static const String _jsonKeyBody = 'body';
  static const String _jsonKeyVersion = 'version';
  static const String _jsonKeyContent = 'content';
  static const String _jsonKeyParagraph = 'paragraph';
  static const String _jsonKeyText = 'text';
  static const String _jsonKeyMention = 'mention';
  static const String _jsonKeyAttrs = 'attrs';
  static const String _jsonKeyParent = 'parent';
  static const String _jsonKeyRenderedBody = 'renderedBody';
  static const String _jsonKeyDetail = 'detail';

  // Confluence Constants
  static const String _confluenceType = 'com.atlassian.confluence';
  static const String _confluenceName = 'Confluence';
  static const String _confluenceRelationship = 'Wiki Page';
  static const String _confluencePageTitle = 'Confluence Page';

  // Sprint States
  static const String _sprintStateActive = 'active';
  static const String _sprintStateClosed = 'closed';
  static const String _sprintStateFuture = 'future';

  // JQL Keywords
  static const String _jqlAssigneeEmpty = 'assignee is EMPTY';
  static const String _jqlSprintEmpty = 'sprint is EMPTY';

  // Cache and Timeout
  JiraConfig? _config;
  final Map<String, _CacheEntry> _cache = {};
  static const _cacheDurationMs = 5 * 60 * 1000; // 5 min
  static const _issuesCacheMs = 60 * 1000; // 1 min for board issues
  static const _issueDetailsCacheMs = 2 * 60 * 1000; // 2 min
  static const _timeout = Duration(seconds: 45); // Increased from 25s to handle heavy loads
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
      HttpConstants.headerAuthorization: '${HttpConstants.authSchemeBasic} $auth',
      HttpConstants.headerContentType: HttpConstants.contentTypeJson,
      HttpConstants.headerAccept: HttpConstants.contentTypeJson,
      HttpConstants.headerUserAgent: _userAgent,
    };
  }

  /// Headers for authenticated media requests (e.g. video playback from attachment URL).
  Map<String, String> get authHeaders {
    final c = _config;
    if (c == null) throw StateError('Jira API not initialized.');
    final auth = base64Encode(utf8.encode('${c.email}:${c.apiToken}'));
    return {
      HttpConstants.headerAuthorization: '${HttpConstants.authSchemeBasic} $auth',
      HttpConstants.headerUserAgent: _userAgent,
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

  /// Clear caches related to a specific issue (issue details, comments, board issues).
  void _clearIssueCache(String issueKey) {
    _cache.remove(_cacheKey('$_endpointApi3Issue/$issueKey', {}));
    _cache.remove(_cacheKey('$_endpointApi3Issue/$issueKey/comment', {}));
    // Clear board issues caches (they may contain this issue)
    _cache.removeWhere((key, _) => key.contains(_endpointAgileBoard) && key.contains('/issue'));
    // Clear sprint issues caches
    _cache.removeWhere((key, _) => key.contains(_endpointAgileBoard) && key.contains('/sprint') && key.contains('/issue'));
    // Clear backlog caches
    _cache.removeWhere((key, _) => key.contains(_endpointAgileBoard) && key.contains('/backlog'));
  }

  /// Clear caches related to a board (board issues, sprints, assignees).
  void _clearBoardCache(int boardId) {
    _cache.removeWhere((key, _) => 
      key.contains('$_endpointAgileBoard/$boardId'));
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
        '$base$_endpointApi3Myself',
        '$base$_endpointApi2Myself',
      ];
      for (final url in urls) {
        _log('GET', url);
        try {
          final r = await http
              .get(Uri.parse(url), headers: _headers)
              .timeout(_connectionTestTimeout);
          _log('response', 'statusCode=${r.statusCode} url=$url');
          if (r.statusCode != HttpConstants.statusOk && r.body.isNotEmpty) {
            final bodyPreview = r.body.length > 300 ? '${r.body.substring(0, 300)}...' : r.body;
            _log('response body', bodyPreview.replaceAll('\n', ' '));
          }
          if (r.statusCode == HttpConstants.statusOk) {
            _log('testConnectionResult', 'SUCCESS');
            return null;
          }
          if (r.statusCode == HttpConstants.statusUnauthorized) {
            return 'Invalid email or API token. Check credentials and try again.';
          }
          if (r.statusCode == HttpConstants.statusForbidden) {
            return 'Access forbidden. Check your Jira permissions.';
          }
          // 404 etc.: try next URL
          if (r.statusCode == HttpConstants.statusNotFound) {
            _log('testConnectionResult', '404, trying next API version');
            continue;
          }
          try {
            final body = jsonDecode(r.body);
            final raw = body is Map ? (body[_jsonKeyErrorMessages] as List?)?.join(' ') ?? r.body : r.body;
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
    for (final path in [_endpointApi3Myself, _endpointApi2Myself]) {
      try {
        final r = await http.get(Uri.parse('$_baseUrl$path'), headers: _headers).timeout(_timeout);
        if (r.statusCode == HttpConstants.statusOk) {
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
      final uri = Uri.parse('$_baseUrl$_endpointApi3User').replace(queryParameters: {_paramAccountId: accountId});
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode == HttpConstants.statusOk) {
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
      if (r.statusCode == HttpConstants.statusOk) return r.bodyBytes;
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
      _paramStartAt: startAt.toString(),
      _paramMaxResults: maxResults.toString(),
    };
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      params[_paramName] = searchQuery.trim();
    }
    if (projectKeyOrId != null && projectKeyOrId.trim().isNotEmpty) {
      params[_paramProjectKeyOrId] = projectKeyOrId.trim();
    }
    final key = _cacheKey(_endpointAgileBoard, params);
    final cached = _getFromCache<BoardsResponse>(key, _cacheDurationMs);
    if (cached != null) return cached;

    final uri = Uri.parse('$_baseUrl$_endpointAgileBoard').replace(queryParameters: params);
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != HttpConstants.statusOk) throw JiraApiException(r.statusCode, r.body);

    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final boards = (json[_jsonKeyValues] as List<dynamic>?)
            ?.map((e) => JiraBoard.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final total = intFromJson(json[_jsonKeyTotal]) ?? 0;
    final isLast = json[_jsonKeyIsLast] as bool? ?? true;
    final result = BoardsResponse(boards: boards, total: total, isLast: isLast);
    _setCache(key, result);
    return result;
  }

  Future<JiraBoard?> getBoardById(int boardId) async {
    final r = await http
        .get(
          Uri.parse('$_baseUrl$_endpointAgileBoard/$boardId'),
          headers: _headers,
        )
        .timeout(_timeout);
    if (r.statusCode != HttpConstants.statusOk) return null;
    final json = jsonDecode(r.body) as Map<String, dynamic>;
    return JiraBoard.fromJson(json);
  }

  Future<List<JiraIssue>> getBoardIssues(int boardId, {int maxResults = 50, String? assignee}) async {
    final key = _cacheKey('$_endpointAgileBoard/$boardId/issue', {_paramMaxResults: maxResults, _paramAssignee: assignee ?? 'all'});
    final cached = _getFromCache<List<JiraIssue>>(key, _issuesCacheMs);
    if (cached != null) return cached;

    final params = <String, String>{
      _paramMaxResults: maxResults.toString(),
      _paramFields: _fieldsBasic,
    };
    if (assignee != null && assignee.isNotEmpty && assignee != 'all') {
      if (assignee == 'unassigned') {
        params[_paramJql] = _jqlAssigneeEmpty;
      } else {
        params[_paramJql] = 'assignee = "$assignee"';
      }
    }
    final uri = Uri.parse('$_baseUrl$_endpointAgileBoard/$boardId/issue').replace(queryParameters: params);
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != HttpConstants.statusOk) throw JiraApiException(r.statusCode, r.body);

    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (json[_jsonKeyIssues] as List<dynamic>?) ?? [];
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
        _paramStartAt: '$startAt',
        _paramMaxResults: '$maxResults',
        _paramFields: _fieldsBasic,
      };
      if (assignee != null && assignee.isNotEmpty && assignee != 'all') {
        if (assignee == 'unassigned') {
          params[_paramJql] = _jqlAssigneeEmpty;
        } else {
          params[_paramJql] = 'assignee = "$assignee"';
        }
      }
      final uri = Uri.parse('$_baseUrl$_endpointAgileBoard/$boardId/issue').replace(queryParameters: params);
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode != HttpConstants.statusOk) throw JiraApiException(r.statusCode, r.body);
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      final list = (json[_jsonKeyIssues] as List<dynamic>?) ?? [];
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
    final key = _cacheKey('$_endpointAgileBoard/$boardId/assignees', {});
    final cached = _getFromCache<List<BoardAssignee>>(key, _cacheDurationMs);
    if (cached != null) return cached;

    // OPTIMIZED: Fetch only 150 issues instead of 1000 to reduce load time
    // This should be sufficient to get most active assignees
    final params = {_paramMaxResults: '150', _paramFields: _fieldAssignee};
    final uri = Uri.parse('$_baseUrl$_endpointAgileBoard/$boardId/issue').replace(queryParameters: params);
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != HttpConstants.statusOk) return [];

    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (json[_jsonKeyIssues] as List<dynamic>?) ?? [];
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
    final key = _cacheKey('$_endpointAgileBoard/$boardId/sprint', {});
    final cached = _getFromCache<List<JiraSprint>>(key, _cacheDurationMs);
    if (cached != null) return cached;

    try {
      final r = await http
          .get(
            Uri.parse('$_baseUrl$_endpointAgileBoard/$boardId/sprint'),
            headers: _headers,
          )
          .timeout(_timeout);
      if (r.statusCode == HttpConstants.statusBadRequest || r.statusCode == HttpConstants.statusNotFound) return [];
      if (r.statusCode != HttpConstants.statusOk) throw JiraApiException(r.statusCode, r.body);

      final json = jsonDecode(r.body) as Map<String, dynamic>;
      final list = (json[_jsonKeyValues] as List<dynamic>?) ?? [];
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
      return sprints.firstWhere((s) => s.state == _sprintStateActive);
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
        _jsonKeyName: name,
        _jsonKeyOriginBoardId: boardId,
      };

      if (goal != null && goal.isNotEmpty) {
        body[_jsonKeyGoal] = goal;
      }

      if (startDate != null && startDate.isNotEmpty) {
        body[_jsonKeyStartDate] = startDate;
      }

      if (endDate != null && endDate.isNotEmpty) {
        body[_jsonKeyEndDate] = endDate;
      }

      final r = await http.post(
        Uri.parse('$_baseUrl$_endpointAgileSprint'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(_timeout);

      if (r.statusCode >= HttpConstants.statusSuccessMin && r.statusCode <= HttpConstants.statusSuccessMax) {
        clearCache();
        return null; // Success
      }

      // Parse error message
      try {
        final errorJson = jsonDecode(r.body) as Map<String, dynamic>;
        final errorMessages = errorJson[_jsonKeyErrorMessages] as List<dynamic>?;
        if (errorMessages != null && errorMessages.isNotEmpty) {
          return errorMessages.join(', ');
        }
        final errors = errorJson[_jsonKeyErrors] as Map<String, dynamic>?;
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
    // Add caching to reduce redundant API calls
    final cacheKey = _cacheKey('$_endpointAgileBoard/$boardId/sprint/$sprintId/issue', {'assignee': assignee ?? 'all'});
    final cached = _getFromCache<List<JiraIssue>>(cacheKey, _issuesCacheMs);
    if (cached != null) return cached;

    final results = <JiraIssue>[];
    int startAt = 0;
    const maxResults = 50;
    while (true) {
      final params = <String, String>{
        _paramStartAt: '$startAt',
        _paramMaxResults: '$maxResults',
        _paramFields: _fieldsBasic,
      };
      if (assignee != null && assignee.isNotEmpty && assignee != 'all') {
        if (assignee == 'unassigned') {
          params[_paramJql] = _jqlAssigneeEmpty;
        } else {
          params[_paramJql] = 'assignee = "$assignee"';
        }
      }
      final uri = Uri.parse('$_baseUrl$_endpointAgileBoard/$boardId/sprint/$sprintId/issue')
          .replace(queryParameters: params);
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode != HttpConstants.statusOk) throw JiraApiException(r.statusCode, r.body);

      final json = jsonDecode(r.body) as Map<String, dynamic>;
      final list = (json[_jsonKeyIssues] as List<dynamic>?) ?? [];
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
    
    // Cache the results
    _setCache(cacheKey, results);
    return results;
  }

  /// Fetches one page of backlog issues (board backlog API). Returns issues and whether more pages exist.
  Future<({List<JiraIssue> issues, bool hasMore})> getBacklogIssuesPage(
    int boardId, {
    int startAt = 0,
    int maxResults = 50,
    String? assignee,
  }) async {
    // Add caching to reduce redundant API calls
    final cacheKey = _cacheKey('$_endpointAgileBoard/$boardId/backlog', {
      'startAt': startAt,
      'maxResults': maxResults,
      'assignee': assignee ?? 'all',
    });
    final cached = _getFromCache<({List<JiraIssue> issues, bool hasMore})>(cacheKey, _issuesCacheMs);
    if (cached != null) return cached;

    final params = <String, String>{
      _paramStartAt: '$startAt',
      _paramMaxResults: '$maxResults',
      _paramFields: _fieldsBasic,
    };
    if (assignee != null && assignee.isNotEmpty && assignee != 'all') {
      if (assignee == 'unassigned') {
        params[_paramJql] = _jqlAssigneeEmpty;
      } else {
        params[_paramJql] = 'assignee = "$assignee"';
      }
    }
    final uri = Uri.parse('$_baseUrl$_endpointAgileBoard/$boardId/backlog').replace(queryParameters: params);
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != HttpConstants.statusOk) throw JiraApiException(r.statusCode, r.body);

    final json = jsonDecode(r.body) as Map<String, dynamic>;
    List<dynamic> list = (json[_jsonKeyIssues] as List<dynamic>?) ?? (json[_jsonKeyValues] as List<dynamic>?) ?? [];
    if (list.isEmpty && json['contents'] is Map) {
      final contents = json['contents'] as Map<String, dynamic>;
      list = (contents[_jsonKeyIssues] as List<dynamic>?) ?? (contents[_jsonKeyValues] as List<dynamic>?) ?? [];
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
    final result = (issues: issues, hasMore: hasMore);
    
    // Cache the result
    _setCache(cacheKey, result);
    return result;
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
    final jql = StringBuffer('project = $projectKey AND $_jqlSprintEmpty');
    if (assignee != null && assignee.isNotEmpty && assignee != 'all') {
      if (assignee == 'unassigned') {
        jql.write(' AND $_jqlAssigneeEmpty');
      } else {
        jql.write(' AND assignee = "$assignee"');
      }
    }
    final uri = Uri.parse('$_baseUrl$_endpointApi3Search').replace(queryParameters: {
      _paramJql: jql.toString(),
      _paramStartAt: '$startAt',
      _paramMaxResults: '$maxResults',
      _paramFields: _fieldsBasic,
    });
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != HttpConstants.statusOk) return (issues: <JiraIssue>[], hasMore: false, total: 0);
    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (json[_jsonKeyIssues] as List<dynamic>?) ?? [];
    final total = (json[_jsonKeyTotal] as int?) ?? 0;
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
    final key = _cacheKey('$_endpointApi3Issue/$issueKey', {});
    final cached = _getFromCache<JiraIssue>(key, _issueDetailsCacheMs);
    if (cached != null) return cached;

    final params = {
      _paramFields: _fieldsIssueDetails,
    };
    final uri = Uri.parse('$_baseUrl$_endpointApi3Issue/$issueKey').replace(queryParameters: params);
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != HttpConstants.statusOk) throw JiraApiException(r.statusCode, r.body);

    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final issue = JiraIssue.fromJson(json);
    _setCache(key, issue);
    return issue;
  }

  /// Get remote issue links (e.g. Confluence pages). GET /rest/api/3/issue/{key}/remotelink.
  Future<List<JiraRemoteLink>> getRemoteLinks(String issueKey) async {
    try {
      final r = await http.get(
        Uri.parse('$_baseUrl$_endpointApi3Issue/$issueKey/remotelink'),
        headers: _headers,
      ).timeout(_timeout);
      if (r.statusCode != HttpConstants.statusOk) return [];
      final list = jsonDecode(r.body);
      if (list is! List) return [];
      return (list as List<dynamic>)
          .map((e) => JiraRemoteLink.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Get development information (branches, commits, pull requests) linked to an issue via dev-status REST API.
  /// Uses issueId (numeric ID) with dataType=repository for comprehensive GitHub integration.
  Future<JiraDevelopmentInfo> getDevelopmentInfo(String issueId) async {
    if (issueId.isEmpty) {
      return JiraDevelopmentInfo(branches: [], commits: [], pullRequests: []);
    }

    final branches = <JiraDevelopmentBranch>[];
    final commits = <JiraDevelopmentCommit>[];
    final pullRequests = <JiraDevelopmentPullRequest>[];
    final seenBranchUrls = <String>{};
    final seenCommitUrls = <String>{};
    final seenPrUrls = <String>{};

    for (final applicationType in ['github', 'stash']) {
      try {
        final uri = Uri.parse('$_baseUrl$_endpointDevStatusDetail').replace(
          queryParameters: {
            'issueId': issueId,
            'applicationType': applicationType,
            'dataType': 'repository',
          },
        );
        final r = await http.get(uri, headers: _headers).timeout(_timeout);
        if (r.statusCode != HttpConstants.statusOk) continue;

        final body = jsonDecode(r.body);
        if (body is! Map) continue;
        final detail = body['detail'];
        if (detail is! List) continue;

        for (final repo in detail) {
          if (repo is! Map) continue;

          // Parse branches
          final branchesData = repo['branches'] as List?;
          if (branchesData != null) {
            for (final branchJson in branchesData) {
              if (branchJson is Map<String, dynamic>) {
                try {
                  final branch = JiraDevelopmentBranch.fromJson(branchJson);
                  if (branch.url.isNotEmpty && seenBranchUrls.add(branch.url)) {
                    branches.add(branch);
                  }
                } catch (_) {}
              }
            }
          }

          // Parse commits
          final commitsData = repo['commits'] as List?;
          if (commitsData != null) {
            for (final commitJson in commitsData) {
              if (commitJson is Map<String, dynamic>) {
                try {
                  final commit = JiraDevelopmentCommit.fromJson(commitJson);
                  if (commit.url.isNotEmpty && seenCommitUrls.add(commit.url)) {
                    commits.add(commit);
                  }
                } catch (_) {}
              }
            }
          }

          // Parse pull requests
          final prsData = repo['pullRequests'] as List?;
          if (prsData != null) {
            for (final prJson in prsData) {
              if (prJson is Map<String, dynamic>) {
                try {
                  final pr = JiraDevelopmentPullRequest.fromJson(prJson);
                  if (pr.url.isNotEmpty && seenPrUrls.add(pr.url)) {
                    pullRequests.add(pr);
                  }
                } catch (_) {}
              }
            }
          }
        }
      } catch (e) {
        print('[JiraAPI] getDevelopmentInfo error for $applicationType: $e');
        // One integration may fail; continue with the other
      }
    }

    return JiraDevelopmentInfo(
      branches: branches,
      commits: commits,
      pullRequests: pullRequests,
    );
  }

  /// Legacy method for backward compatibility. Use getDevelopmentInfo instead.
  @Deprecated('Use getDevelopmentInfo instead')
  Future<List<JiraDevelopmentPullRequest>> getDevelopmentPullRequests(String issueKey) async {
    // For backward compatibility, fetch issue details to get the ID
    final issue = await getIssueDetails(issueKey);
    if (issue == null) return [];
    final devInfo = await getDevelopmentInfo(issue.id);
    return devInfo.pullRequests;
  }

  /// Try to get Confluence application id from applinks (for creating Confluence remote link).
  Future<String?> getConfluenceAppId() async {
    try {
      final r = await http.get(
        Uri.parse('$_baseUrl$_endpointApplinks'),
        headers: _headers,
      ).timeout(_timeout);
      if (r.statusCode != HttpConstants.statusOk) return null;
      final list = jsonDecode(r.body);
      if (list is! List) return null;
      for (final e in list as List<dynamic>) {
        if (e is! Map) continue;
        final type = stringFromJson(e[_jsonKeyType]);
        if (type != null && type.toLowerCase().contains('confluence')) {
          final id = stringFromJson(e[_jsonKeyId]);
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
        : '$_baseUrl$_endpointWikiPage?pageId=$pid';
    final body = {
      _jsonKeyGlobalId: globalId,
      _jsonKeyApplication: {
        _jsonKeyType: _confluenceType,
        _jsonKeyName: _confluenceName,
      },
      _jsonKeyRelationship: _confluenceRelationship,
      _jsonKeyObject: {
        _jsonKeyUrl: url,
        _jsonKeyTitle: title.isNotEmpty ? title : _confluencePageTitle,
      },
    };
    try {
      final r = await http.post(
        Uri.parse('$_baseUrl$_endpointApi3Issue/$issueKey/remotelink'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(_timeout);
      if (r.statusCode == HttpConstants.statusOk || r.statusCode == HttpConstants.statusCreated) {
        _clearIssueCache(issueKey);
        return null;
      }
      return r.body;
    } catch (e) {
      return e.toString();
    }
  }

  /// Delete a remote issue link. DELETE /rest/api/3/issue/{key}/remotelink/{linkId}.
  Future<String?> deleteRemoteLink(String issueKey, int linkId) async {
    try {
      final r = await http.delete(
        Uri.parse('$_baseUrl$_endpointApi3Issue/$issueKey/remotelink/$linkId'),
        headers: _headers,
      ).timeout(_timeout);
      if (r.statusCode == HttpConstants.statusNoContent || r.statusCode == HttpConstants.statusOk) {
        _clearIssueCache(issueKey);
        return null;
      }
      return r.body;
    } catch (e) {
      return e.toString();
    }
  }

  /// Get available issue link types from Jira. GET /rest/api/3/issueLinkType.
  Future<List<JiraIssueLinkType>> getIssueLinkTypes() async {
    final key = _cacheKey(_endpointApi3IssueLinkType, {});
    final cached = _getFromCache<List<JiraIssueLinkType>>(key, _cacheDurationMs);
    if (cached != null) return cached;
    try {
      final r = await http.get(
        Uri.parse('$_baseUrl$_endpointApi3IssueLinkType'),
        headers: _headers,
      ).timeout(_timeout);
      if (r.statusCode == HttpConstants.statusOk) {
        final json = jsonDecode(r.body);
        final linkTypes = JiraIssueLinkType.fromJsonList(json['issueLinkTypes']);
        _setCache(key, linkTypes);
        return linkTypes;
      }
    } catch (e) {
      print('[JiraAPI] getIssueLinkTypes error: $e');
    }
    return [];
  }

  /// Create an issue link between two issues. POST /rest/api/3/issueLink.
  Future<String?> linkIssues({
    required String linkTypeName,
    required String inwardIssueKey,
    required String outwardIssueKey,
    String? commentText,
  }) async {
    try {
      final body = <String, dynamic>{
        'type': {'name': linkTypeName},
        'inwardIssue': {'key': inwardIssueKey},
        'outwardIssue': {'key': outwardIssueKey},
      };
      if (commentText != null && commentText.isNotEmpty) {
        body['comment'] = {'body': commentText};
      }
      final r = await http.post(
        Uri.parse('$_baseUrl$_endpointApi3IssueLink'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(_timeout);
      if (r.statusCode == HttpConstants.statusOk || r.statusCode == HttpConstants.statusCreated) {
        _clearIssueCache(inwardIssueKey);
        _clearIssueCache(outwardIssueKey);
        return null;
      }
      // Try to parse error messages from response
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
      return r.body;
    } catch (e) {
      return e.toString();
    }
  }

  /// Delete an issue link. DELETE /rest/api/3/issueLink/{linkId}.
  Future<String?> deleteIssueLink(String linkId) async {
    try {
      final r = await http.delete(
        Uri.parse('$_baseUrl$_endpointApi3IssueLink/$linkId'),
        headers: _headers,
      ).timeout(_timeout);
      if (r.statusCode == HttpConstants.statusNoContent || r.statusCode == HttpConstants.statusOk) {
        // Clear all issue caches since we can't determine affected issues from linkId
        _cache.removeWhere((key, _) => key.contains(_endpointApi3Issue));
        return null;
      }
      return r.body;
    } catch (e) {
      return e.toString();
    }
  }

  /// Fetch subtasks for an issue (JQL: parent = issueKey). Quoting the key for JQL safety.
  Future<List<JiraIssue>> getSubtasks(String issueKey) async {
    final jql = 'parent = "$issueKey"';
    final uri = Uri.parse('$_baseUrl$_endpointApi3Search').replace(
      queryParameters: {
        _paramJql: jql,
        _paramMaxResults: '50',
        _paramFields: _fieldsEpic,
      },
    );
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != HttpConstants.statusOk) return [];
    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (json[_jsonKeyIssues] as List<dynamic>?) ?? [];
    return list.map((e) => JiraIssue.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Fetch all issues that belong to an Epic (Task, Sub-task, Bug, Story, etc.). Tries parentEpic first, then parent = key.
  Future<List<JiraIssue>> getEpicChildren(String issueKey) async {
    final params = (String jql) => {_paramJql: jql, _paramMaxResults: '100', _paramFields: _fieldsEpic};

    // 1) parentEpic = key returns direct children + nested sub-tasks (all types) in Jira Cloud
    try {
      final uri = Uri.parse('$_baseUrl$_endpointApi3Search').replace(queryParameters: params('parentEpic = "$issueKey"'));
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode == HttpConstants.statusOk) {
        final json = jsonDecode(r.body) as Map<String, dynamic>;
        final list = (json[_jsonKeyIssues] as List<dynamic>?) ?? [];
        if (list.isNotEmpty) {
          return list.map((e) => JiraIssue.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}

    // 2) Fallback: parent = key (direct children – Task, Bug, Story, Sub-task under Epic)
    try {
      final uri = Uri.parse('$_baseUrl$_endpointApi3Search').replace(queryParameters: params('parent = "$issueKey"'));
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode == HttpConstants.statusOk) {
        final json = jsonDecode(r.body) as Map<String, dynamic>;
        final list = (json[_jsonKeyIssues] as List<dynamic>?) ?? [];
        if (list.isNotEmpty) {
          return list.map((e) => JiraIssue.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}

    // 3) Fallback: "Epic Link" = key (classic/company-managed projects using Epic Link field)
    try {
      final jql = '"Epic Link" = "$issueKey"';
      final uri = Uri.parse('$_baseUrl$_endpointApi3Search').replace(queryParameters: {_paramJql: jql, _paramMaxResults: '100', _paramFields: _fieldsEpic});
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode == HttpConstants.statusOk) {
        final json = jsonDecode(r.body) as Map<String, dynamic>;
        final list = (json[_jsonKeyIssues] as List<dynamic>?) ?? [];
        return list.map((e) => JiraIssue.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}

    return [];
  }

  /// Get available transitions for an issue (for status change). GET /rest/api/3/issue/{key}/transitions.
  Future<List<Map<String, dynamic>>> getTransitions(String issueKey) async {
    try {
      final r = await http.get(
        Uri.parse('$_baseUrl$_endpointApi3Issue/$issueKey/transitions'),
        headers: _headers,
      ).timeout(_timeout);
      if (r.statusCode != HttpConstants.statusOk) return [];
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      final list = json[_jsonKeyTransitions] as List<dynamic>?;
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
        Uri.parse('$_baseUrl$_endpointApi3Issue/$issueKey/transitions'),
        headers: _headers,
        body: jsonEncode({_jsonKeyTransition: {_jsonKeyId: transitionId}}),
      ).timeout(_timeout);
      if (r.statusCode >= HttpConstants.statusSuccessMin && r.statusCode <= HttpConstants.statusSuccessMax) {
        _clearIssueCache(issueKey);
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
      final params = <String, String>{'issueKey': issueKey, _paramMaxResults: '50'};
      if (query != null && query.isNotEmpty) params[_paramQuery] = query;
      final uri = Uri.parse('$_baseUrl$_endpointApi3UserAssignableSearch').replace(queryParameters: params);
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode != HttpConstants.statusOk) return [];
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
      final r = await http.get(Uri.parse('$_baseUrl$_endpointApi3Priority'), headers: _headers).timeout(_timeout);
      if (r.statusCode != HttpConstants.statusOk) return [];
      final list = jsonDecode(r.body) as List<dynamic>?;
      if (list == null) return [];
      return list.map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  /// Update issue fields (assignee, priority, duedate, summary, description, customfield_10016, etc.). Same as reference.
  Future<String?> updateIssueField(String issueKey, Map<String, dynamic> fields) async {
    final body = jsonEncode({_jsonKeyFields: fields});
      final r = await http.put(
        Uri.parse('$_baseUrl$_endpointApi3Issue/$issueKey'),
        headers: _headers,
        body: body,
      ).timeout(_timeout);
      if (r.statusCode >= HttpConstants.statusSuccessMin && r.statusCode <= HttpConstants.statusSuccessMax) {
        _clearIssueCache(issueKey);
        return null;
      }
    return r.body;
  }

  Future<List<dynamic>> getIssueComments(String issueKey) async {
    final uri = Uri.parse('$_baseUrl$_endpointApi3Issue/$issueKey/comment').replace(
      queryParameters: {_paramExpand: _jsonKeyRenderedBody},
    );
    final r = await http.get(uri, headers: _headers).timeout(_timeout);
    if (r.statusCode != HttpConstants.statusOk) return [];
    final json = jsonDecode(r.body) as Map<String, dynamic>;
    return (json[_jsonKeyComments] as List<dynamic>?) ?? [];
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
      payload[_jsonKeyParent] = {_jsonKeyId: parentCommentId};
    }
    final r = await http.post(
      Uri.parse('$_baseUrl$_endpointApi3Issue/$issueKey/comment'),
      headers: _headers,
      body: jsonEncode(payload),
    ).timeout(_timeout);
    if (r.statusCode >= HttpConstants.statusSuccessMin && r.statusCode <= HttpConstants.statusSuccessMax) {
      _clearIssueCache(issueKey);
      return null;
    }
    return r.body;
  }

  /// Update comment. Returns error message or null on success.
  Future<String?> updateComment(String issueKey, String commentId, String text) async {
    final body = _commentBodyAdf(text);
    final r = await http.put(
      Uri.parse('$_baseUrl$_endpointApi3Issue/$issueKey/comment/$commentId'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(_timeout);
    if (r.statusCode >= HttpConstants.statusSuccessMin && r.statusCode <= HttpConstants.statusSuccessMax) {
      _clearIssueCache(issueKey);
      return null;
    }
    return r.body;
  }

  /// Delete comment. Returns error message or null on success.
  Future<String?> deleteComment(String issueKey, String commentId) async {
      final r = await http.delete(
        Uri.parse('$_baseUrl$_endpointApi3Issue/$issueKey/comment/$commentId'),
        headers: _headers,
      ).timeout(_timeout);
      if (r.statusCode >= HttpConstants.statusSuccessMin && r.statusCode <= HttpConstants.statusSuccessMax) {
        _clearIssueCache(issueKey);
        return null;
      }
    return r.body;
  }

  Future<void> completeSprint(int sprintId) async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl$_endpointAgileSprint/$sprintId'),
          headers: _headers,
          body: jsonEncode({_jsonKeyState: _sprintStateClosed}),
        )
        .timeout(_timeout);
    if (r.statusCode != HttpConstants.statusOk) throw JiraApiException(r.statusCode, r.body);
    clearCache();
  }

  /// Start a future sprint (set state to active). Sprint must be in 'future' and have startDate/endDate.
  Future<void> startSprint(int sprintId) async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl$_endpointAgileSprint/$sprintId'),
          headers: _headers,
          body: jsonEncode({_jsonKeyState: _sprintStateActive}),
        )
        .timeout(_timeout);
    if (r.statusCode != HttpConstants.statusOk) throw JiraApiException(r.statusCode, r.body);
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
      final body = <String, dynamic>{_jsonKeyName: name};
      if (goal != null) body[_jsonKeyGoal] = goal;
      if (startDate != null) body[_jsonKeyStartDate] = startDate;
      if (endDate != null) body[_jsonKeyEndDate] = endDate;
      final r = await http
          .put(
            Uri.parse('$_baseUrl$_endpointAgileSprint/$sprintId'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (r.statusCode != HttpConstants.statusOk) return 'Failed to update sprint: ${r.statusCode}';
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
          .delete(Uri.parse('$_baseUrl$_endpointAgileSprint/$sprintId'), headers: _headers)
          .timeout(_timeout);
      if (r.statusCode != HttpConstants.statusOk && r.statusCode != HttpConstants.statusNoContent) return 'Failed to delete sprint: ${r.statusCode}';
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
        Uri.parse('$_baseUrl$_endpointApi3ProjectStatuses/$projectKey/statuses'),
        headers: _headers,
      ).timeout(_timeout);
      if (r.statusCode != HttpConstants.statusOk) return [];
      final list = jsonDecode(r.body) as List<dynamic>?;
      if (list == null) return [];
      return list.map((e) => {
        _jsonKeyId: e[_jsonKeyId].toString(),
        _jsonKeyName: stringFromJson(e[_jsonKeyName]) ?? '',
        'description': stringFromJson(e['description']) ?? '',
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get assignable users for a project. GET /rest/api/3/user/assignable/search
  Future<List<JiraUser>> getAssignableUsersForProject(String projectKey, {String? query}) async {
    try {
      final params = <String, String>{_paramProject: projectKey, _paramMaxResults: '50'};
      if (query != null && query.isNotEmpty) params[_paramQuery] = query;
      final uri = Uri.parse('$_baseUrl$_endpointApi3UserAssignableSearch').replace(queryParameters: params);
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode != HttpConstants.statusOk) return [];
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
      final uri = Uri.parse('$_baseUrl$_endpointApi3SearchJql');
      final body = jsonEncode({
        _paramJql: jql,
        _paramMaxResults: maxResults,
        _paramFields: _fieldsSearch.split(',').map((e) => e.trim()).toList(),
      });
      final r = await http.post(
        uri,
        headers: {..._headers, HttpConstants.headerContentType: HttpConstants.contentTypeJson},
        body: body,
      ).timeout(_timeout);
      
      if (r.statusCode != HttpConstants.statusOk) {
        debugPrint('JQL search error: ${r.statusCode} ${r.body}');
        return [];
      }
      
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      final list = (json[_jsonKeyIssues] as List<dynamic>?) ?? [];
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
        _fieldProject: {_jsonKeyKey: projectKey},
        _fieldIssueType: {_jsonKeyId: issueTypeId},
        _fieldSummary: summary,
      };

      if (descriptionAdf != null) {
        fields[_fieldDescription] = descriptionAdf;
      } else if (description != null && description.isNotEmpty) {
        fields[_fieldDescription] = descriptionAdfFromPlainText(description);
      }

      if (assigneeAccountId != null && assigneeAccountId.isNotEmpty) {
        fields[_fieldAssignee] = {_paramAccountId: assigneeAccountId};
      }

      if (priorityId != null && priorityId.isNotEmpty) {
        fields[_fieldPriority] = {_jsonKeyId: priorityId};
      }

      if (dueDate != null && dueDate.isNotEmpty) {
        fields[_fieldDueDate] = dueDate;
      }

      if (storyPoints != null) {
        fields[_fieldCustomfield10016] = storyPoints;
      }

      if (parentKey != null && parentKey.isNotEmpty) {
        fields[_fieldParent] = {_jsonKeyKey: parentKey};
      }

      final body = jsonEncode({_jsonKeyFields: fields});
      final r = await http.post(
        Uri.parse('$_baseUrl$_endpointApi3Issue'),
        headers: _headers,
        body: body,
      ).timeout(_timeout);

      if (r.statusCode >= HttpConstants.statusSuccessMin && r.statusCode <= HttpConstants.statusSuccessMax) {
        final responseJson = jsonDecode(r.body) as Map<String, dynamic>;
        final issueKey = responseJson[_jsonKeyKey] as String?;
        
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
        final errorMessages = errorJson[_jsonKeyErrorMessages] as List<dynamic>?;
        if (errorMessages != null && errorMessages.isNotEmpty) {
          return errorMessages.join(', ');
        }
        final errors = errorJson[_jsonKeyErrors] as Map<String, dynamic>?;
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
      final body = jsonEncode({_jsonKeyIssues: [issueKey]});
      final r = await http.post(
        Uri.parse('$_baseUrl$_endpointAgileSprint/$sprintId/issue'),
        headers: _headers,
        body: body,
      ).timeout(_timeout);
      if (r.statusCode >= HttpConstants.statusSuccessMin && r.statusCode <= HttpConstants.statusSuccessMax) {
        _clearIssueCache(issueKey);
        // Clear board caches since sprint assignment affects board views
        _cache.removeWhere((key, _) => 
          key.contains(_endpointAgileBoard) && 
          (key.contains('/issue') || key.contains('/sprint') || key.contains('/backlog')));
      }
    } catch (_) {
      // Ignore errors when moving to sprint
    }
  }

  /// Move an issue to a sprint (public). Returns error message or null on success.
  Future<String?> moveIssueToSprint(String issueKey, int sprintId) async {
    try {
      final body = jsonEncode({_jsonKeyIssues: [issueKey]});
      final r = await http.post(
        Uri.parse('$_baseUrl$_endpointAgileSprint/$sprintId/issue'),
        headers: _headers,
        body: body,
      ).timeout(_timeout);
      if (r.statusCode >= HttpConstants.statusSuccessMin && r.statusCode <= HttpConstants.statusSuccessMax) {
        _clearIssueCache(issueKey);
        // Clear board caches since sprint assignment affects board views
        // Extract boardId from sprint if possible, otherwise clear all board caches
        _cache.removeWhere((key, _) => 
          key.contains(_endpointAgileBoard) && 
          (key.contains('/issue') || key.contains('/sprint') || key.contains('/backlog')));
        return null;
      }
      try {
        final err = jsonDecode(r.body) as Map<String, dynamic>;
        final msgs = err[_jsonKeyErrorMessages] as List<dynamic>?;
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
      final body = jsonEncode({_jsonKeyIssues: [issueKey]});
      final r = await http.post(
        Uri.parse('$_baseUrl$_endpointAgileBoard/$boardId/backlog/issue'),
        headers: _headers,
        body: body,
      ).timeout(_timeout);
      if (r.statusCode >= HttpConstants.statusSuccessMin && r.statusCode <= HttpConstants.statusSuccessMax) {
        _clearIssueCache(issueKey);
        _clearBoardCache(boardId);
        return null;
      }
      try {
        final err = jsonDecode(r.body) as Map<String, dynamic>;
        final msgs = err[_jsonKeyErrorMessages] as List<dynamic>?;
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
