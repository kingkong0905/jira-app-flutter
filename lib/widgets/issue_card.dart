import 'package:flutter/material.dart';
import '../models/jira_models.dart';

/// Issue card with key, status, summary, assignee (same info as reference app).
class IssueCard extends StatelessWidget {
  final JiraIssue issue;
  final VoidCallback onTap;

  const IssueCard({super.key, required this.issue, required this.onTap});

  static Color _statusColor(String? categoryKey) {
    switch (categoryKey?.toLowerCase()) {
      case 'done':
        return const Color(0xFF00875A);
      case 'indeterminate':
        return const Color(0xFF0052CC);
      case 'new':
      case 'todo':
        return const Color(0xFF6554C0);
      default:
        return const Color(0xFF999999);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusCat = issue.fields.status.statusCategory.key;
    final statusColor = _statusColor(statusCat);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    issue.key,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0052CC),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.3),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      issue.fields.status.name,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                issue.fields.summary,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF333333),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F5F7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      issue.fields.issuetype.name,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5E6C84),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (issue.fields.assignee != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: const Color(0xFF0052CC),
                          backgroundImage: issue.fields.assignee!.avatar48 != null
                              ? NetworkImage(issue.fields.assignee!.avatar48!)
                              : null,
                          child: issue.fields.assignee!.avatar48 == null
                              ? Text(
                                  issue.fields.assignee!.displayName.isNotEmpty
                                      ? issue.fields.assignee!.displayName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                                )
                              : null,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          issue.fields.assignee!.displayName,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                        ),
                      ],
                    )
                  else
                    const Text('Unassigned', style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
