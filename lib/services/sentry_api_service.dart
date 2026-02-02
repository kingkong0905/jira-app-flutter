import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/sentry_models.dart';

/// Parses Sentry issue URLs and calls Sentry REST API for issue and event details.
/// See: https://docs.sentry.io/api/events/retrieve-an-issue/
///      https://docs.sentry.io/api/events/retrieve-an-issue-event/
class SentryApiService {
  /// Parse a Sentry issue URL to get base URL, org slug, and issue ID.
  /// Example: https://employment-hero.sentry.io/issues/7068255778/?project=5286560
  ///   -> baseUrl: https://employment-hero.sentry.io, orgSlug: employment-hero, issueId: 7068255778
  static SentryUrlParts? parseIssueUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    Uri? uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return null;
    }
    if (uri.host.isEmpty) return null;
    // Must contain sentry.io (or similar) and /issues/
    if (!uri.host.contains('sentry') || !uri.path.contains('/issues/')) return null;

    // Organization slug: for *.sentry.io it's the subdomain (e.g. employment-hero)
    String orgSlug = uri.host;
    if (orgSlug.endsWith('.sentry.io')) {
      orgSlug = orgSlug.replaceFirst(RegExp(r'\.sentry\.io$'), '');
    } else if (uri.host == 'sentry.io') {
      // Standard sentry.io URL: https://sentry.io/organizations/ORG/issues/ID/
      final match = RegExp(r'/organizations/([^/]+)/issues/(\d+)').firstMatch(uri.path);
      if (match != null) {
        final baseUrl = '${uri.scheme}://${uri.host}';
        return SentryUrlParts(
          baseUrl: baseUrl,
          organizationSlug: match.group(1)!,
          issueId: match.group(2)!,
        );
      }
      return null;
    }

    // Path like /issues/7068255778/ or /issues/7068255778
    final match = RegExp(r'/issues/(\d+)').firstMatch(uri.path);
    if (match == null) return null;
    final issueId = match.group(1)!;
    final baseUrl = '${uri.scheme}://${uri.host}';
    return SentryUrlParts(baseUrl: baseUrl, organizationSlug: orgSlug, issueId: issueId);
  }

  /// Fetch issue details from Sentry API.
  /// Requires [authToken] (create at sentry.io/settings/account/api/auth-tokens/) with scope event:read.
  Future<SentryIssue> getIssue({
    required SentryUrlParts parts,
    required String? authToken,
  }) async {
    if (authToken == null || authToken.isEmpty) {
      throw SentryApiException('Sentry API token is required. Add it in Settings.');
    }
    final url = '${parts.baseUrl}/api/0/organizations/${Uri.encodeComponent(parts.organizationSlug)}/issues/${parts.issueId}/';
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode != 200) {
      throw SentryApiException(_errorMessage(response));
    }
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    return SentryIssue.fromJson(map);
  }

  /// Fetch latest event for an issue (stack trace, breadcrumbs, tags).
  Future<SentryEvent?> getLatestEvent({
    required SentryUrlParts parts,
    required String? authToken,
  }) async {
    if (authToken == null || authToken.isEmpty) return null;
    final url = '${parts.baseUrl}/api/0/organizations/${Uri.encodeComponent(parts.organizationSlug)}/issues/${parts.issueId}/events/latest/';
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode != 200) return null;
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    return SentryEvent.fromJson(map);
  }

  /// Fetch both issue and latest event in one go.
  Future<SentryIssueDetail> getIssueDetail({
    required SentryUrlParts parts,
    required String? authToken,
  }) async {
    final issue = await getIssue(parts: parts, authToken: authToken);
    final event = await getLatestEvent(parts: parts, authToken: authToken);
    return SentryIssueDetail(issue: issue, event: event);
  }

  static String _errorMessage(http.Response response) {
    if (response.statusCode == 401) {
      return 'Unauthorized. Check your Sentry API token (Settings).';
    }
    if (response.statusCode == 403) {
      return 'Access denied to this Sentry issue.';
    }
    if (response.statusCode == 404) {
      return 'Sentry issue not found.';
    }
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] != null) {
        return body['detail'].toString();
      }
    } catch (_) {}
    return 'Sentry API error: ${response.statusCode}';
  }
}

class SentryApiException implements Exception {
  SentryApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
