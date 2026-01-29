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
  final JiraSprintRef? sprint;
  final JiraIssueParent? parent;
  /// Nullable for backward compatibility with cached/older parsed issues that may lack this field.
  final List<JiraAttachment>? attachment;

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
    this.attachment = const [],
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
      sprint: _parseSprint(json['sprint']),
      parent: json['parent'] != null
          ? JiraIssueParent.fromJson(json['parent'] as Map<String, dynamic>)
          : null,
      attachment: JiraAttachment.fromJsonList(json['attachment']),
    );
  }

  static JiraSprintRef? _parseSprint(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) return JiraSprintRef.fromJson(v);
    if (v is List && v.isNotEmpty && v.first is Map<String, dynamic>) {
      return JiraSprintRef.fromJson(v.first as Map<String, dynamic>);
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
    return JiraUser(
      accountId: stringFromJson(json['accountId']) ?? '',
      displayName: stringFromJson(json['displayName']) ?? '',
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
