import 'package:flutter/material.dart';
import '../models/jira_models.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

/// Issue card with key, status, summary, assignee (same info as reference app).
class IssueCard extends StatelessWidget {
  final JiraIssue issue;
  final VoidCallback onTap;

  const IssueCard({super.key, required this.issue, required this.onTap});

  static Color _statusColor(String? categoryKey) {
    switch (categoryKey?.toLowerCase()) {
      case 'done':
        return AppTheme.statusDone;
      case 'indeterminate':
        return AppTheme.statusInProgress;
      case 'new':
      case 'todo':
        return AppTheme.statusTodo;
      default:
        return AppTheme.statusDefault;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusCat = issue.fields.status.statusCategory.key;
    final statusColor = _statusColor(statusCat);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
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
                style: textTheme.bodyLarge?.copyWith(
                  fontSize: 16,
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ) ?? TextStyle(
                  fontSize: 16,
                  color: colorScheme.onSurface,
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
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      issue.fields.issuetype.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
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
                          backgroundColor: colorScheme.primary,
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
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    )
                  else
                    Text(
                      AppLocalizations.of(context).unassigned,
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
