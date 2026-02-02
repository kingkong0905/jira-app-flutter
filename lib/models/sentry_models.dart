/// Parsed Sentry URL components for API calls.
class SentryUrlParts {
  SentryUrlParts({
    required this.baseUrl,
    required this.organizationSlug,
    required this.issueId,
  });

  final String baseUrl;
  final String organizationSlug;
  final String issueId;
}

/// Issue summary from Sentry API GET /api/0/organizations/{org}/issues/{id}/
class SentryIssue {
  SentryIssue({
    required this.id,
    required this.shortId,
    required this.title,
    this.culprit,
    this.level,
    this.status,
    this.firstSeen,
    this.lastSeen,
    this.permalink,
    this.metadata,
    this.project,
    this.tags = const [],
    this.userCount = 0,
    this.count,
  });

  final String id;
  final String shortId;
  final String title;
  final String? culprit;
  final String? level;
  final String? status;
  final String? firstSeen;
  final String? lastSeen;
  final String? permalink;
  final SentryIssueMetadata? metadata;
  final SentryProjectRef? project;
  final List<SentryTag> tags;
  final int userCount;
  final String? count;

  factory SentryIssue.fromJson(Map<String, dynamic> json) {
    final meta = json['metadata'];
    final proj = json['project'];
    final tagList = json['tags'] as List<dynamic>?;
    return SentryIssue(
      id: json['id']?.toString() ?? '',
      shortId: json['shortId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      culprit: json['culprit']?.toString(),
      level: json['level']?.toString(),
      status: json['status']?.toString(),
      firstSeen: json['firstSeen']?.toString(),
      lastSeen: json['lastSeen']?.toString(),
      permalink: json['permalink']?.toString(),
      metadata: meta != null && meta is Map ? SentryIssueMetadata.fromJson(Map<String, dynamic>.from(meta)) : null,
      project: proj != null && proj is Map ? SentryProjectRef.fromJson(Map<String, dynamic>.from(proj)) : null,
      tags: tagList != null
          ? tagList.map((e) => SentryTag.fromJson(Map<String, dynamic>.from(e as Map))).toList()
          : [],
      userCount: (json['userCount'] is int) ? json['userCount'] as int : 0,
      count: json['count']?.toString(),
    );
  }
}

class SentryIssueMetadata {
  SentryIssueMetadata({this.type, this.value, this.title});

  final String? type;
  final String? value;
  final String? title;

  factory SentryIssueMetadata.fromJson(Map<String, dynamic> json) {
    return SentryIssueMetadata(
      type: json['type']?.toString(),
      value: json['value']?.toString(),
      title: json['title']?.toString(),
    );
  }
}

class SentryProjectRef {
  SentryProjectRef({required this.id, required this.slug, this.name});

  final String id;
  final String slug;
  final String? name;

  factory SentryProjectRef.fromJson(Map<String, dynamic> json) {
    return SentryProjectRef(
      id: json['id']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      name: json['name']?.toString(),
    );
  }
}

class SentryTag {
  SentryTag({required this.key, required this.value});

  final String key;
  final String value;

  factory SentryTag.fromJson(Map<String, dynamic> json) {
    return SentryTag(
      key: json['key']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
    );
  }
}

/// Event detail from GET .../issues/{id}/events/latest/ (stack trace, breadcrumbs, etc.)
class SentryEvent {
  SentryEvent({
    required this.eventID,
    required this.title,
    this.message,
    this.culprit,
    this.dateCreated,
    this.platform,
    this.tags = const [],
    this.entries = const [],
    this.contexts,
    this.user,
    this.extra,
  });

  final String eventID;
  final String title;
  final String? message;
  final String? culprit;
  final String? dateCreated;
  final String? platform;
  final List<SentryTag> tags;
  final List<SentryEventEntry> entries;
  final Map<String, dynamic>? contexts;
  final SentryUserContext? user;
  /// Additional key-value data (shown in "Additional Data" section).
  final Map<String, dynamic>? extra;

  factory SentryEvent.fromJson(Map<String, dynamic> json) {
    final tagList = json['tags'] as List<dynamic>?;
    final entryList = json['entries'] as List<dynamic>?;
    final userJson = json['user'];
    // extra = custom key-value data sent to Sentry when capturing the issue (Sentry API field "extra")
    final extra = json['extra'] is Map
        ? Map<String, dynamic>.from(json['extra'] as Map)
        : null;

    return SentryEvent(
      eventID: json['eventID']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString(),
      culprit: json['culprit']?.toString(),
      dateCreated: json['dateCreated']?.toString(),
      platform: json['platform']?.toString(),
      tags: tagList != null
          ? tagList.map((e) => SentryTag.fromJson(Map<String, dynamic>.from(e as Map))).toList()
          : [],
      entries: entryList != null
          ? entryList.map((e) => SentryEventEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList()
          : [],
      contexts: json['contexts'] is Map ? Map<String, dynamic>.from(json['contexts'] as Map) : null,
      user: userJson != null && userJson is Map
          ? SentryUserContext.fromJson(Map<String, dynamic>.from(userJson))
          : null,
      extra: extra,
    );
  }
}

class SentryEventEntry {
  SentryEventEntry({required this.type, this.data});

