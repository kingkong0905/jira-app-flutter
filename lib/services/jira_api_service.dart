import 'dart:convert';
import 'package:crypto/crypto.dart';
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

  /// Upload attachment to an issue. POST /rest/api/3/issue/{issueKey}/attachments
  /// Returns the uploaded attachment info (id, filename, content URL) or null on error.
  Future<Map<String, String>?> uploadAttachment(String issueKey, String filePath, String filename) async {
    try {
      final file = await http.MultipartFile.fromPath('file', filePath, filename: filename);
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/rest/api/3/issue/$issueKey/attachments'),
      );
      
      // Set headers for multipart request (without Content-Type, let it be set automatically)
      final auth = base64Encode(utf8.encode('${_config!.email}:${_config!.apiToken}'));
      request.headers['Authorization'] = 'Basic $auth';
      request.headers['X-Atlassian-Token'] = 'no-check'; // Required for Jira Cloud
      request.headers['Accept'] = 'application/json';
      
      request.files.add(file);
      
      final streamedResponse = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Clear cache for issue details
        _setCache(_cacheKey('/rest/api/3/issue/$issueKey', {}), null);
        try {
          final json = jsonDecode(response.body) as List<dynamic>;
          if (json.isNotEmpty && json[0] is Map) {
            final attachment = json[0] as Map<String, dynamic>;
            final id = stringFromJson(attachment['id']);
            
            // Debug: log attachment response to see available fields
            if (debugLog) {
              _log('Attachment upload response', jsonEncode(attachment));
            }
            
            final contentUrl = stringFromJson(attachment['content']);
            final mimeType = stringFromJson(attachment['mimeType']) ?? 'application/octet-stream';
            if (id != null) {
              // Jira returns numeric IDs, but ADF media nodes require UUID format
              // Generate a deterministic UUID v5 from the attachment ID
              // This creates a consistent UUID that can be used in ADF media nodes
              final mediaId = _generateUuidV5('6ba7b810-9dad-11d1-80b4-00c04fd430c8', id);
              
              if (debugLog) {
                _log('Generated UUID for attachment', 'ID: $id -> UUID: $mediaId');
              }
              
              return {
                'id': id, // Numeric ID for reference
                'mediaId': mediaId, // UUID format for ADF media nodes
                'filename': filename,
                'content': contentUrl ?? '',
                'mimeType': mimeType,
              };
            }
          }
        } catch (_) {}
        return null;
      }
      
      _log('uploadAttachment failed', 'statusCode=${response.statusCode} body=${response.body}');
      return null;
    } catch (e) {
      _log('uploadAttachment exception', e.toString());
      return null;
    }
  }

  /// Upload attachment from bytes (for web platform). POST /rest/api/3/issue/{issueKey}/attachments
  /// Returns the uploaded attachment info (id, filename, content URL) or null on error.
  Future<Map<String, String>?> uploadAttachmentFromBytes(String issueKey, List<int> bytes, String filename) async {
    try {
      final file = http.MultipartFile.fromBytes('file', bytes, filename: filename);
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/rest/api/3/issue/$issueKey/attachments'),
      );
      
      // Set headers for multipart request (without Content-Type, let it be set automatically)
      final auth = base64Encode(utf8.encode('${_config!.email}:${_config!.apiToken}'));
      request.headers['Authorization'] = 'Basic $auth';
      request.headers['X-Atlassian-Token'] = 'no-check'; // Required for Jira Cloud
      request.headers['Accept'] = 'application/json';
      
      request.files.add(file);
      
      final streamedResponse = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Clear cache for issue details
        _setCache(_cacheKey('/rest/api/3/issue/$issueKey', {}), null);
        try {
          final json = jsonDecode(response.body) as List<dynamic>;
          if (json.isNotEmpty && json[0] is Map) {
            final attachment = json[0] as Map<String, dynamic>;
            final id = stringFromJson(attachment['id']);
            
            // Debug: log attachment response to see available fields
            if (debugLog) {
              _log('Attachment upload response', jsonEncode(attachment));
            }
            
            final contentUrl = stringFromJson(attachment['content']);
            final mimeType = stringFromJson(attachment['mimeType']) ?? 'application/octet-stream';
            if (id != null) {
              // Jira returns numeric IDs, but ADF media nodes require UUID format
              // Generate a deterministic UUID v5 from the attachment ID
              // This creates a consistent UUID that can be used in ADF media nodes
              final mediaId = _generateUuidV5('6ba7b810-9dad-11d1-80b4-00c04fd430c8', id);
              
              if (debugLog) {
                _log('Generated UUID for attachment', 'ID: $id -> UUID: $mediaId');
              }
              
              return {
                'id': id, // Numeric ID for reference
                'mediaId': mediaId, // UUID format for ADF media nodes
                'filename': filename,
                'content': contentUrl ?? '',
                'mimeType': mimeType,
              };
            }
          }
        } catch (_) {}
        return null;
      }
      
      _log('uploadAttachmentFromBytes failed', 'statusCode=${response.statusCode} body=${response.body}');
      return null;
    } catch (e) {
      _log('uploadAttachmentFromBytes exception', e.toString());
      return null;
    }
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

  /// Fetches all board issues (paginated). Used as fallback for backlog when backlog API and JQL return empty.
  Future<List<JiraIssue>> getBoardIssuesAll(int boardId, {String? assignee}) async {
    final results = <JiraIssue>[];
    int startAt = 0;
    const maxResults = 100;
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

  /// Fetches all backlog issues (paginated). Board backlog = issues not in any sprint.
  /// Jira Agile API may return 'issues' or 'values'; we accept both.
  Future<List<JiraIssue>> getBacklogIssues(int boardId, {String? assignee}) async {
    final results = <JiraIssue>[];
    int startAt = 0;
    const maxResults = 100;
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
      final uri = Uri.parse('$_baseUrl/rest/agile/1.0/board/$boardId/backlog').replace(queryParameters: params);
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode != 200) throw JiraApiException(r.statusCode, r.body);

      final json = jsonDecode(r.body) as Map<String, dynamic>;
      // Jira Agile backlog: standard key is 'issues'; some responses use 'values' or nest under 'contents'
      List<dynamic> list = (json['issues'] as List<dynamic>?) ?? (json['values'] as List<dynamic>?) ?? [];
      if (list.isEmpty && json['contents'] is Map) {
        final contents = json['contents'] as Map<String, dynamic>;
        list = (contents['issues'] as List<dynamic>?) ?? (contents['values'] as List<dynamic>?) ?? [];
      }
      for (final e in list) {
        if (e is Map<String, dynamic>) {
          try {
            results.add(JiraIssue.fromJson(e));
          } catch (parseErr) {
            if (debugLog) debugPrint('[JiraAPI] getBacklogIssues skip issue parse: $parseErr');
          }
        }
      }
      if (list.length < maxResults) break;
      startAt += maxResults;
    }
    return results;
  }

  /// Fallback: get issues with no sprint via JQL (project = X AND sprint is EMPTY). Use when board backlog returns empty.
  Future<List<JiraIssue>> getBacklogIssuesByJql(String projectKey, {String? assignee}) async {
    final jql = StringBuffer('project = $projectKey AND sprint is EMPTY');
    if (assignee != null && assignee.isNotEmpty && assignee != 'all') {
      if (assignee == 'unassigned') {
        jql.write(' AND assignee is EMPTY');
      } else {
        jql.write(' AND assignee = "$assignee"');
      }
    }
    final results = <JiraIssue>[];
    int startAt = 0;
    const maxResults = 100;
    const fields = 'summary,status,priority,assignee,issuetype,created,updated,duedate,sprint';
    while (true) {
      final uri = Uri.parse('$_baseUrl/rest/api/3/search').replace(queryParameters: {
        'jql': jql.toString(),
        'startAt': '$startAt',
        'maxResults': '$maxResults',
        'fields': fields,
      });
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode != 200) return results;
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      final list = (json['issues'] as List<dynamic>?) ?? [];
      for (final e in list) {
        if (e is Map<String, dynamic>) {
          results.add(JiraIssue.fromJson(e));
        }
      }
      if (list.length < maxResults) break;
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

  /// Generate UUID v5 (deterministic) from namespace and name
  /// This creates a consistent UUID from the attachment ID
  static String _generateUuidV5(String namespaceUuid, String name) {
    // Parse namespace UUID (remove dashes)
    final nsBytes = namespaceUuid.replaceAll('-', '').toLowerCase();
    final ns = List<int>.generate(16, (i) => int.parse(nsBytes.substring(i * 2, i * 2 + 2), radix: 16));
    
    // Combine namespace bytes with name bytes
    final nameBytes = utf8.encode(name);
    final combined = List<int>.from(ns)..addAll(nameBytes);
    
    // SHA-1 hash
    final hash = sha1.convert(combined).bytes;
    
    // Set version (5) and variant bits
    final result = List<int>.from(hash);
    result[6] = (result[6] & 0x0f) | 0x50; // Version 5
    result[8] = (result[8] & 0x3f) | 0x80; // Variant 10
    
    // Format as UUID string
    return '${_hex(result, 0, 4)}-${_hex(result, 4, 6)}-${_hex(result, 6, 8)}-${_hex(result, 8, 10)}-${_hex(result, 10, 16)}';
  }
  
  static String _hex(List<int> bytes, int start, int end) {
    return bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
  
  /// Build ADF body from comment text. Parses mention markers and attachment markers into ADF nodes.
  /// Attachment markers like [attachment:ID:filename] are converted to mediaInline nodes.
  /// Mention markers are converted to mention nodes.
  static Map<String, dynamic> _commentBodyAdf(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return {
        'body': {
          'type': 'doc',
          'version': 1,
          'content': [
            {'type': 'paragraph', 'content': [{'type': 'text', 'text': ''}]},
          ],
        },
      };
    }
    final normalized = _removeDuplicateMentionDisplay(trimmed);
    
    // Pattern for attachment markers: [attachment:ID:filename] or [image:ID:filename]
    final attachmentPattern = RegExp(r'\[(attachment|image):([^:]+):([^\]]+)\]');
    
    // Pattern for mention markers
    final mentionPattern = RegExp(
      '${RegExp.escape(_mentionMarkerZwsp)}~$_mentionMarkerZwsp([^$_mentionMarkerSep]+)$_mentionMarkerSep([^$_mentionMarkerZwsp]*)$_mentionMarkerZwsp~$_mentionMarkerZwsp',
    );
    
    final List<Map<String, dynamic>> paragraphContent = [];
    
    // Combine and sort all matches by position
    final allMatches = <Map<String, dynamic>>[];
    for (final match in attachmentPattern.allMatches(normalized)) {
      allMatches.add({
        'start': match.start,
        'end': match.end,
        'type': 'attachment',
        'match': match,
      });
    }
    for (final match in mentionPattern.allMatches(normalized)) {
      allMatches.add({
        'start': match.start,
        'end': match.end,
        'type': 'mention',
        'match': match,
      });
    }
    allMatches.sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));
    
    int lastEnd = 0;
    for (final matchInfo in allMatches) {
      final start = matchInfo['start'] as int;
      final end = matchInfo['end'] as int;
      final type = matchInfo['type'] as String;
      
      if (start > lastEnd) {
        final segment = normalized.substring(lastEnd, start);
        if (segment.isNotEmpty) {
          paragraphContent.add({'type': 'text', 'text': segment});
        }
      }
      
      if (type == 'attachment') {
        final match = matchInfo['match'] as RegExpMatch;
        final attachmentIdStr = match.group(2) ?? '';
        final filename = match.group(3) ?? '';
        
        // Convert attachment ID to integer (Jira ADF requires numeric IDs)
        final attachmentIdNum = int.tryParse(attachmentIdStr);
        if (attachmentIdNum == null) {
          // If ID is not numeric, add as plain text to avoid breaking the comment
          debugPrint('Warning: Invalid attachment ID format (not numeric): $attachmentIdStr');
          paragraphContent.add({'type': 'text', 'text': normalized.substring(start, end)});
        } else {
          // Add mediaInline node for attachment
          // Jira ADF format: Try both string and integer ID formats
          // First try: Use integer ID (as per ADF spec)
          // If that fails, we'll try string ID or mediaSingle structure
          final attrs = <String, dynamic>{
            'id': attachmentIdNum, // Try integer first
            'type': 'file',
            'collection': 'attachment',
          };
          // Only add alt if filename is not empty
          if (filename.isNotEmpty && filename.trim().isNotEmpty) {
            attrs['alt'] = filename.trim();
          }
          paragraphContent.add({
            'type': 'mediaInline',
            'attrs': attrs,
          });
        }
      } else if (type == 'mention') {
        final match = matchInfo['match'] as RegExpMatch;
        final accountId = match.group(1) ?? '';
        final displayName = match.group(2) ?? '';
        paragraphContent.add({
          'type': 'mention',
          'attrs': {'id': accountId, 'text': displayName.isEmpty ? '@$accountId' : '@$displayName'},
        });
      }
      
      lastEnd = end;
    }
    
    if (lastEnd < normalized.length) {
      final segment = normalized.substring(lastEnd);
      if (segment.isNotEmpty) {
        paragraphContent.add({'type': 'text', 'text': segment});
      }
    }
    
    // Ensure we have valid content
    // If paragraphContent is empty but we have normalized text, add it
    if (paragraphContent.isEmpty) {
      final trimmedNormalized = normalized.trim();
      if (trimmedNormalized.isEmpty) {
        // Empty comment - add empty paragraph
        paragraphContent.add({'type': 'text', 'text': ''});
      } else {
        // Add normalized text
        paragraphContent.add({'type': 'text', 'text': normalized});
      }
    }
    
    // Jira comments with attachments: Use media nodes directly in document content
    // Structure: paragraph with text, then media node with UUID ID and empty collection
    final hasMediaInline = paragraphContent.any((item) => item['type'] == 'mediaInline');
    
    List<Map<String, dynamic>> docContent;
      if (hasMediaInline) {
        // Separate text content and media nodes
        final textContent = <Map<String, dynamic>>[];
        final mediaNodes = <Map<String, dynamic>>[];
        
        for (final item in paragraphContent) {
          if (item['type'] == 'mediaInline') {
            final attrs = item['attrs'] as Map<String, dynamic>;
            // The ID stored in attrs should be the UUID from uploadAttachment response
            // We store it as 'mediaId' in the attachment marker: [attachment:UUID:filename]
            final mediaId = attrs['id']?.toString() ?? '';
            
            // Create media node with UUID string ID and empty collection
            // The mediaId should be a UUID format from Jira's attachment upload response
            mediaNodes.add({
              'type': 'media',
              'attrs': {
                'type': 'file',
                'id': mediaId, // UUID format expected by Jira ADF
                'collection': '', // Empty collection as per the example
              },
            });
          } else {
            textContent.add(item);
          }
        }
      
      // Build document content: paragraph with text, then media nodes
      docContent = [];
      if (textContent.isNotEmpty) {
        docContent.add({'type': 'paragraph', 'content': textContent});
      }
      // Add media nodes directly to document content (not inside paragraph)
      docContent.addAll(mediaNodes);
      
      // Ensure we have at least one paragraph
      if (docContent.isEmpty) {
        docContent.add({'type': 'paragraph', 'content': [{'type': 'text', 'text': ''}]});
      }
    } else {
      // No mediaInline nodes, use standard paragraph structure
      docContent = [
        {'type': 'paragraph', 'content': paragraphContent},
      ];
    }
    
    // Build ADF document
    final adfBody = {
      'type': 'doc',
      'version': 1,
      'content': docContent,
    };
    
    // Debug: log ADF structure for troubleshooting validation errors
    if (debugLog) {
      _log('Comment ADF structure', jsonEncode(adfBody));
    }
    
    return {
      'body': adfBody,
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
    
    // Debug: log payload for troubleshooting
    if (debugLog) {
      _log('Adding comment', 'Issue: $issueKey, Payload: ${jsonEncode(payload)}');
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
    
    // Log detailed error for debugging validation issues
    _log('addComment failed', 'statusCode=${r.statusCode}');
    _log('Error response body', r.body);
    if (debugLog) {
      _log('Request payload was', jsonEncode(payload));
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
  /// Returns the created issue key on success, or an error message string on failure.
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
        return issueKey; // Return issue key on success
      }

      // Parse error message
      try {
        final errorJson = jsonDecode(r.body) as Map<String, dynamic>;
        final errorMessages = errorJson['errorMessages'] as List<dynamic>?;
        if (errorMessages != null && errorMessages.isNotEmpty) {
          return 'ERROR: ${errorMessages.join(', ')}';
        }
        final errors = errorJson['errors'] as Map<String, dynamic>?;
        if (errors != null && errors.isNotEmpty) {
          return 'ERROR: ${errors.values.join(', ')}';
        }
      } catch (_) {}
      
      return 'ERROR: Failed to create issue: ${r.statusCode}';
    } catch (e) {
      return 'ERROR: ${e.toString()}';
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
