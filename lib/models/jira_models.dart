/// Jira domain models matching the reference React Native app (kingkong0905/jira-app).

/// Safely coerce API value to String? (Jira sometimes returns Map/ADF instead of string).
String? stringFromJson(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is Map) {
    final p = v['plain'] ?? v['value'] ?? v['name'] ?? v['displayName'] ?? v['text'];
    return stringFromJson(p);
  }
  return v.toString();
}

/// Safely coerce API value to int? (JSON numbers are often decoded as double).
int? intFromJson(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

class JiraConfig {
  final String email;
  final String jiraUrl;
  final String apiToken;

  JiraConfig({
    required this.email,
    required this.jiraUrl,
    required this.apiToken,
  });
}

class JiraBoard {
  final int id;
  final String name;
  final String type;
  final JiraBoardLocation? location;

  JiraBoard({
    required this.id,
    required this.name,
    required this.type,
    this.location,
  });

  factory JiraBoard.fromJson(Map<String, dynamic> json) {
    return JiraBoard(
      id: intFromJson(json['id']) ?? 0,
      name: stringFromJson(json['name']) ?? '',
      type: stringFromJson(json['type']) ?? 'scrum',
      location: json['location'] != null
          ? JiraBoardLocation.fromJson(json['location'] as Map<String, dynamic>)
          : null,
    );
  }
}

class JiraBoardLocation {
  final String? projectKey;
  final String? projectName;

  JiraBoardLocation({this.projectKey, this.projectName});

  factory JiraBoardLocation.fromJson(Map<String, dynamic> json) {
    return JiraBoardLocation(
      projectKey: stringFromJson(json['projectKey']),
      projectName: stringFromJson(json['projectName']),
    );
  }
}

class JiraIssue {
  final String id;
  final String key;
  final JiraIssueFields fields;

  JiraIssue({
    required this.id,
    required this.key,
    required this.fields,
  });

  factory JiraIssue.fromJson(Map<String, dynamic> json) {
    return JiraIssue(
      id: stringFromJson(json['id']) ?? '',
      key: stringFromJson(json['key']) ?? '',
      fields: JiraIssueFields.fromJson(
        json['fields'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

/// Attachment on an issue (Jira REST API v3).
class JiraAttachment {
  final String id;
  final String filename;
  final String mimeType;
  final String content; // URL to download (requires auth)
  final int? size;
  final String? thumbnail;

  JiraAttachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.content,
    this.size,
    this.thumbnail,
  });

  factory JiraAttachment.fromJson(Map<String, dynamic> json) {
    return JiraAttachment(
      id: stringFromJson(json['id']) ?? '',
      filename: stringFromJson(json['filename']) ?? '',
      mimeType: stringFromJson(json['mimeType']) ?? 'application/octet-stream',
      content: stringFromJson(json['content']) ?? '',
      size: intFromJson(json['size']),
      thumbnail: stringFromJson(json['thumbnail']),
    );
  }

  static List<JiraAttachment> fromJsonList(dynamic v) {
    if (v == null) return [];
    if (v is! List) return [];
    return v
        .whereType<Map<String, dynamic>>()
        .map((e) => JiraAttachment.fromJson(e))
        .toList();
  }
}

class JiraIssueFields {
  final String summary;
  /// Description: String (plain) or Map (ADF). Stored raw for display/edit.
  final dynamic description;
  final JiraStatus status;
  final JiraPriority? priority;
  final JiraUser? assignee;
  final JiraUser? reporter;
  final JiraIssueType issuetype;
  final String created;
  final String updated;
  final String? duedate;
  final int? customfield_10016; // Story points
  final dynamic sprint; // Can be JiraSprintRef, List<JiraSprintRef>, or null
  final JiraIssueParent? parent;
  /// Project key (e.g. PROJ) for loading boards/sprints when updating sprint on issue detail.
  final String? projectKey;
  /// Nullable for backward compatibility with cached/older parsed issues that may lack this field.
  final List<JiraAttachment>? attachment;
  /// Child issues (subtasks) when returned by GET issue with fields=subtasks.
  final List<JiraIssue>? subtasks;
  /// Linked work items (issue links) when returned by GET issue with fields=issuelinks.
  final List<JiraIssueLink>? issuelinks;

  JiraIssueFields({
    required this.summary,
    this.description,
    required this.status,
    this.priority,
    this.assignee,
    this.reporter,
    required this.issuetype,
    required this.created,
    required this.updated,
    this.duedate,
    this.customfield_10016,
    this.sprint,
    this.parent,
    this.projectKey,
    this.attachment = const [],
    this.subtasks,
    this.issuelinks,
  });

  factory JiraIssueFields.fromJson(Map<String, dynamic> json) {
    return JiraIssueFields(
      summary: stringFromJson(json['summary']) ?? '',
      description: json['description'],
      status: json['status'] != null
          ? JiraStatus.fromJson(json['status'] as Map<String, dynamic>)
          : JiraStatus(name: 'Unknown', statusCategory: JiraStatusCategory(colorName: 'gray', key: 'unknown')),
      priority: json['priority'] != null
          ? JiraPriority.fromJson(json['priority'] as Map<String, dynamic>)
          : null,
      assignee: json['assignee'] != null
          ? JiraUser.fromJson(json['assignee'] as Map<String, dynamic>)
          : null,
      reporter: json['reporter'] != null
          ? JiraUser.fromJson(json['reporter'] as Map<String, dynamic>)
          : null,
      issuetype: json['issuetype'] != null
          ? JiraIssueType.fromJson(json['issuetype'] as Map<String, dynamic>)
          : JiraIssueType(name: 'Task', iconUrl: ''),
      created: stringFromJson(json['created']) ?? '',
      updated: stringFromJson(json['updated']) ?? '',
      duedate: stringFromJson(json['duedate']),
      customfield_10016: intFromJson(json['customfield_10016']),
      sprint: json['sprint'] ?? json['customfield_10020'], // Store raw sprint data (can be object or list)
      parent: json['parent'] != null
          ? JiraIssueParent.fromJson(json['parent'] as Map<String, dynamic>)
          : null,
      projectKey: json['project'] != null && json['project'] is Map
          ? stringFromJson((json['project'] as Map)['key'])
          : null,
      attachment: JiraAttachment.fromJsonList(json['attachment']),
      subtasks: _parseSubtasks(json['subtasks']),
      issuelinks: JiraIssueLink.fromJsonList(json['issuelinks'] ?? json['issueLinks']),
    );
  }

  static List<JiraIssue>? _parseSubtasks(dynamic v) {
    if (v == null) return null;
    if (v is! List) return null;
    final list = <JiraIssue>[];
    for (final e in v) {
      if (e is Map<String, dynamic>) {
        try {
          list.add(JiraIssue.fromJson(e));
        } catch (_) {
          // Skip malformed subtask
        }
      }
    }
    return list.isEmpty ? null : list;
  }

  static JiraSprintRef? _parseSprint(dynamic v) {
    if (v == null) return null;
    
    // Handle single sprint object
    if (v is Map<String, dynamic>) {
      try {
        return JiraSprintRef.fromJson(v);
      } catch (e) {
        // If parsing fails, try to extract basic fields
        final id = intFromJson(v['id']);
        final name = stringFromJson(v['name']);
        if (id != null && name != null) {
          return JiraSprintRef(
            id: id,
            name: name,
            state: stringFromJson(v['state']) ?? 'unknown',
          );
        }
      }
    }
    
    // Handle list of sprints (take the last/most recent one)
    if (v is List && v.isNotEmpty) {
      final last = v.last;
      if (last is Map<String, dynamic>) {
        try {
          return JiraSprintRef.fromJson(last);
        } catch (e) {
          // Fallback parsing
          final id = intFromJson(last['id']);
          final name = stringFromJson(last['name']);
          if (id != null && name != null) {
            return JiraSprintRef(
              id: id,
              name: name,
              state: stringFromJson(last['state']) ?? 'unknown',
            );
          }
        }
      }
    }
    
    return null;
  }
}

class JiraStatus {
  final String name;
  final JiraStatusCategory statusCategory;

  JiraStatus({required this.name, required this.statusCategory});

  factory JiraStatus.fromJson(Map<String, dynamic> json) {
    return JiraStatus(
      name: stringFromJson(json['name']) ?? '',
      statusCategory: json['statusCategory'] != null
          ? JiraStatusCategory.fromJson(json['statusCategory'] as Map<String, dynamic>)
          : JiraStatusCategory(colorName: 'gray', key: 'unknown'),
    );
  }
}

class JiraStatusCategory {
  final String colorName;
  final String? key;

  JiraStatusCategory({required this.colorName, this.key});

  factory JiraStatusCategory.fromJson(Map<String, dynamic> json) {
    return JiraStatusCategory(
      colorName: stringFromJson(json['colorName']) ?? 'gray',
      key: stringFromJson(json['key']),
    );
  }
}

class JiraPriority {
  final String name;
  final String? iconUrl;

  JiraPriority({required this.name, this.iconUrl});

  factory JiraPriority.fromJson(Map<String, dynamic> json) {
    return JiraPriority(
      name: stringFromJson(json['name']) ?? 'Medium',
      iconUrl: stringFromJson(json['iconUrl']),
    );
  }
}

class JiraUser {
  final String accountId;
  final String displayName;
  final String? emailAddress;
  final Map<String, String>? avatarUrls;

  JiraUser({
    required this.accountId,
    required this.displayName,
    this.emailAddress,
    this.avatarUrls,
  });

  String? get avatar48 => avatarUrls?['48x48'];

  factory JiraUser.fromJson(Map<String, dynamic> json) {
    final av = json['avatarUrls'];
    Map<String, String>? urls;
    if (av is Map) {
      urls = av.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    // Jira Cloud uses displayName; Jira Server may use name
    final displayName = stringFromJson(json['displayName']) ??
        stringFromJson(json['name']) ??
        '';
    return JiraUser(
      accountId: stringFromJson(json['accountId']) ?? '',
      displayName: displayName,
      emailAddress: stringFromJson(json['emailAddress']),
      avatarUrls: urls,
    );
  }
}

class JiraIssueType {
  final String name;
  final String? iconUrl;

  JiraIssueType({required this.name, this.iconUrl});

  factory JiraIssueType.fromJson(Map<String, dynamic> json) {
    return JiraIssueType(
      name: stringFromJson(json['name']) ?? 'Task',
      iconUrl: stringFromJson(json['iconUrl']),
    );
  }
}

class JiraSprintRef {
  final int id;
  final String name;
  final String state;

  JiraSprintRef({required this.id, required this.name, required this.state});

  factory JiraSprintRef.fromJson(Map<String, dynamic> json) {
    return JiraSprintRef(
      id: intFromJson(json['id']) ?? 0,
      name: stringFromJson(json['name']) ?? '',
      state: stringFromJson(json['state']) ?? 'unknown',
    );
  }
}

class JiraIssueParent {
  final String id;
  final String key;
  final String? summary;

  JiraIssueParent({required this.id, required this.key, this.summary});

  factory JiraIssueParent.fromJson(Map<String, dynamic> json) {
    final fields = json['fields'] as Map<String, dynamic>?;
    return JiraIssueParent(
      id: stringFromJson(json['id']) ?? '',
      key: stringFromJson(json['key']) ?? '',
      summary: fields != null ? stringFromJson(fields['summary']) : null,
    );
  }
}

class JiraSprint {
  final int id;
  final String name;
  final String state;
  final String? startDate;
  final String? endDate;
  final String? goal;

  JiraSprint({
    required this.id,
    required this.name,
    required this.state,
    this.startDate,
    this.endDate,
    this.goal,
  });

  factory JiraSprint.fromJson(Map<String, dynamic> json) {
    return JiraSprint(
      id: intFromJson(json['id']) ?? 0,
      name: stringFromJson(json['name']) ?? '',
      state: stringFromJson(json['state']) ?? 'unknown',
      startDate: stringFromJson(json['startDate']),
      endDate: stringFromJson(json['endDate']),
      goal: stringFromJson(json['goal']),
    );
  }
}

class BoardAssignee {
  final String key;
  final String name;

  BoardAssignee({required this.key, required this.name});
}

/// Issue link (linked work item) from Jira API. GET issue with fields=issuelinks.
class JiraIssueLink {
  final String linkTypeName;
  /// Direction label from type (e.g. "is blocked by", "blocks").
  final String directionLabel;
  final JiraIssue linkedIssue;

  JiraIssueLink({
    required this.linkTypeName,
    required this.directionLabel,
    required this.linkedIssue,
  });

  factory JiraIssueLink.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as Map<String, dynamic>?;
    final typeName = type != null ? (stringFromJson(type['name']) ?? '') : '';
    final inward = type != null ? (stringFromJson(type['inward']) ?? '') : '';
    final outward = type != null ? (stringFromJson(type['outward']) ?? '') : '';
    JiraIssue issue;
    String directionLabel;
    if (json['inwardIssue'] != null) {
      issue = JiraIssue.fromJson(json['inwardIssue'] as Map<String, dynamic>);
      directionLabel = inward;
    } else if (json['outwardIssue'] != null) {
      issue = JiraIssue.fromJson(json['outwardIssue'] as Map<String, dynamic>);
      directionLabel = outward;
    } else {
      throw ArgumentError('Issue link must have inwardIssue or outwardIssue');
    }
    return JiraIssueLink(linkTypeName: typeName, directionLabel: directionLabel, linkedIssue: issue);
  }

  static List<JiraIssueLink>? fromJsonList(dynamic v) {
    if (v == null) return null;
    if (v is! List) return null;
    final list = <JiraIssueLink>[];
    for (final e in v) {
      if (e is Map<String, dynamic>) {
        try {
          list.add(JiraIssueLink.fromJson(e));
        } catch (_) {}
      }
    }
    return list.isEmpty ? null : list;
  }
}

/// Remote issue link from Jira API (e.g. Confluence page link). GET/POST /rest/api/3/issue/{key}/remotelink.
class JiraRemoteLink {
  final int id;
  final String? globalId;
  final String? applicationType;
  final String? applicationName;
  final String title;
  final String url;
  final String? relationship;

  JiraRemoteLink({
    required this.id,
    this.globalId,
    this.applicationType,
    this.applicationName,
    required this.title,
    required this.url,
    this.relationship,
  });

  factory JiraRemoteLink.fromJson(Map<String, dynamic> json) {
    final obj = json['object'] as Map<String, dynamic>?;
    final app = json['application'] as Map<String, dynamic>?;
    return JiraRemoteLink(
      id: intFromJson(json['id']) ?? 0,
      globalId: stringFromJson(json['globalId']),
      applicationType: app != null ? stringFromJson(app['type']) : null,
      applicationName: app != null ? stringFromJson(app['name']) : null,
      title: obj != null ? (stringFromJson(obj['title']) ?? '') : '',
      url: obj != null ? (stringFromJson(obj['url']) ?? '') : '',
      relationship: stringFromJson(json['relationship']),
    );
  }

  /// True if this link is a Confluence wiki page (shown in Confluence section).
  bool get isConfluence =>
      applicationType != null &&
      (applicationType!.toLowerCase().contains('confluence') ||
          relationship == 'Wiki Page');
}
