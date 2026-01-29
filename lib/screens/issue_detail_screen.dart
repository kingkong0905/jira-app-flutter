import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/jira_models.dart';
import '../services/jira_api_service.dart';

/// Issue detail: summary, status, assignee, description, comments (same data as reference app).
class IssueDetailScreen extends StatefulWidget {
  final String issueKey;
  final VoidCallback onBack;
  final VoidCallback? onRefresh;

  const IssueDetailScreen({
    super.key,
    required this.issueKey,
    required this.onBack,
    this.onRefresh,
  });

  @override
  State<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends State<IssueDetailScreen> {
  JiraIssue? _issue;
  List<dynamic> _comments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<JiraApiService>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final issue = await api.getIssueDetails(widget.issueKey);
      final comments = await api.getIssueComments(widget.issueKey);
      if (mounted) {
        setState(() {
          _issue = issue;
          _comments = comments;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  static Color _statusColor(String? key) {
    switch (key?.toLowerCase()) {
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            widget.onRefresh?.call();
            widget.onBack();
          },
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(widget.issueKey, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFF0052CC),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0052CC)))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Color(0xFFDE350B)),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF5E6C84))),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _issue == null
                  ? const Center(child: Text('Issue not found'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _issue!.fields.summary,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF172B4D)),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _chip(
                                _issue!.fields.status.name,
                                _statusColor(_issue!.fields.status.statusCategory.key),
                              ),
                              _chip(_issue!.fields.issuetype.name, const Color(0xFF5E6C84)),
                              if (_issue!.fields.priority != null)
                                _chip(_issue!.fields.priority!.name, const Color(0xFF6554C0)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_issue!.fields.assignee != null)
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: const Color(0xFF0052CC),
                                  backgroundImage: _issue!.fields.assignee!.avatar48 != null
                                      ? NetworkImage(_issue!.fields.assignee!.avatar48!)
                                      : null,
                                  child: _issue!.fields.assignee!.avatar48 == null
                                      ? Text(
                                          _issue!.fields.assignee!.displayName.isNotEmpty
                                              ? _issue!.fields.assignee!.displayName[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _issue!.fields.assignee!.displayName,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          if (_issue!.fields.description != null && _issue!.fields.description!.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            const Text('Description', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Text(
                              _plainText(_issue!.fields.description!),
                              style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF42526E)),
                            ),
                          ],
                          const SizedBox(height: 24),
                          const Text('Comments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          if (_comments.isEmpty)
                            const Text('No comments yet.', style: TextStyle(color: Color(0xFF5E6C84)))
                          else
                            ..._comments.map((c) {
                              final map = c as Map<String, dynamic>;
                              final body = map['body'] ?? map['renderedBody'] ?? '';
                              final author = map['author'];
                              final name = author is Map ? (author['displayName'] as String?) ?? 'Unknown' : 'Unknown';
                              final created = map['created'] as String? ?? '';
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                          const SizedBox(width: 8),
                                          Text(
                                            _formatDate(created),
                                            style: const TextStyle(fontSize: 12, color: Color(0xFF5E6C84)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(_plainText(body), style: const TextStyle(fontSize: 14, height: 1.4)),
                                    ],
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  String _plainText(dynamic content) {
    if (content is String) {
      return content.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    if (content is Map<String, dynamic>) {
      final plain = content['plain'] as String?;
      if (plain != null) return plain;
    }
    return content.toString();
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.month}/${d.day}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
