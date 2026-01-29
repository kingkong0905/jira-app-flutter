/// Jira domain models matching the reference React Native app (kingkong0905/jira-app).

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
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'scrum',
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
      projectKey: json['projectKey'] as String?,
      projectName: json['projectName'] as String?,
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
      id: json['id'] as String? ?? '',
      key: json['key'] as String? ?? '',
      fields: JiraIssueFields.fromJson(
        json['fields'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

class JiraIssueFields {
  final String summary;
  final String? description;
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
  });

  factory JiraIssueFields.fromJson(Map<String, dynamic> json) {
    return JiraIssueFields(
      summary: json['summary'] as String? ?? '',
      description: json['description'] as String?,
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
      created: json['created'] as String? ?? '',
      updated: json['updated'] as String? ?? '',
      duedate: json['duedate'] as String?,
      customfield_10016: json['customfield_10016'] as int?,
      sprint: _parseSprint(json['sprint']),
      parent: json['parent'] != null
          ? JiraIssueParent.fromJson(json['parent'] as Map<String, dynamic>)
          : null,
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
      name: json['name'] as String? ?? '',
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
      colorName: json['colorName'] as String? ?? 'gray',
      key: json['key'] as String?,
    );
  }
}

class JiraPriority {
  final String name;
  final String? iconUrl;

  JiraPriority({required this.name, this.iconUrl});

  factory JiraPriority.fromJson(Map<String, dynamic> json) {
    return JiraPriority(
      name: json['name'] as String? ?? 'Medium',
      iconUrl: json['iconUrl'] as String?,
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
      accountId: json['accountId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      emailAddress: json['emailAddress'] as String?,
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
      name: json['name'] as String? ?? 'Task',
      iconUrl: json['iconUrl'] as String?,
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
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      state: json['state'] as String? ?? 'unknown',
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
      id: json['id'] as String? ?? '',
      key: json['key'] as String? ?? '',
      summary: fields?['summary'] as String?,
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
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      state: json['state'] as String? ?? 'unknown',
      startDate: json['startDate'] as String?,
      endDate: json['endDate'] as String?,
      goal: json['goal'] as String?,
    );
  }
}

class BoardAssignee {
  final String key;
  final String name;

  BoardAssignee({required this.key, required this.name});
}