  final String type;
  final Map<String, dynamic>? data;

  factory SentryEventEntry.fromJson(Map<String, dynamic> json) {
    return SentryEventEntry(
      type: json['type']?.toString() ?? '',
      data: json['data'] is Map ? Map<String, dynamic>.from(json['data'] as Map) : null,
    );
  }
}

/// Exception entry data (stack trace).
class SentryExceptionEntry {
  SentryExceptionEntry({this.values = const []});

  final List<SentryExceptionValue> values;

  factory SentryExceptionEntry.fromJson(Map<String, dynamic> json) {
    final list = json['values'] as List<dynamic>?;
    return SentryExceptionEntry(
      values: list != null
          ? list.map((e) => SentryExceptionValue.fromJson(Map<String, dynamic>.from(e as Map))).toList()
          : [],
    );
  }
}

class SentryExceptionValue {
  SentryExceptionValue({
    required this.type,
    required this.value,
    this.stacktrace,
    this.mechanism,
  });

  final String type;
  final String value;
  final SentryStacktrace? stacktrace;
  final Map<String, dynamic>? mechanism;

  factory SentryExceptionValue.fromJson(Map<String, dynamic> json) {
    final st = json['stacktrace'];
    return SentryExceptionValue(
      type: json['type']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      stacktrace: st != null && st is Map
          ? SentryStacktrace.fromJson(Map<String, dynamic>.from(st))
          : null,
      mechanism: json['mechanism'] is Map ? Map<String, dynamic>.from(json['mechanism'] as Map) : null,
    );
  }
}

class SentryStacktrace {
  SentryStacktrace({this.frames = const [], this.framesOmitted, this.hasSystemFrames});

  final List<SentryFrame> frames;
  final bool? framesOmitted;
  final bool? hasSystemFrames;

  factory SentryStacktrace.fromJson(Map<String, dynamic> json) {
    final list = json['frames'] as List<dynamic>?;
    return SentryStacktrace(
      frames: list != null
          ? list.map((e) => SentryFrame.fromJson(Map<String, dynamic>.from(e as Map))).toList()
          : [],
      framesOmitted: json['framesOmitted'] as bool?,
      hasSystemFrames: json['hasSystemFrames'] as bool?,
    );
  }
}

class SentryFrame {
  SentryFrame({
    this.filename,
    this.function,
    this.module,
    this.lineNo,
    this.colNo,
    this.absPath,
    this.inApp = false,
    this.context,
    this.vars,
  });

  final String? filename;
  final String? function;
  final String? module;
  final int? lineNo;
  final int? colNo;
  final String? absPath;
  final bool inApp;
  final List<List<dynamic>>? context;
  final Map<String, dynamic>? vars;

  factory SentryFrame.fromJson(Map<String, dynamic> json) {
    final ctx = json['context'] as List<dynamic>?;
    return SentryFrame(
      filename: json['filename']?.toString(),
      function: json['function']?.toString(),
      module: json['module']?.toString(),
      lineNo: json['lineNo'] is int ? json['lineNo'] as int : (json['lineNo'] is num ? (json['lineNo'] as num).toInt() : null),
      colNo: json['colNo'] is int ? json['colNo'] as int : (json['colNo'] is num ? (json['colNo'] as num).toInt() : null),
      absPath: json['absPath']?.toString(),
      inApp: json['inApp'] == true,
      context: ctx?.map((e) => e is List ? List<dynamic>.from(e) : <dynamic>[e]).toList(),
      vars: json['vars'] is Map ? Map<String, dynamic>.from(json['vars'] as Map) : null,
    );
  }
}

/// Breadcrumb entry.
class SentryBreadcrumb {
  SentryBreadcrumb({
    required this.type,
    required this.category,
    this.message,
    this.level,
    this.timestamp,
    this.data,
  });

  final String type;
  final String category;
  final String? message;
  final String? level;
  final String? timestamp;
  final Map<String, dynamic>? data;

  factory SentryBreadcrumb.fromJson(Map<String, dynamic> json) {
    return SentryBreadcrumb(
      type: json['type']?.toString() ?? 'default',
      category: json['category']?.toString() ?? '',
      message: json['message']?.toString(),
      level: json['level']?.toString(),
      timestamp: json['timestamp']?.toString(),
      data: json['data'] is Map ? Map<String, dynamic>.from(json['data'] as Map) : null,
    );
  }
}

/// Combined issue + latest event for the detail screen.
class SentryIssueDetail {
  SentryIssueDetail({required this.issue, this.event});

  final SentryIssue issue;
  final SentryEvent? event;
}

class SentryUserContext {
  SentryUserContext({this.id, this.email, this.username, this.name, this.ipAddress});

  final String? id;
  final String? email;
  final String? username;
  final String? name;
  final String? ipAddress;

  factory SentryUserContext.fromJson(Map<String, dynamic> json) {
    return SentryUserContext(
      id: json['id']?.toString(),
      email: json['email']?.toString(),
      username: json['username']?.toString(),
      name: json['name']?.toString(),
      ipAddress: json['ip_address']?.toString(),
    );
  }
}
