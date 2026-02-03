import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:open_file/open_file.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:video_player/video_player.dart';
import '../models/jira_models.dart';
import '../services/jira_api_service.dart';
import '../services/storage_service.dart';
import '../services/sentry_api_service.dart';
import '../l10n/app_localizations.dart';
import '../utils/adf_quill_converter.dart';
import 'sentry_issue_detail_screen.dart';

/// Sentry issue URL pattern (e.g. https://org.sentry.io/issues/123/ or https://sentry.io/organizations/org/issues/123/)
final _sentryIssueUrlRegex = RegExp(
  r'https?://[^\s"<>]*sentry[^\s"<>]*/issues/\d+[^\s"<>]*',
  caseSensitive: false,
);

/// Extracts the first Sentry issue URL from Jira description (plain string or ADF).
String? extractFirstSentryUrlFromDescription(dynamic description) {
  if (description == null) return null;
  final urls = <String>[];
  if (description is String) {
    for (final m in _sentryIssueUrlRegex.allMatches(description)) {
      final url = m.group(0);
      if (url != null && url.isNotEmpty && SentryApiService.parseIssueUrl(url) != null) {
        return url.trim();
      }
    }
    return null;
  }
  if (description is Map) {
    _collectUrlsFromAdf(description, urls);
    final plain = _plainFromAdf(description);
    for (final m in _sentryIssueUrlRegex.allMatches(plain)) {
      final url = m.group(0);
      if (url != null && url.isNotEmpty && SentryApiService.parseIssueUrl(url) != null) {
        return url.trim();
      }
    }
    for (final u in urls) {
      if (SentryApiService.parseIssueUrl(u) != null) return u;
    }
  }
  return null;
}

void _collectUrlsFromAdf(dynamic node, List<String> urls) {
  if (node == null) return;
  if (node is Map) {
    if (node['type'] == 'text' && node['marks'] is List) {
      for (final m in node['marks'] as List) {
        if (m is Map && m['type'] == 'link' && m['attrs'] is Map) {
          final href = (m['attrs'] as Map)['href']?.toString();
          if (href != null && href.isNotEmpty) urls.add(href);
        }
      }
    }
    if (node['type'] == 'inlineCard' && node['attrs'] is Map) {
      final url = (node['attrs'] as Map)['url']?.toString();
      if (url != null && url.isNotEmpty) urls.add(url);
    }
    final c = node['content'];
    if (c is List) for (final child in c) _collectUrlsFromAdf(child, urls);
  }
  if (node is List) for (final child in node) _collectUrlsFromAdf(child, urls);
}

String _plainFromAdf(dynamic node) {
  if (node == null) return '';
  if (node is String) return node;
  if (node is Map) {
    final t = node['text'];
    if (t is String) return t;
    final c = node['content'];
    if (c is List) return c.map(_plainFromAdf).join('');
  }
  if (node is List) return node.map(_plainFromAdf).join('');
  return '';
}

/// Issue detail: structure and logic aligned with reference (kingkong0905/jira-app IssueDetailsScreen).
class IssueDetailScreen extends StatefulWidget {
  final String issueKey;
  final VoidCallback onBack;
  final VoidCallback? onRefresh;
  /// When provided, tapping Parent or a Subtask opens that issue in a new screen (same as reference onNavigateToIssue).
  final void Function(String issueKey)? onNavigateToIssue;

  const IssueDetailScreen({
    super.key,
    required this.issueKey,
    required this.onBack,
    this.onRefresh,
    this.onNavigateToIssue,
  });

  @override
  State<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends State<IssueDetailScreen> {
  JiraIssue? _issue;
  List<dynamic> _comments = [];
  List<JiraIssue> _subtasks = [];
  JiraIssue? _parentIssue;
  JiraUser? _currentUser;
  bool _loading = true;
  bool _loadingSubtasks = false;
  bool _loadingParent = false;
  String? _error;
  final TextEditingController _newCommentController = TextEditingController();
  bool _addingComment = false;
  String? _replyToCommentId;
  JiraAttachment? _previewAttachment;
  VideoPlayerController? _previewVideoController;
  String? _previewVideoError;
  final Map<String, Uint8List> _loadedImageBytes = {};
  bool _loadingPreview = false;
  bool _showUserInfoModal = false;
  JiraUser? _selectedUser;
  bool _loadingUserInfo = false;
  // Edit modals (Assignee, Status, Priority, Story Points, Due Date)
  bool _showAssigneePicker = false;
  bool _showStatusPicker = false;
  bool _showPriorityPicker = false;
  bool _showStoryPointsPicker = false;
  bool _showDueDatePicker = false;
  bool _showSprintPicker = false;
  List<Map<String, dynamic>> _transitions = [];
  List<JiraUser> _assignableUsers = [];
  List<Map<String, dynamic>> _priorities = [];
  bool _loadingTransitions = false;
  bool _loadingUsers = false;
  bool _loadingPriorities = false;
  String? _updatingAssignee;
  String? _transitioningStatusId;
  String? _updatingPriorityId;
  bool _updatingStoryPoints = false;
  bool _updatingDueDate = false;
  String _storyPointsInput = '';
  DateTime? _selectedDueDate;
  TextEditingController? _storyPointsController;
  // Sprint picker
  bool _loadingSprints = false;
  List<JiraSprint> _sprints = [];
  int? _boardIdForSprint;
  bool _updatingSprint = false;
  bool _updatingSprintToBacklog = false;
  int? _updatingSprintId;
  // Description edit
  bool _updatingDescription = false;
  // Assignee search
  final TextEditingController _assigneeSearchController = TextEditingController();
  Timer? _assigneeSearchTimer;
  // Mention suggestions for comments
  bool _showMentionSuggestions = false;
  List<JiraUser> _mentionSuggestions = [];
  bool _loadingMentions = false;
  Timer? _mentionSearchTimer;
  int _mentionStartPosition = -1; // Position of "@" in comment text
  OverlayEntry? _mentionOverlayEntry;
  final GlobalKey _commentInputKey = GlobalKey();
  Offset? _mentionOverlayOffset;
  Size? _mentionOverlaySize;
  // Confluence (remote links from Jira API)
  List<JiraRemoteLink> _confluenceLinks = [];
  bool _loadingConfluenceLinks = false;
  int? _deletingConfluenceLinkId;
  // Pull Requests (GitHub – from remote links and dev-status API)
  List<JiraRemoteLink> _pullRequestLinks = [];
  List<JiraDevelopmentPullRequest> _devPullRequests = [];
  List<JiraDevelopmentBranch> _devBranches = [];
  List<JiraDevelopmentCommit> _devCommits = [];
  String _selectedDevTab = 'pullRequests'; // branches, commits, pullRequests
  // Epic children (when issue is Epic)
  List<JiraIssue> _epicChildren = [];
  bool _loadingEpicChildren = false;
  // Sentry link from description (show "View in Sentry" when configured)
  String? _sentryUrl;
  bool _sentryConfigured = false;
  bool _loadingSentryDetail = false;
  // Issue linking
  bool _loadingLinkTypes = false;
  List<JiraIssueLinkType> _linkTypes = [];
  String? _deletingIssueLinkId;

  @override
  void initState() {
    super.initState();
    _load();
    // Listen to comment text changes for mention detection
    _newCommentController.addListener(_onCommentTextChanged);
  }

  @override
  void dispose() {
    _mentionOverlayEntry?.remove();
    _mentionOverlayEntry = null;
    _previewVideoController?.dispose();
    _previewVideoController = null;
    _newCommentController.removeListener(_onCommentTextChanged);
    _newCommentController.dispose();
    _storyPointsController?.dispose();
    _assigneeSearchController.dispose();
    _assigneeSearchTimer?.cancel();
    _mentionSearchTimer?.cancel();
    super.dispose();
  }

  void _removeMentionOverlay() {
    _mentionOverlayEntry?.remove();
    _mentionOverlayEntry = null;
  }

  void _hideMentionOverlay() {
    _removeMentionOverlay();
    setState(() {
      _showMentionSuggestions = false;
      _mentionStartPosition = -1;
    });
  }

  void _showMentionOverlay() {
    _removeMentionOverlay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showMentionSuggestions || _mentionSuggestions.isEmpty) return;
      final box = _commentInputKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      _mentionOverlayOffset = box.localToGlobal(Offset.zero);
      _mentionOverlaySize = box.size;
      _mentionOverlayEntry = OverlayEntry(
        builder: (context) => _buildMentionOverlayContent(),
      );
      Overlay.of(context).insert(_mentionOverlayEntry!);
    });
  }

  /// Overlay content for mention list so it can scroll and receive taps (outside SingleChildScrollView).
  Widget _buildMentionOverlayContent() {
    final colorScheme = Theme.of(context).colorScheme;
    final offset = _mentionOverlayOffset ?? Offset.zero;
    final size = _mentionOverlaySize ?? Size(MediaQuery.of(context).size.width, 100);
    const listHeight = 200.0;
    final top = (offset.dy - listHeight).clamp(0.0, double.infinity);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _hideMentionOverlay,
          ),
        ),
        Positioned(
          left: offset.dx,
          top: top,
          width: size.width,
          height: listHeight,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: colorScheme.surface,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView.separated(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: _mentionSuggestions.length,
                separatorBuilder: (context, index) => Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
                itemBuilder: (context, index) {
                  final user = _mentionSuggestions[index];
                  return InkWell(
                    onTap: () => _insertMention(user),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          if (user.avatarUrls?['48x48'] != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.network(
                                user.avatarUrls!['48x48']!,
                                width: 36,
                                height: 36,
                                errorBuilder: (context, error, stackTrace) => _mentionAvatarPlaceholder(context, user),
                              ),
                            )
                          else
                            _mentionAvatarPlaceholder(context, user),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.displayName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                if (user.emailAddress != null && user.emailAddress!.isNotEmpty)
                                  Text(
                                    user.emailAddress!,
                                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mentionAvatarPlaceholder(BuildContext context, JiraUser user) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: Text(
          user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
          style: TextStyle(
            color: colorScheme.onPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
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
      final currentUser = await api.getMyself();
      if (mounted) {
        final sentryUrl = extractFirstSentryUrlFromDescription(issue?.fields.description);
        final storage = context.read<StorageService>();
        final sentryToken = await storage.getSentryApiToken();
        if (mounted) {
          setState(() {
            _issue = issue;
            _comments = comments;
            _currentUser = currentUser;
            _loading = false;
            _subtasks = issue?.fields.subtasks ?? [];
            _sentryUrl = sentryUrl;
            _sentryConfigured = sentryToken != null && sentryToken.trim().isNotEmpty;
          });
          _loadSubtasks();
          _loadParent(issue);
          _loadConfluenceLinks();
          if ((issue?.fields.issuetype.name ?? '').toLowerCase().contains('epic')) _loadEpicChildren();
        }
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

  Future<void> _loadSubtasks() async {
    final api = context.read<JiraApiService>();
    setState(() => _loadingSubtasks = true);
    try {
      final list = await api.getSubtasks(widget.issueKey);
      if (mounted) {
        if (list.isNotEmpty) {
          setState(() {
            _loadingSubtasks = false;
            _subtasks = list;
          });
          return;
        }
        _subtasks = _subtasks;
      }
      // Fallback: subtasks from fields.subtasks are minimal and often lack assignee. Enrich with full details.
      if (_subtasks.isEmpty) {
        if (mounted) setState(() => _loadingSubtasks = false);
        return;
      }
      final enriched = <JiraIssue>[];
      for (final st in _subtasks) {
        if (st.key.isEmpty) continue;
        try {
          final full = await api.getIssueDetails(st.key);
          if (full != null && mounted) enriched.add(full);
          else if (mounted) enriched.add(st);
        } catch (_) {
          if (mounted) enriched.add(st);
        }
      }
      if (mounted) setState(() {
        _subtasks = enriched.isNotEmpty ? enriched : _subtasks;
        _loadingSubtasks = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _loadingSubtasks = false;
      });
      // On error, try to enrich fallback subtasks so assignee is shown
      if (mounted && _subtasks.isNotEmpty) {
        final api = context.read<JiraApiService>();
        final enriched = <JiraIssue>[];
        for (final st in _subtasks) {
          if (st.key.isEmpty) continue;
          try {
            final full = await api.getIssueDetails(st.key);
            if (full != null && mounted) enriched.add(full);
            else if (mounted) enriched.add(st);
          } catch (_) {
            if (mounted) enriched.add(st);
          }
        }
        if (mounted && enriched.isNotEmpty) setState(() => _subtasks = enriched);
      }
    }
  }

  Future<void> _loadEpicChildren() async {
    final api = context.read<JiraApiService>();
    setState(() => _loadingEpicChildren = true);
    try {
      final list = await api.getEpicChildren(widget.issueKey);
      if (mounted) setState(() {
        _epicChildren = list;
        _loadingEpicChildren = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingEpicChildren = false);
    }
  }

  Future<void> _loadConfluenceLinks() async {
    final api = context.read<JiraApiService>();
    setState(() => _loadingConfluenceLinks = true);
    try {
      final list = await api.getRemoteLinks(widget.issueKey);
      if (!mounted) return;
      setState(() {
        _confluenceLinks = list.where((l) => l.isConfluence).toList();
        _pullRequestLinks = list.where((l) => l.isGitHubPullRequest).toList();
      });
      // Load dev-status info (branches, commits, PRs) using issue ID for comprehensive GitHub integration
      if (_issue != null) {
        final devInfo = await api.getDevelopmentInfo(_issue!.id);
        if (mounted) {
          setState(() {
            _devBranches = devInfo.branches;
            _devCommits = devInfo.commits;
            _devPullRequests = devInfo.pullRequests;
          });
        }
      }
      if (mounted) setState(() => _loadingConfluenceLinks = false);
    } catch (_) {
      if (mounted) setState(() => _loadingConfluenceLinks = false);
    }
  }

  Future<void> _loadParent(JiraIssue? issue) async {
    final parentKey = issue?.fields.parent?.key;
    if (parentKey == null || parentKey.isEmpty) {
      setState(() => _parentIssue = null);
      return;
    }
    final api = context.read<JiraApiService>();
    setState(() => _loadingParent = true);
    try {
      final parent = await api.getIssueDetails(parentKey);
      if (mounted) setState(() {
        _parentIssue = parent;
        _loadingParent = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _parentIssue = null;
        _loadingParent = false;
      });
    }
  }

  void _navigateToIssue(String key) {
    if (widget.onNavigateToIssue != null) {
      widget.onNavigateToIssue!(key);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => IssueDetailScreen(
          issueKey: key,
          onBack: () => Navigator.of(context).pop(),
          onRefresh: widget.onRefresh,
          onNavigateToIssue: widget.onNavigateToIssue,
        ),
      ),
    );
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

  static String _getPriorityEmoji(String? name) {
    if (name == null) return '';
    final n = name.toLowerCase();
    if (n.contains('highest') || n.contains('critical')) return '🔴';
    if (n.contains('high')) return '🟠';
    if (n.contains('medium')) return '🟡';
    if (n.contains('low')) return '🟢';
    if (n.contains('lowest')) return '⚪';
    return '⚡';
  }

  bool get _canEdit => !kIsWeb;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.share, color: colorScheme.onPrimary),
            onSelected: (value) {
              if (value == 'copy') _copyIssueLink();
              else if (value == 'open') _openIssueInBrowser();
            },
            itemBuilder: (context) {
              final cs = Theme.of(context).colorScheme;
              return [
                PopupMenuItem(
                  value: 'copy',
                  child: Row(
                    children: [
                      Icon(Icons.link, size: 20, color: cs.onSurface),
                      const SizedBox(width: 8),
                      Text(AppLocalizations.of(context).copyIssueLink),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'open',
                  child: Row(
                    children: [
                      Icon(Icons.open_in_browser, size: 20, color: cs.onSurface),
                      const SizedBox(width: 8),
                      Text(AppLocalizations.of(context).openInBrowser),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;
          return Stack(
            children: [
              _loading
                  ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                                const SizedBox(height: 16),
                                Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: colorScheme.onSurfaceVariant)),
                                const SizedBox(height: 24),
                                FilledButton(
                                  onPressed: _load,
                                  child: Text(AppLocalizations.of(context).retry),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _issue == null
                          ? Center(child: Text(AppLocalizations.of(context).issueNotFound, style: TextStyle(color: colorScheme.onSurface)))
                          : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSummaryCard(),
                          _buildDetailsCard(),
                          const SizedBox(height: 16),
                          _buildDescriptionCard(),
                          if ((_issue!.fields.attachment ?? []).isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Text(AppLocalizations.of(context).attachments, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colorScheme.onSurface)),
                            const SizedBox(height: 8),
                            _buildAttachmentsSection(),
                          ],
                          if (_issue!.fields.parent != null) ...[
                            const SizedBox(height: 24),
                            Text(AppLocalizations.of(context).parent, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colorScheme.onSurface)),
                            const SizedBox(height: 8),
                            _buildParentCard(),
                          ],
                          const SizedBox(height: 24),
                          Text(AppLocalizations.of(context).subtasks, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colorScheme.onSurface)),
                          const SizedBox(height: 8),
                          _buildSubtasksSection(),
                          if (_issue!.fields.issuetype.name.toLowerCase().contains('epic')) ...[
                            const SizedBox(height: 24),
                            Text(AppLocalizations.of(context).issuesInThisEpic, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colorScheme.onSurface)),
                            const SizedBox(height: 8),
                            _buildEpicChildrenSection(),
                          ],
                          const SizedBox(height: 24),
                          Text(AppLocalizations.of(context).linkedWorkItems, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colorScheme.onSurface)),
                          const SizedBox(height: 8),
                          _buildLinkedWorkItemsSection(),
                          const SizedBox(height: 24),
                          _buildDevelopmentSection(),
                          const SizedBox(height: 24),
                          Text(AppLocalizations.of(context).confluence, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colorScheme.onSurface)),
                          const SizedBox(height: 8),
                          _buildConfluenceSection(),
                          const SizedBox(height: 24),
                          Text(AppLocalizations.of(context).comments, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colorScheme.onSurface)),
                          const SizedBox(height: 12),
                          if (_replyToCommentId != null) _buildReplyBanner(),
                          Stack(
                            key: _commentInputKey,
                            clipBehavior: Clip.none,
                            children: [
                              LayoutBuilder(
                                builder: (context, constraints) {
                                final useStacked = constraints.maxWidth < 400;
                                final inputField = TextField(
                                  controller: _newCommentController,
                                  decoration: InputDecoration(
                                    hintText: AppLocalizations.of(context).addCommentHint,
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  maxLines: useStacked ? 3 : 4,
                                  minLines: 1,
                                );
                                final postButton = FilledButton(
                                  onPressed: _addingComment ? null : _onAddComment,
                                  child: _addingComment
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : Text(AppLocalizations.of(context).postComment),
                                );
                                if (useStacked) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      inputField,
                                      const SizedBox(height: 10),
                                      postButton,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(child: inputField),
                                    const SizedBox(width: 8),
                                    postButton,
                                  ],
                                );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_comments.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(AppLocalizations.of(context).noCommentsYet, style: const TextStyle(color: Color(0xFF5E6C84), fontStyle: FontStyle.italic)),
                            )
                          else
                            ..._commentTreeWidgets(),
                        ],
                      ),
                    ),
          if (_previewAttachment != null) _buildAttachmentPreviewOverlay(),
          if (_showUserInfoModal) _buildUserInfoModal(),
          if (_showAssigneePicker) _buildAssigneePickerModal(),
          if (_showStatusPicker) _buildStatusPickerModal(),
          if (_showPriorityPicker) _buildPriorityPickerModal(),
          if (_showStoryPointsPicker) _buildStoryPointsModal(),
          if (_showDueDatePicker) _buildDueDateModal(),
          if (_showSprintPicker) _buildSprintPickerModal(),
        ],
      );
    },
  ),
    );
  }

  void _closeUserInfoModal() {
    setState(() {
      _showUserInfoModal = false;
      _selectedUser = null;
    });
  }

  Widget _buildUserInfoModal() {
    return GestureDetector(
      onTap: _closeUserInfoModal,
      behavior: HitTestBehavior.opaque,
      child: Material(
        color: Colors.black54,
        child: Center(
          child: GestureDetector(
            onTap: () {}, // prevent tap from closing when tapping the card
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              constraints: const BoxConstraints(maxWidth: 360),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 16, offset: const Offset(0, 8))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _closeUserInfoModal,
                    ),
                  ),
                  if (_loadingUserInfo)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0052CC)),
                      ),
                    )
                  else if (_selectedUser != null) ...[
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: const Color(0xFF0052CC),
                      backgroundImage: _selectedUser!.avatar48 != null ? NetworkImage(_selectedUser!.avatar48!) : null,
                      child: _selectedUser!.avatar48 == null
                          ? Text(
                              _selectedUser!.displayName.isNotEmpty ? _selectedUser!.displayName[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _selectedUser!.displayName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF172B4D)),
                      textAlign: TextAlign.center,
                    ),
                    if (_selectedUser!.emailAddress != null && _selectedUser!.emailAddress!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _selectedUser!.emailAddress!,
                        style: const TextStyle(fontSize: 14, color: Color(0xFF5E6C84)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildAttachmentPreviewOverlay() {
    final att = _previewAttachment!;
    final isImage = att.mimeType.startsWith('image/');
    final isVideo = att.mimeType.startsWith('video/');
    final bytes = _loadedImageBytes[att.id];
    final videoController = _previewVideoController;
    final videoError = _previewVideoError;
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: _closePreviewOverlay,
              ),
            ),
            Expanded(
              child: Center(
                child: isImage
                    ? (_loadingPreview
                        ? const CircularProgressIndicator(color: Colors.white)
                        : bytes != null
                            ? InteractiveViewer(
                                child: Image.memory(bytes, fit: BoxFit.contain),
                              )
                            : Text(AppLocalizations.of(context).failedToLoadImage, style: const TextStyle(color: Colors.white)))
                    : isVideo
                        ? (videoError != null
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.error_outline, color: Colors.white, size: 48),
                                    const SizedBox(height: 16),
                                    Text(AppLocalizations.of(context).videoFailedToLoad, style: const TextStyle(color: Colors.white, fontSize: 16)),
                                    const SizedBox(height: 8),
                                    Text(videoError, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                                    const SizedBox(height: 24),
                                    FilledButton.icon(
                                      onPressed: () async {
                                        final api = context.read<JiraApiService>();
                                        final data = await api.fetchAttachmentBytes(att.content);
                                        if (data == null || !mounted) return;
                                        final dir = await Directory.systemTemp.createTemp();
                                        final ext = att.filename.contains('.') ? att.filename.split('.').last : 'bin';
                                        final file = File('${dir.path}/jira_${att.id}.$ext');
                                        await file.writeAsBytes(data);
                                        OpenFile.open(file.path);
                                        _closePreviewOverlay();
                                      },
                                      icon: const Icon(Icons.open_in_new),
                                      label: Text(AppLocalizations.of(context).openExternally),
                                    ),
                                  ],
                                ),
                              )
                            : videoController != null && videoController.value.isInitialized
                                ? _buildVideoPreviewPlayer(videoController)
                                : Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const CircularProgressIndicator(color: Colors.white),
                                        const SizedBox(height: 16),
                                        Text(AppLocalizations.of(context).loadingVideo, style: const TextStyle(color: Colors.white, fontSize: 14)),
                                      ],
                                    ),
                                  ))
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_fileIcon(att), style: const TextStyle(fontSize: 48)),
                                const SizedBox(height: 16),
                                Text(att.filename, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 24),
                                FilledButton.icon(
                                  onPressed: () async {
                                    final api = context.read<JiraApiService>();
                                    final data = await api.fetchAttachmentBytes(att.content);
                                    if (data == null || !mounted) return;
                                    final dir = await Directory.systemTemp.createTemp();
                                    final ext = att.filename.contains('.') ? att.filename.split('.').last : 'bin';
                                    final file = File('${dir.path}/jira_${att.id}.$ext');
                                    await file.writeAsBytes(data);
                                    OpenFile.open(file.path);
                                    _closePreviewOverlay();
                                  },
                                  icon: const Icon(Icons.open_in_new),
                                  label: Text(AppLocalizations.of(context).open),
                                ),
                              ],
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPreviewPlayer(VideoPlayerController controller) {
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            GestureDetector(
              onTap: () {
                if (controller.value.isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
                setState(() {});
              },
              child: controller.value.isPlaying
                  ? const SizedBox.shrink()
                  : Container(
                      color: Colors.black38,
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 72),
                    ),
            ),
          ],
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

  Widget _detailRow(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF5E6C84), fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }

  Widget _userTile(JiraUser user, {double radius = 14}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: colorScheme.primary,
          backgroundImage: user.avatar48 != null ? NetworkImage(user.avatar48!) : null,
          child: user.avatar48 == null
              ? Text(
                  user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
                  style: TextStyle(color: colorScheme.onPrimary, fontSize: radius > 14 ? 16 : 12, fontWeight: FontWeight.w600),
                )
              : null,
        ),
        const SizedBox(width: 8),
        Flexible(child: Text(user.displayName, style: TextStyle(fontSize: 14, color: colorScheme.onSurface), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  /// IssueSummaryCard-style: key+status row, divider, Summary header + priority emoji + Edit, summary text.
  Widget _buildSummaryCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(_issue!.fields.status.statusCategory.key);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [BoxShadow(color: colorScheme.shadow.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context).issueKey, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant, letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Text(_issue!.key, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: colorScheme.primary, letterSpacing: 0.3)),
                ],
              ),
              if (_canEdit)
                InkWell(
                  onTap: _openStatusPicker,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.3), blurRadius: 2, offset: const Offset(0, 1))],
                    ),
                    child: Text(_issue!.fields.status.name.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5)),
                  ),
                )
              else
                _chip(_issue!.fields.status.name, statusColor),
            ],
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: colorScheme.outlineVariant),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('📝', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).summary, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colorScheme.onSurface, letterSpacing: 0.2)),
                  if (_issue!.fields.priority != null) ...[
                    const SizedBox(width: 8),
                    Text(_getPriorityEmoji(_issue!.fields.priority!.name), style: const TextStyle(fontSize: 16)),
                  ],
                ],
              ),
              if (_canEdit)
                TextButton(
                  onPressed: () => _openSummaryEdit(),
                  child: Text(AppLocalizations.of(context).edit, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.primary)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _issue!.fields.summary,
            style: TextStyle(fontSize: 20, color: colorScheme.onSurface, fontWeight: FontWeight.w600, height: 1.5, letterSpacing: 0.1),
          ),
        ],
      ),
    );
  }

  /// IssueDetailsFields-style: card with icon+label rows (Assignee, Reporter, Priority, Type, Sprint, Story Points, Due Date).
  Widget _buildDetailsCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final sprintDisplay = _formatSprint(context, _issue!.fields.sprint);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [BoxShadow(color: colorScheme.shadow.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📋', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context).details, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colorScheme.onSurface, letterSpacing: 0.2)),
            ],
          ),
          const SizedBox(height: 16),
          _detailRowTap(
            icon: '👤',
            label: AppLocalizations.of(context).assignee,
            value: _issue!.fields.assignee != null ? _userTile(_issue!.fields.assignee!, radius: 12) : Text(AppLocalizations.of(context).unassigned, style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
            onTap: _canEdit ? _openAssigneePicker : null,
          ),
          if (_issue!.fields.reporter != null)
            _detailRowStatic(
              icon: '📝',
              label: AppLocalizations.of(context).reporter,
              value: _userTile(_issue!.fields.reporter!, radius: 12),
            ),
          _detailRowTap(
            icon: '⚡',
            label: AppLocalizations.of(context).priority,
            value: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_getPriorityEmoji(_issue!.fields.priority?.name), style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(_issue!.fields.priority?.name ?? AppLocalizations.of(context).none, style: TextStyle(fontSize: 15, color: colorScheme.onSurface, fontWeight: FontWeight.w500)),
              ],
            ),
            onTap: _canEdit ? _openPriorityPicker : null,
          ),
          _detailRowStatic(icon: '🏷️', label: AppLocalizations.of(context).type, value: Text(_issue!.fields.issuetype.name, style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500))),
          _detailRowTap(
            icon: '🏃',
            label: AppLocalizations.of(context).sprint,
            value: Text(sprintDisplay, style: TextStyle(fontSize: 15, color: colorScheme.onSurface, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: _canEdit ? _openSprintPicker : null,
          ),
          _detailRowTap(
            icon: '🎯',
            label: AppLocalizations.of(context).storyPoints,
            value: Text(_issue!.fields.customfield_10016?.toString() ?? AppLocalizations.of(context).notSet, style: TextStyle(fontSize: 15, color: colorScheme.onSurface, fontWeight: FontWeight.w500)),
            onTap: _canEdit ? _openStoryPointsPicker : null,
          ),
          _detailRowTap(
            icon: '📅',
            label: AppLocalizations.of(context).dueDate,
            value: Text(
              _issue!.fields.duedate != null ? _formatDueDate(_issue!.fields.duedate!) : AppLocalizations.of(context).notSet,
              style: TextStyle(fontSize: 15, color: colorScheme.onSurface, fontWeight: FontWeight.w500),
            ),
            onTap: _canEdit ? _openDueDatePicker : null,
          ),
        ],
      ),
    );
  }

  /// Description card with Edit (plain/ADF display, edit as plain text → ADF).
  Widget _buildDescriptionCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [BoxShadow(color: colorScheme.shadow.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(AppLocalizations.of(context).description, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colorScheme.onSurface, letterSpacing: 0.2)),
              if (_canEdit)
                TextButton(
                  onPressed: _updatingDescription ? null : _openDescriptionEdit,
                  child: _updatingDescription
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary))
                      : Text('Edit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.primary)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _DescriptionBodyWidget(
            description: _issue!.fields.description,
            attachments: _issue!.fields.attachment ?? [],
            loadedImageBytes: _loadedImageBytes,
            onAttachmentPress: _onAttachmentPress,
            onNeedLoadImage: _loadDescriptionImage,
          ),
          if (_sentryUrl != null && _sentryConfigured) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadingSentryDetail ? null : _openSentryDetail,
              icon: _loadingSentryDetail
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                    )
                  : const Icon(Icons.bug_report, size: 18),
              label: Text(AppLocalizations.of(context).viewInSentry),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openDescriptionEdit() async {
    final initialDescription = _issue!.fields.description;
    final attachments = _issue!.fields.attachment ?? [];
    final adfResult = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute<Map<String, dynamic>>(
        builder: (ctx) => _DescriptionEditPage(
          initialDescription: initialDescription,
          attachments: attachments,
          loadedImageBytes: _loadedImageBytes,
        ),
      ),
    );
    if (adfResult == null || !mounted) return;
    setState(() => _updatingDescription = true);
    final err = await context.read<JiraApiService>().updateIssueField(widget.issueKey, {'description': adfResult});
    if (mounted) {
      setState(() => _updatingDescription = false);
      if (err == null) {
        await _refreshIssue();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).descriptionUpdated)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }

  /// Extract sprint ID from dynamic sprint field (can be JiraSprintRef, List, or Map)
  int? _getSprintId(dynamic sprint) {
    if (sprint == null) return null;
    if (sprint is JiraSprintRef) return sprint.id;
    if (sprint is List && sprint.isNotEmpty) {
      final last = sprint.last;
      if (last is JiraSprintRef) return last.id;
      if (last is Map) {
        final id = last['id'];
        if (id is int) return id;
        if (id is String) return int.tryParse(id);
      }
    }
    if (sprint is Map) {
      final id = sprint['id'];
      if (id is int) return id;
      if (id is String) return int.tryParse(id);
    }
    return null;
  }

  String _formatSprint(BuildContext context, dynamic sprint) {
    final none = AppLocalizations.of(context).none;
    if (sprint == null) return none;
    
    // Handle JiraSprintRef object
    if (sprint is JiraSprintRef) {
      return sprint.name.isNotEmpty ? sprint.name : none;
    }
    
    // Handle List of sprints (take the last/most recent one)
    if (sprint is List) {
      if (sprint.isEmpty) return none;
      final last = sprint.last;
      if (last is JiraSprintRef) {
        return last.name.isNotEmpty ? last.name : none;
      }
      if (last is Map) {
        // Try to extract name from Map
        final name = last['name']?.toString() ?? 
                    last['sprintName']?.toString() ??
                    last['displayName']?.toString();
        if (name != null && name.isNotEmpty) {
          return name;
        }
        // If no name, try to create JiraSprintRef from Map
        try {
          final sprintRef = JiraSprintRef.fromJson(last as Map<String, dynamic>);
          return sprintRef.name.isNotEmpty ? sprintRef.name : none;
        } catch (e) {
          // If parsing fails, return none
          return none;
        }
      }
    }
    
    // Handle raw Map object from API
    if (sprint is Map) {
      // Try to extract name directly
      final name = sprint['name']?.toString() ?? 
                  sprint['sprintName']?.toString() ??
                  sprint['displayName']?.toString();
      if (name != null && name.isNotEmpty) {
        return name;
      }
      // Try to parse as JiraSprintRef
      try {
        final sprintRef = JiraSprintRef.fromJson(sprint as Map<String, dynamic>);
        return sprintRef.name.isNotEmpty ? sprintRef.name : none;
      } catch (e) {
        // If parsing fails, return none
        return none;
      }
    }
    
    // Last resort: convert to string
    final str = sprint.toString();
    return str.isNotEmpty && str != 'null' ? str : none;
  }

  String _formatDueDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.month}/${d.day}/${d.year}';
    } catch (_) {
      return iso;
    }
  }

  Widget _detailRowTap({required String icon, required String label, required Widget value, VoidCallback? onTap}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 120,
              child: Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(child: value),
                    if (onTap != null) Text(' ›', style: TextStyle(fontSize: 20, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w300)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRowStatic({required String icon, required String label, required Widget value}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [Flexible(child: value)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSummaryEdit() async {
    final controller = TextEditingController(text: _issue!.fields.summary);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).editSummary),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context).cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(AppLocalizations.of(context).save),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    final err = await context.read<JiraApiService>().updateIssueField(widget.issueKey, {'summary': result});
    if (mounted) {
      if (err == null) {
        await _refreshIssue();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).summaryUpdated)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }

  void _openAssigneePicker() async {
    _assigneeSearchController.clear();
    _assigneeSearchTimer?.cancel();
    setState(() { _showAssigneePicker = true; _loadingUsers = true; });
    final api = context.read<JiraApiService>();
    final users = await api.getAssignableUsers(widget.issueKey);
    if (mounted) setState(() { _assignableUsers = users; _loadingUsers = false; });
  }

  void _debouncedAssigneeSearch(String query) {
    _assigneeSearchTimer?.cancel();
    _assigneeSearchTimer = Timer(const Duration(milliseconds: 300), () async {
      final api = context.read<JiraApiService>();
      if (mounted) setState(() => _loadingUsers = true);
      final users = await api.getAssignableUsers(widget.issueKey, query: query.trim().isEmpty ? null : query.trim());
      if (mounted) setState(() { _assignableUsers = users; _loadingUsers = false; });
    });
  }

  void _openStatusPicker() async {
    setState(() { _showStatusPicker = true; _loadingTransitions = true; });
    final api = context.read<JiraApiService>();
    final list = await api.getTransitions(widget.issueKey);
    if (mounted) setState(() { _transitions = list; _loadingTransitions = false; });
  }

  void _openPriorityPicker() async {
    setState(() { _showPriorityPicker = true; _loadingPriorities = true; });
    final api = context.read<JiraApiService>();
    final list = await api.getPriorities();
    if (mounted) setState(() { _priorities = list; _loadingPriorities = false; });
  }

  void _openStoryPointsPicker() {
    _storyPointsInput = _issue!.fields.customfield_10016?.toString() ?? '';
    _storyPointsController?.dispose();
    _storyPointsController = TextEditingController(text: _storyPointsInput);
    setState(() => _showStoryPointsPicker = true);
  }

  void _openDueDatePicker() {
    _selectedDueDate = _issue!.fields.duedate != null ? DateTime.tryParse(_issue!.fields.duedate!) : DateTime.now();
    setState(() => _showDueDatePicker = true);
  }

  void _openSprintPicker() async {
    final issue = _issue;
    if (issue == null) return;
    // Use project from fields, or derive from issue key (e.g. PROJ-123 -> PROJ)
    String? projectKey = issue.fields.projectKey;
    if (projectKey == null || projectKey.isEmpty) {
      final keyParts = issue.key.split('-');
      if (keyParts.isNotEmpty && keyParts.first.isNotEmpty) {
        projectKey = keyParts.first;
      }
    }
    if (projectKey == null || projectKey.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).sprintPickerNoProject)));
      return;
    }
    setState(() {
      _showSprintPicker = true;
      _loadingSprints = true;
      _sprints = [];
      _boardIdForSprint = null;
    });
    try {
      final api = context.read<JiraApiService>();
      final res = await api.getBoards(projectKeyOrId: projectKey, maxResults: 10);
      final boards = res.boards;
      if (!mounted) return;
      if (boards.isEmpty) {
        setState(() { _showSprintPicker = false; _loadingSprints = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).sprintPickerNoBoard)));
        return;
      }
      final board = boards.firstWhere((b) => b.type.toLowerCase() == 'scrum', orElse: () => boards.first);
      final allSprints = await api.getSprintsForBoard(board.id);
      
      // Get current sprint ID from issue (if any)
      final currentSprintId = _getSprintId(issue.fields.sprint);
      
      // Filter to show active and future sprints, plus the current sprint (even if closed)
      final filteredSprints = allSprints.where((s) {
        if (s.state == 'active' || s.state == 'future') return true;
        if (currentSprintId != null && s.id == currentSprintId) return true; // Include current sprint even if closed
        return false;
      }).toList();
      
      // Sort: current sprint first, then active, then future
      filteredSprints.sort((a, b) {
        if (currentSprintId != null) {
          if (a.id == currentSprintId) return -1;
          if (b.id == currentSprintId) return 1;
        }
        if (a.state == 'active' && b.state != 'active') return -1;
        if (b.state == 'active' && a.state != 'active') return 1;
        return 0;
      });
      
      if (!mounted) return;
      setState(() {
        _boardIdForSprint = board.id;
        _sprints = filteredSprints;
        _loadingSprints = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _showSprintPicker = false; _loadingSprints = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _refreshIssue() async {
    final api = context.read<JiraApiService>();
    final issue = await api.getIssueDetails(widget.issueKey);
    if (!mounted) return;
    final sentryUrl = extractFirstSentryUrlFromDescription(issue?.fields.description);
    final storage = context.read<StorageService>();
    final sentryToken = await storage.getSentryApiToken();
    if (mounted) {
      setState(() {
        _issue = issue;
        _sentryUrl = sentryUrl;
        _sentryConfigured = sentryToken != null && sentryToken.trim().isNotEmpty;
      });
    }
  }

  Future<void> _openSentryDetail() async {
    final url = _sentryUrl;
    if (url == null || url.isEmpty) return;
    final parts = SentryApiService.parseIssueUrl(url);
    if (parts == null) return;
    setState(() => _loadingSentryDetail = true);
    try {
      final storage = context.read<StorageService>();
      final api = context.read<SentryApiService>();
      final token = await storage.getSentryApiToken();
      final detail = await api.getIssueDetail(parts: parts, authToken: token);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => SentryIssueDetailScreen(
            detail: detail,
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
      );
    } on SentryApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSentryDetail = false);
    }
  }

  Widget _buildAssigneePickerModal() {
    return _modalSheet(
      title: AppLocalizations.of(context).assignee,
      onClose: () {
        _assigneeSearchController.clear();
        _assigneeSearchTimer?.cancel();
        setState(() => _showAssigneePicker = false);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _assigneeSearchController,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).searchAssignee,
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
              ),
              onChanged: _debouncedAssigneeSearch,
            ),
          ),
          if (_loadingUsers)
            Padding(padding: const EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)))
          else ...[
            ListTile(
              title: Text(AppLocalizations.of(context).unassigned, style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.onSurface)),
              onTap: () async {
                setState(() => _updatingAssignee = 'unassign');
                final err = await context.read<JiraApiService>().updateIssueField(widget.issueKey, {'assignee': null});
                if (mounted) {
                  setState(() { _updatingAssignee = null; _showAssigneePicker = false; });
                  if (err == null) {
                    await _refreshIssue();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).assigneeCleared)));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                }
              },
              trailing: _updatingAssignee == 'unassign' ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            ),
            ..._assignableUsers.map((u) {
              final colorScheme = Theme.of(context).colorScheme;
              final isCurrent = _issue!.fields.assignee?.accountId == u.accountId;
              return ListTile(
                leading: CircleAvatar(radius: 16, backgroundColor: colorScheme.primary, backgroundImage: u.avatar48 != null ? NetworkImage(u.avatar48!) : null, child: u.avatar48 == null ? Text(u.displayName.isNotEmpty ? u.displayName[0] : '?', style: TextStyle(color: colorScheme.onPrimary)) : null),
                title: Text(u.displayName, style: TextStyle(color: colorScheme.onSurface)),
                subtitle: u.emailAddress != null ? Text(u.emailAddress!, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)) : null,
                selected: isCurrent,
                onTap: isCurrent ? null : () async {
                  setState(() => _updatingAssignee = u.accountId);
                  final err = await context.read<JiraApiService>().updateIssueField(widget.issueKey, {'assignee': {'accountId': u.accountId}});
                  if (mounted) {
                    setState(() { _updatingAssignee = null; _showAssigneePicker = false; });
                    if (err == null) {
                      await _refreshIssue();
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).assigneeUpdated)));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    }
                  }
                },
                trailing: _updatingAssignee == u.accountId ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildSprintPickerModal() {
    return _modalSheet(
      title: AppLocalizations.of(context).sprint,
      onClose: () => setState(() => _showSprintPicker = false),
      child: _loadingSprints
          ? Padding(padding: const EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)))
          : ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Text('📋', style: TextStyle(fontSize: 20)),
                  title: Text(AppLocalizations.of(context).backlog, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  trailing: _updatingSprintToBacklog ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                  onTap: _boardIdForSprint == null
                      ? null
                      : () async {
                          setState(() { _updatingSprint = true; _updatingSprintToBacklog = true; });
                          final err = await context.read<JiraApiService>().moveIssueToBacklog(widget.issueKey, _boardIdForSprint!);
                          if (mounted) {
                            setState(() { _updatingSprint = false; _updatingSprintToBacklog = false; _updatingSprintId = null; _showSprintPicker = false; });
                            if (err == null) {
                              await _refreshIssue();
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).movedToBacklog)));
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                            }
                          }
                        },
                ),
                ..._sprints.map((s) {
                  // Check if this sprint is the current sprint for the issue
                  final currentSprintId = _getSprintId(_issue?.fields.sprint);
                  final isCurrent = currentSprintId != null && currentSprintId == s.id;
                  return ListTile(
                    leading: Text(s.state == 'active' ? '🏃' : '📅', style: const TextStyle(fontSize: 20)),
                    title: Text(s.name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    subtitle: Text(s.state.toUpperCase(), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    selected: isCurrent,
                    trailing: _updatingSprintId == s.id ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                    onTap: isCurrent
                        ? null
                        : () async {
                            setState(() { _updatingSprint = true; _updatingSprintId = s.id; });
                            final err = await context.read<JiraApiService>().moveIssueToSprint(widget.issueKey, s.id);
                            if (mounted) {
                              setState(() { _updatingSprint = false; _updatingSprintId = null; _showSprintPicker = false; });
                              if (err == null) {
                                await _refreshIssue();
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).sprintUpdated)));
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                              }
                            }
                          },
                  );
                }),
              ],
            ),
    );
  }

  Widget _buildStatusPickerModal() {
    return _modalSheet(
      title: 'Status',
      onClose: () => setState(() => _showStatusPicker = false),
      wrapInScrollView: false,
      child: _loadingTransitions
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)))
          : _transitions.isEmpty
              ? Padding(padding: const EdgeInsets.all(24), child: Text('No transitions available', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
              : ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                  child: ListView(
                    shrinkWrap: false,
                    children: _transitions.map((t) {
                      final id = t['id']?.toString() ?? '';
                      final name = t['name']?.toString() ?? id;
                      final to = t['to'];
                      final toName = to is Map ? (to['name']?.toString() ?? '') : '';
                      final isTransitioning = _transitioningStatusId == id;
                      return ListTile(
                        title: Text(name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                        subtitle: toName.isNotEmpty ? Text('→ $toName', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)) : null,
                        onTap: () async {
                          setState(() => _transitioningStatusId = id);
                          final err = await context.read<JiraApiService>().transitionIssue(widget.issueKey, id);
                          if (mounted) {
                            setState(() { _transitioningStatusId = null; _showStatusPicker = false; });
                            if (err == null) {
                              await _refreshIssue();
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status updated')));
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                            }
                          }
                        },
                        trailing: isTransitioning ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                      );
                    }).toList(),
                  ),
                ),
    );
  }

  Widget _buildPriorityPickerModal() {
    return _modalSheet(
      title: 'Priority',
      onClose: () => setState(() => _showPriorityPicker = false),
      wrapInScrollView: false,
      child: _loadingPriorities
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)))
          : ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView(
                shrinkWrap: false,
                children: _priorities.map((p) {
                  final id = p['id']?.toString() ?? '';
                  final name = p['name']?.toString() ?? 'Unknown';
                  final isUpdating = _updatingPriorityId == id;
                  return ListTile(
                    leading: Text(_getPriorityEmoji(name), style: const TextStyle(fontSize: 20)),
                    title: Text(name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    onTap: () async {
                      setState(() => _updatingPriorityId = id);
                      final err = await context.read<JiraApiService>().updateIssueField(widget.issueKey, {'priority': {'id': id.toString()}});
                      if (mounted) {
                        setState(() { _updatingPriorityId = null; _showPriorityPicker = false; });
                        if (err == null) {
                          await _refreshIssue();
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Priority updated')));
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                        }
                      }
                    },
                    trailing: isUpdating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                  );
                }).toList(),
              ),
            ),
    );
  }

  Widget _buildStoryPointsModal() {
    return _modalSheet(
      title: 'Story Points',
      onClose: () {
        _storyPointsController?.dispose();
        _storyPointsController = null;
        setState(() => _showStoryPointsPicker = false);
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Story points', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              controller: _storyPointsController,
              onChanged: (v) => setState(() => _storyPointsInput = v),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [1, 2, 3, 5, 8, 13].map((n) => ActionChip(
                label: Text('$n'),
                onPressed: () => setState(() => _storyPointsInput = '$n'),
              )).toList(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _updatingStoryPoints ? null : () async {
                final input = _storyPointsController?.text.trim() ?? _storyPointsInput.trim();
                setState(() => _updatingStoryPoints = true);
                final v = input.isEmpty ? null : double.tryParse(input);
                final err = await context.read<JiraApiService>().updateIssueField(widget.issueKey, {'customfield_10016': v});
                if (mounted) {
                  _storyPointsController?.dispose();
                  _storyPointsController = null;
                  setState(() { _updatingStoryPoints = false; _showStoryPointsPicker = false; });
                  if (err == null) {
                    await _refreshIssue();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Story points updated')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                }
              },
              child: _updatingStoryPoints ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDueDateModal() {
    return _modalSheet(
      title: AppLocalizations.of(context).dueDate,
      onClose: () => setState(() => _showDueDatePicker = false),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (Platform.isIOS)
              SizedBox(
                height: 200,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: _selectedDueDate ?? DateTime.now(),
                  onDateTimeChanged: (d) => setState(() => _selectedDueDate = d),
                ),
              )
            else
              CalendarDatePicker(
                initialDate: _selectedDueDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                onDateChanged: (d) => setState(() => _selectedDueDate = d),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(onPressed: () => setState(() => _selectedDueDate = null), child: const Text('Clear')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _updatingDueDate ? null : () async {
                    setState(() => _updatingDueDate = true);
                    final dateStr = _selectedDueDate != null ? '${_selectedDueDate!.year}-${_selectedDueDate!.month.toString().padLeft(2, '0')}-${_selectedDueDate!.day.toString().padLeft(2, '0')}' : null;
                    final err = await context.read<JiraApiService>().updateIssueField(widget.issueKey, {'duedate': dateStr});
                    if (mounted) {
                      setState(() { _updatingDueDate = false; _showDueDatePicker = false; });
                      if (err == null) {
                        await _refreshIssue();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dateStr != null ? 'Due date updated' : 'Due date cleared')));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                      }
                    }
                  },
                  child: _updatingDueDate ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Update'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _modalSheet({required String title, required VoidCallback onClose, required Widget child, bool wrapInScrollView = true}) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onClose,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black54,
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colorScheme.onSurface)),
                      IconButton(icon: const Icon(Icons.close), onPressed: onClose),
                    ],
                  ),
                ),
                Flexible(child: wrapInScrollView ? SingleChildScrollView(child: child) : child),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fileIcon(JiraAttachment a) {
    if (a.mimeType.startsWith('image/')) return '🖼️';
    if (a.mimeType.startsWith('video/')) return '🎥';
    if (a.mimeType == 'application/pdf') return '📄';
    return '📎';
  }

  Widget _buildAttachmentsSection() {
    final list = _issue!.fields.attachment ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: list.map((a) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => _onAttachmentPress(a),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFDFE1E6)),
                ),
                child: Row(
                  children: [
                    Text(_fileIcon(a), style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.filename, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF172B4D)), maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (a.size != null)
                            Text('${(a.size! / 1024).toStringAsFixed(1)} KB', style: const TextStyle(fontSize: 12, color: Color(0xFF7A869A))),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFF5E6C84), size: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _onMentionPress(String accountId, String displayName) {
    setState(() {
      _showUserInfoModal = true;
      _selectedUser = null;
      _loadingUserInfo = true;
    });
    context.read<JiraApiService>().getUserByAccountId(accountId).then((user) {
      if (mounted) {
        setState(() {
          _selectedUser = user ?? JiraUser(accountId: accountId, displayName: displayName.replaceFirst('@', '').trim(), emailAddress: null, avatarUrls: null);
          _loadingUserInfo = false;
        });
      }
    });
  }

  void _closePreviewOverlay() {
    _previewVideoController?.dispose();
    _previewVideoController = null;
    _previewVideoError = null;
    setState(() => _previewAttachment = null);
  }

  void _initVideoPreview(JiraAttachment att) {
    final api = context.read<JiraApiService>();
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(att.content),
      httpHeaders: api.authHeaders,
    );
    _previewVideoController = controller;
    _previewVideoError = null;
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    controller.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object e) {
      if (mounted) setState(() => _previewVideoError = e.toString());
    });
  }

  void _onAttachmentPress(JiraAttachment att) {
    _previewVideoController?.dispose();
    _previewVideoController = null;
    _previewVideoError = null;
    setState(() {
      _previewAttachment = att;
      _loadingPreview = att.mimeType.startsWith('image/') && !_loadedImageBytes.containsKey(att.id);
    });
    if (att.mimeType.startsWith('image/') && !_loadedImageBytes.containsKey(att.id)) {
      context.read<JiraApiService>().fetchAttachmentBytes(att.content).then((bytes) {
        if (mounted && bytes != null) setState(() {
          _loadedImageBytes[att.id] = Uint8List.fromList(bytes);
          _loadingPreview = false;
        });
      });
    } else if (att.mimeType.startsWith('video/')) {
      _initVideoPreview(att);
    } else {
      setState(() => _loadingPreview = false);
    }
  }

  void _loadDescriptionImage(JiraAttachment att) {
    if (_loadedImageBytes.containsKey(att.id)) return;
    context.read<JiraApiService>().fetchAttachmentBytes(att.content).then((bytes) {
      if (mounted && bytes != null) setState(() => _loadedImageBytes[att.id] = Uint8List.fromList(bytes));
    });
  }

  Widget _buildReplyBanner() {
    final list = _comments.whereType<Map<String, dynamic>>().where((c) => c['id']?.toString() == _replyToCommentId).toList();
    final replyTo = list.isNotEmpty ? list.first : null;
    final name = replyTo != null ? (stringFromJson(replyTo['author'] is Map ? (replyTo['author'] as Map)['displayName'] : null) ?? 'Unknown') : 'Unknown';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE6FCFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(child: Text('Replying to $name', style: const TextStyle(fontSize: 14, color: Color(0xFF0052CC), fontWeight: FontWeight.w500))),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: Color(0xFF0052CC)),
            onPressed: () => setState(() => _replyToCommentId = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  /// Parent card: same as reference IssueParentCard — tap to open parent issue.
  Widget _buildParentCard() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_loadingParent) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(height: 44, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary))),
      );
    }
    final parent = _parentIssue ?? _issue?.fields.parent;
    if (parent == null) return const SizedBox.shrink();
    final key = parent is JiraIssue ? parent.key : (parent as JiraIssueParent).key;
    final summary = parent is JiraIssue ? parent.fields.summary : (parent as JiraIssueParent).summary ?? '';
    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _navigateToIssue(key),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.account_tree, color: colorScheme.onSurfaceVariant, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(key, style: TextStyle(fontWeight: FontWeight.w700, color: colorScheme.primary, fontSize: 14)),
                    if (summary.isNotEmpty)
                      Text(summary, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// Subtasks section: same as reference IssueSubtasksCard — list of subtasks, tap to open.
  Widget _buildSubtasksSection() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_loadingSubtasks) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(height: 44, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary))),
      );
    }
    if (_subtasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('No subtasks.', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _subtasks.map((issue) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => _navigateToIssue(issue.key),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _statusColor(issue.fields.status.statusCategory.key),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            issue.fields.status.name,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(issue.key, style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary, fontSize: 13), overflow: TextOverflow.ellipsis),
                        ),
                        Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant, size: 20),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(issue.fields.summary, style: TextStyle(fontSize: 13, color: colorScheme.onSurface), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (issue.fields.assignee != null) ...[
                      const SizedBox(height: 8),
                      _userTile(issue.fields.assignee!, radius: 10),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Epic children section: list issues in this Epic (when issue type is Epic). JQL parentEpic = key.
  Widget _buildEpicChildrenSection() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_loadingEpicChildren) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(height: 44, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary))),
      );
    }
    if (_epicChildren.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(AppLocalizations.of(context).noIssuesInThisEpic, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _epicChildren.map((issue) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => _navigateToIssue(issue.key),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _statusColor(issue.fields.status.statusCategory.key),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            issue.fields.status.name,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(issue.key, style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary, fontSize: 13), overflow: TextOverflow.ellipsis),
                        ),
                        Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant, size: 20),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(issue.fields.summary, style: TextStyle(fontSize: 13, color: colorScheme.onSurface), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (issue.fields.assignee != null) ...[
                      const SizedBox(height: 8),
                      _userTile(issue.fields.assignee!, radius: 10),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Linked work items section: list issue links from _issue.fields.issuelinks (Jira API).
  Widget _buildLinkedWorkItemsSection() {
    final colorScheme = Theme.of(context).colorScheme;
    final links = _issue?.fields.issuelinks ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (links.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Text(AppLocalizations.of(context).noLinkedWorkItems, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
          )
        else
          ...links.map((link) {
            final issue = link.linkedIssue;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => _navigateToIssue(issue.key),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                link.directionLabel,
                                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(issue.key, style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary, fontSize: 13), overflow: TextOverflow.ellipsis),
                            ),
                            if (link.id != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _deletingIssueLinkId == link.id ? null : () => _confirmRemoveIssueLink(link.id!, issue.key),
                                color: colorScheme.error,
                                tooltip: AppLocalizations.of(context).removeIssueLink,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                              ),
                            Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant, size: 20),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(issue.fields.summary, style: TextStyle(fontSize: 13, color: colorScheme.onSurface), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _statusColor(issue.fields.status.statusCategory.key),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                issue.fields.status.name,
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (issue.fields.assignee != null) ...[
                              const SizedBox(width: 8),
                              _userTile(issue.fields.assignee!, radius: 10),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showAddIssueLinkDialog(),
            icon: Icon(Icons.add_link, size: 18, color: colorScheme.primary),
            label: Text(AppLocalizations.of(context).linkIssue),
          ),
        ),
      ],
    );
  }

  /// Parse GitHub PR URL for repo (owner/repo) and PR number.
  static ({String? repo, String? prId}) _parseGitHubPrUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.host.toLowerCase().contains('github.com')) return (repo: null, prId: null);
      final pathSegments = uri.pathSegments;
      final pullIdx = pathSegments.indexOf('pull');
      if (pullIdx < 2 || pullIdx >= pathSegments.length - 1) return (repo: null, prId: null);
      final owner = pathSegments[0];
      final repoName = pathSegments[1];
      final prNum = pathSegments[pullIdx + 1];
      return (repo: '$owner/$repoName', prId: '#$prNum');
    } catch (_) {
      return (repo: null, prId: null);
    }
  }

  List<PullRequestRow> _buildPullRequestRows() {
    final seenUrls = <String>{};
    final rows = <PullRequestRow>[];
    for (final link in _pullRequestLinks) {
      if (link.url.isEmpty || !seenUrls.add(link.url)) continue;
      final parsed = _parseGitHubPrUrl(link.url);
      rows.add(PullRequestRow(
        url: link.url,
        title: link.title.isNotEmpty ? link.title : 'Pull Request',
        id: parsed.prId ?? '#—',
        repositoryName: parsed.repo,
      ));
    }
    for (final pr in _devPullRequests) {
      if (pr.url.isEmpty || !seenUrls.add(pr.url)) continue;
      rows.add(PullRequestRow(
        url: pr.url,
        title: pr.name,
        id: pr.id != null ? '#${pr.id}' : _parseGitHubPrUrl(pr.url).prId ?? '#—',
        authorName: pr.authorName,
        authorAvatarUrl: pr.authorAvatarUrl,
        branchText: pr.sourceBranch != null && pr.targetBranch != null
            ? '${pr.sourceBranch} → ${pr.targetBranch}'
            : (pr.sourceBranch ?? pr.targetBranch),
        status: pr.status,
        updated: pr.updated,
        repositoryName: pr.repositoryName ?? _parseGitHubPrUrl(pr.url).repo,
      ));
    }
    return rows;
  }

  /// Development section: title, tabs, repository, and PR table (Author | ID | Summary | Status | Updated).
  Widget _buildDevelopmentSection() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_loadingConfluenceLinks) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(height: 44, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary))),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${AppLocalizations.of(context).development} ${widget.issueKey}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colorScheme.onSurface)),
        const SizedBox(height: 12),
        // Tabs
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildDevTab(AppLocalizations.of(context).branches, 'branches', _devBranches.isNotEmpty),
              _buildDevTab(AppLocalizations.of(context).commits, 'commits', _devCommits.isNotEmpty),
              _buildDevTab(AppLocalizations.of(context).pullRequests, 'pullRequests', _buildPullRequestRows().isNotEmpty),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Content based on selected tab
        if (_selectedDevTab == 'branches')
          _buildBranchesContent(colorScheme)
        else if (_selectedDevTab == 'commits')
          _buildCommitsContent(colorScheme)
        else
          _buildPullRequestsContent(colorScheme),
      ],
    );
  }

  Widget _buildBranchesContent(ColorScheme colorScheme) {
    if (_devBranches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('No branches linked', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _devBranches.map((branch) {
        return Material(
          color: colorScheme.surface,
          child: InkWell(
            onTap: () => url_launcher.launchUrl(Uri.parse(branch.url), mode: url_launcher.LaunchMode.externalApplication),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_tree, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      branch.name,
                      style: TextStyle(fontSize: 13, color: colorScheme.primary, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (branch.repositoryName != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      branch.repositoryName!,
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCommitsContent(ColorScheme colorScheme) {
    if (_devCommits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('No commits linked', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _devCommits.map((commit) {
        return Material(
          color: colorScheme.surface,
          child: InkWell(
            onTap: () => url_launcher.launchUrl(Uri.parse(commit.url), mode: url_launcher.LaunchMode.externalApplication),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  if (commit.authorAvatarUrl != null)
                    CircleAvatar(
                      radius: 12,
                      backgroundImage: NetworkImage(commit.authorAvatarUrl!),
                    )
                  else
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: colorScheme.primaryContainer,
                      child: Icon(Icons.person, size: 14, color: colorScheme.onPrimaryContainer),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          commit.message ?? commit.id.substring(0, 7),
                          style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${commit.authorName ?? 'Unknown'} • ${commit.id.substring(0, 7)}',
                          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPullRequestsContent(ColorScheme colorScheme) {
    final rows = _buildPullRequestRows();
    final repoName = rows.isNotEmpty
        ? (rows.first.repositoryName != null ? '${rows.first.repositoryName} (GitHub)' : 'GitHub')
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (repoName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: rows.isNotEmpty ? () => url_launcher.launchUrl(Uri.parse(rows.first.url), mode: url_launcher.LaunchMode.externalApplication) : null,
              child: Text(repoName, style: TextStyle(fontSize: 13, color: colorScheme.primary, decoration: TextDecoration.underline)),
            ),
          ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(AppLocalizations.of(context).noPullRequestsLinked, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // Table header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: const BorderRadius.vertical(top: Radius.circular(7))),
                  child: Row(
                    children: [
                      SizedBox(width: 40, child: Text(AppLocalizations.of(context).author, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant))),
                      const SizedBox(width: 8),
                      SizedBox(width: 56, child: Text(AppLocalizations.of(context).id, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant))),
                      const SizedBox(width: 8),
                      Expanded(flex: 3, child: Text(AppLocalizations.of(context).summary, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant))),
                      const SizedBox(width: 8),
                      SizedBox(width: 72, child: Text(AppLocalizations.of(context).status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant))),
                      const SizedBox(width: 8),
                      SizedBox(width: 72, child: Text(AppLocalizations.of(context).updated, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant))),
                    ],
                  ),
                ),
                ...rows.map((row) => _buildPullRequestTableRow(row, colorScheme)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDevTab(String label, String tabKey, bool hasContent) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _selectedDevTab == tabKey;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: selected ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: hasContent ? () {
            setState(() {
              _selectedDevTab = tabKey;
            });
          } : null,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: hasContent
                        ? (selected ? colorScheme.onPrimaryContainer : colorScheme.onSurface)
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                if (hasContent && !selected) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _getTabCount(tabKey).toString(),
                      style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _getTabCount(String tabKey) {
    switch (tabKey) {
      case 'branches':
        return _devBranches.length;
      case 'commits':
        return _devCommits.length;
      case 'pullRequests':
        return _buildPullRequestRows().length;
      default:
        return 0;
    }
  }

  Widget _buildPullRequestTableRow(PullRequestRow row, ColorScheme colorScheme) {
    return Material(
      color: colorScheme.surface,
      child: InkWell(
        onTap: () => url_launcher.launchUrl(Uri.parse(row.url), mode: url_launcher.LaunchMode.externalApplication),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: colorScheme.outlineVariant))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 40,
                child: row.authorAvatarUrl != null && row.authorAvatarUrl!.isNotEmpty
                    ? CircleAvatar(radius: 14, backgroundImage: NetworkImage(row.authorAvatarUrl!), backgroundColor: colorScheme.surfaceContainerHighest)
                    : CircleAvatar(radius: 14, backgroundColor: colorScheme.surfaceContainerHighest, child: Text((row.authorName ?? '?').isNotEmpty ? (row.authorName!.substring(0, 1).toUpperCase()) : '?', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant))),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 56, child: Text(row.id, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colorScheme.primary))),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(row.title, style: TextStyle(fontSize: 13, color: colorScheme.onSurface), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (row.branchText != null && row.branchText!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
                            child: Text(row.branchText!, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: row.status != null && row.status!.isNotEmpty
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: row.status!.toUpperCase() == 'MERGED' ? const Color(0xFF00875A).withValues(alpha: 0.15) : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(row.status!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: row.status!.toUpperCase() == 'MERGED' ? const Color(0xFF00875A) : colorScheme.onSurface)),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 72, child: Text(row.updated ?? '—', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant))),
            ],
          ),
        ),
      ),
    );
  }

  /// Confluence section: list remote links that are Confluence pages (Jira API) and allow adding/linking.
  Widget _buildConfluenceSection() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_loadingConfluenceLinks) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(height: 44, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary))),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_confluenceLinks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(AppLocalizations.of(context).noConfluencePagesLinked, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
          )
        else
          ..._confluenceLinks.map((link) {
            final isDeleting = _deletingConfluenceLinkId == link.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: link.url.isNotEmpty && !isDeleting
                      ? () => url_launcher.launchUrl(Uri.parse(link.url), mode: url_launcher.LaunchMode.externalApplication)
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.article_outlined, color: colorScheme.primary, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(link.title.isNotEmpty ? link.title : 'Confluence Page', style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  if (link.url.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(link.url, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (!isDeleting && link.url.isNotEmpty)
                              TextButton.icon(
                                icon: Icon(Icons.open_in_new, size: 18, color: colorScheme.primary),
                                label: Text(AppLocalizations.of(context).openExternally, style: TextStyle(fontSize: 13, color: colorScheme.primary)),
                                onPressed: () => url_launcher.launchUrl(Uri.parse(link.url), mode: url_launcher.LaunchMode.externalApplication),
                              ),
                            TextButton.icon(
                              icon: isDeleting
                                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary))
                                  : Icon(Icons.link_off, size: 18, color: colorScheme.onSurfaceVariant),
                              label: Text(
                                AppLocalizations.of(context).removeConfluenceLink,
                                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                              ),
                              onPressed: isDeleting ? null : () => _confirmRemoveConfluenceLink(link.id),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showAddConfluenceDialog(context),
            icon: Icon(Icons.add_link, size: 18, color: colorScheme.primary),
            label: Text(AppLocalizations.of(context).linkConfluencePage),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddConfluenceDialog(BuildContext context) async {
    final urlController = TextEditingController();
    final titleController = TextEditingController();
    final screenContext = context;
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return Dialog(
          backgroundColor: colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(AppLocalizations.of(ctx).linkConfluencePage, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colorScheme.onSurface)),
                const SizedBox(height: 16),
                TextField(
                  controller: urlController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(ctx).confluencePageUrl,
                    hintText: AppLocalizations.of(ctx).confluencePageUrlHint,
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 1,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(ctx).confluencePageTitleOptional,
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(AppLocalizations.of(ctx).cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        final url = urlController.text.trim();
                        if (url.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please enter the Confluence page URL')));
                          return;
                        }
                        final api = screenContext.read<JiraApiService>();
                        final err = await api.createConfluenceRemoteLink(
                          widget.issueKey,
                          pageUrl: url,
                          title: titleController.text.trim(),
                        );
                        if (!ctx.mounted) return;
                        if (err != null) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(AppLocalizations.of(ctx).confluenceLinkFailed(err))));
                        } else {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(AppLocalizations.of(ctx).confluenceLinkAdded)));
                          Navigator.of(ctx).pop(true);
                        }
                      },
                      child: Text(AppLocalizations.of(ctx).save),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (added == true && mounted) _loadConfluenceLinks();
  }

  Future<void> _confirmRemoveConfluenceLink(int linkId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).removeConfluenceLink),
        content: Text(AppLocalizations.of(ctx).removeConfluenceLinkConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(AppLocalizations.of(ctx).delete),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    _deleteConfluenceLink(linkId);
  }

  Future<void> _deleteConfluenceLink(int linkId) async {
    setState(() => _deletingConfluenceLinkId = linkId);
    final api = context.read<JiraApiService>();
    final err = await api.deleteRemoteLink(widget.issueKey, linkId);
    if (!mounted) return;
    setState(() => _deletingConfluenceLinkId = null);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).confluenceLinkRemoveFailed(err))));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).confluenceLinkRemoved)));
      _loadConfluenceLinks();
    }
  }

  Future<void> _showAddIssueLinkDialog() async {
    final issueKeyController = TextEditingController();
    final commentController = TextEditingController();
    String? selectedLinkTypeName;
    bool showCommentField = false;

    // Load link types if not already loaded
    if (_linkTypes.isEmpty) {
      setState(() => _loadingLinkTypes = true);
      final api = context.read<JiraApiService>();
      _linkTypes = await api.getIssueLinkTypes();
      if (mounted) setState(() => _loadingLinkTypes = false);
    }

    if (_linkTypes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).noLinkTypesAvailable)),
      );
      return;
    }

    final screenContext = context;
    final linked = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: colorScheme.surface,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(AppLocalizations.of(ctx).addIssueLink, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colorScheme.onSurface)),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(ctx).linkType,
                          border: const OutlineInputBorder(),
                        ),
                        value: selectedLinkTypeName,
                        hint: Text(AppLocalizations.of(ctx).selectLinkType),
                        items: _linkTypes.map((linkType) {
                          return DropdownMenuItem<String>(
                            value: linkType.name,
                            child: Text('${linkType.name} (${linkType.inward} ← → ${linkType.outward})'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedLinkTypeName = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: issueKeyController,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(ctx).issueKey,
                          hintText: AppLocalizations.of(ctx).issueKeyHint,
                          border: const OutlineInputBorder(),
                        ),
                        maxLines: 1,
                        textCapitalization: TextCapitalization.characters,
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () {
                          setDialogState(() {
                            showCommentField = !showCommentField;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Icon(showCommentField ? Icons.expand_less : Icons.expand_more, color: colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Text(AppLocalizations.of(ctx).addComment, style: TextStyle(color: colorScheme.primary, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                      if (showCommentField) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: commentController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text(AppLocalizations.of(ctx).cancel),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () async {
                              final issueKey = issueKeyController.text.trim().toUpperCase();

                              // Validate issue key
                              if (issueKey.isEmpty || !issueKey.contains('-')) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text(AppLocalizations.of(ctx).issueKeyRequired)),
                                );
                                return;
                              }

                              // Check if trying to link to self
                              if (issueKey == widget.issueKey.toUpperCase()) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text(AppLocalizations.of(ctx).cannotLinkToSelf)),
                                );
                                return;
                              }

                              // Validate link type selected
                              if (selectedLinkTypeName == null) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text(AppLocalizations.of(ctx).selectLinkType)),
                                );
                                return;
                              }

                              final api = screenContext.read<JiraApiService>();
                              final comment = commentController.text.trim();
                              final err = await api.linkIssues(
                                linkTypeName: selectedLinkTypeName!,
                                inwardIssueKey: issueKey,
                                outwardIssueKey: widget.issueKey,
                                commentText: comment.isNotEmpty ? comment : null,
                              );

                              if (!ctx.mounted) return;
                              if (err != null) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text(AppLocalizations.of(ctx).issueLinkFailed(err))),
                                );
                              } else {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text(AppLocalizations.of(ctx).issueLinkAdded)),
                                );
                                Navigator.of(ctx).pop(true);
                              }
                            },
                            child: Text(AppLocalizations.of(ctx).linkIssue),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (linked == true && mounted) await _refreshIssue();
  }

  Future<void> _confirmRemoveIssueLink(String linkId, String linkedIssueKey) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).removeIssueLink),
        content: Text(AppLocalizations.of(ctx).removeIssueLinkConfirm(linkedIssueKey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(AppLocalizations.of(ctx).delete),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    _deleteIssueLink(linkId);
  }

  Future<void> _deleteIssueLink(String linkId) async {
    setState(() => _deletingIssueLinkId = linkId);
    final api = context.read<JiraApiService>();
    final err = await api.deleteIssueLink(linkId);
    if (!mounted) return;
    setState(() => _deletingIssueLinkId = null);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).issueLinkRemoveFailed(err))),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).issueLinkRemoved)),
      );
      await _refreshIssue();
    }
  }

  /// Detect "@" mentions in comment text and show user suggestions
  void _onCommentTextChanged() {
    final text = _newCommentController.text;
    final selection = _newCommentController.selection;
    final cursorPosition = selection.baseOffset;
    
    if (cursorPosition < 0 || cursorPosition > text.length) {
      _removeMentionOverlay();
      setState(() => _showMentionSuggestions = false);
      return;
    }
    
    // Find "@" symbol before cursor
    int atIndex = -1;
    for (int i = cursorPosition - 1; i >= 0; i--) {
      if (text[i] == '@') {
        // Check if there's a space or newline before @ (start of mention)
        if (i == 0 || text[i - 1] == ' ' || text[i - 1] == '\n') {
          atIndex = i;
          break;
        }
      } else if (text[i] == ' ' || text[i] == '\n') {
        // Stop if we hit a space/newline before finding @
        break;
      }
    }
    
    if (atIndex >= 0) {
      // Extract query after "@"
      final query = text.substring(atIndex + 1, cursorPosition);
      _mentionStartPosition = atIndex;
      
      // Only show suggestions if query doesn't contain spaces or newlines
      if (!query.contains(' ') && !query.contains('\n')) {
        // Search for users
        _searchMentionUsers(query.trim());
      } else {
        // Query contains space/newline, hide suggestions
        _removeMentionOverlay();
        setState(() => _showMentionSuggestions = false);
      }
    } else {
      _removeMentionOverlay();
      setState(() {
        _showMentionSuggestions = false;
        _mentionStartPosition = -1;
      });
    }
  }

  /// Search for users to mention (debounced)
  void _searchMentionUsers(String query) {
    _mentionSearchTimer?.cancel();
    _mentionSearchTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _loadingMentions = true);
      try {
        final api = context.read<JiraApiService>();
        final users = await api.getAssignableUsers(widget.issueKey, query: query.isEmpty ? null : query);
        if (mounted) {
          setState(() {
            _mentionSuggestions = users;
            _showMentionSuggestions = users.isNotEmpty;
            _loadingMentions = false;
          });
          if (users.isNotEmpty) _showMentionOverlay();
        }
      } catch (e) {
        if (mounted) {
          _removeMentionOverlay();
          setState(() {
            _mentionSuggestions = [];
            _showMentionSuggestions = false;
            _loadingMentions = false;
          });
        }
      }
    });
  }

  /// Insert mention into comment text
  void _insertMention(JiraUser user) {
    if (_mentionStartPosition < 0) return;
    
    final text = _newCommentController.text;
    final cursorPosition = _newCommentController.selection.baseOffset;
    
    // Find end of mention query (space or end of text)
    int endPosition = cursorPosition;
    for (int i = cursorPosition; i < text.length; i++) {
      if (text[i] == ' ' || text[i] == '\n') {
        endPosition = i;
        break;
      }
    }
    if (endPosition == cursorPosition && cursorPosition < text.length) {
      endPosition = text.length;
    }
    
    // Insert display name for the user to see, with invisible marker (accountId + displayName) for ADF when posting
    final before = text.substring(0, _mentionStartPosition);
    final after = text.substring(endPosition);
    const zwsp = '\u200B';
    const sep = '\u200C'; // zero-width non-joiner: separates accountId from displayName in marker
    final mentionText = '@${user.displayName}$zwsp~$zwsp${user.accountId}$sep${user.displayName}$zwsp~$zwsp';
    
    final newText = before + mentionText + (after.isEmpty ? ' ' : after);
    _newCommentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: _mentionStartPosition + mentionText.length + (after.isEmpty ? 1 : 0),
      ),
    );
    
    _hideMentionOverlay();
  }


  Future<void> _onAddComment() async {
    final text = _newCommentController.text.trim();
    if (text.isEmpty) return;
    final api = context.read<JiraApiService>();
    final parentId = _replyToCommentId;
    setState(() => _addingComment = true);
    try {
      final err = await api.addComment(widget.issueKey, text, parentCommentId: parentId);
      if (mounted) {
        if (err != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add comment: $err')));
        } else {
          _newCommentController.clear();
          _removeMentionOverlay();
          setState(() {
            _replyToCommentId = null;
            _showMentionSuggestions = false;
            _mentionStartPosition = -1;
          });
          await _load();
        }
      }
    } finally {
      if (mounted) setState(() => _addingComment = false);
    }
  }

  /// Parent id from Jira comment (for threaded replies).
  static String? _parentCommentId(Map<String, dynamic> c) {
    final p = c['parent'];
    if (p is Map) return (p['id'] as dynamic)?.toString();
    return null;
  }

  /// Build comment list in tree order: roots first, then replies nested by depth.
  List<Widget> _commentTreeWidgets() {
    final list = _comments.whereType<Map<String, dynamic>>().toList();
    final parentIdMap = <String, List<Map<String, dynamic>>>{};
    for (final c in list) {
      final pid = _parentCommentId(c);
      if (pid != null && pid.isNotEmpty) {
        parentIdMap.putIfAbsent(pid, () => []).add(c);
      }
    }
    for (final ls in parentIdMap.values) {
      ls.sort((a, b) => (a['created']?.toString() ?? '').compareTo(b['created']?.toString() ?? ''));
    }
    final roots = list.where((c) {
      final pid = _parentCommentId(c);
      return pid == null || pid.isEmpty;
    }).toList();
    roots.sort((a, b) => (a['created']?.toString() ?? '').compareTo(b['created']?.toString() ?? ''));
    return roots.expand((root) => _commentCardWithReplies(root, 0, parentIdMap)).toList();
  }

  Iterable<Widget> _commentCardWithReplies(Map<String, dynamic> root, int depth, Map<String, List<Map<String, dynamic>>> parentIdMap) sync* {
    yield _buildCommentCard(root, depth: depth);
    final id = root['id']?.toString();
    if (id == null) return;
    final children = parentIdMap[id] ?? [];
    for (final child in children) {
      yield* _commentCardWithReplies(child, depth + 1, parentIdMap);
    }
  }

  Widget _buildCommentCard(Map<String, dynamic> map, {int depth = 0}) {
    final body = map['body'] ?? map['renderedBody'] ?? '';
    final authorMap = map['author'];
    final author = authorMap is Map<String, dynamic> ? JiraUser.fromJson(authorMap) : null;
    final authorName = author?.displayName ?? stringFromJson(authorMap is Map ? authorMap['displayName'] : null) ?? 'Unknown';
    final created = stringFromJson(map['created']) ?? '';
    final commentId = map['id']?.toString();
    final isOwnComment = _currentUser != null && author != null && _currentUser!.accountId == author.accountId;
    final attachments = _issue?.fields.attachment ?? [];
    final colorScheme = Theme.of(context).colorScheme;
    final card = Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: colorScheme.primary,
                  backgroundImage: author?.avatar48 != null ? NetworkImage(author!.avatar48!) : null,
                  child: author?.avatar48 == null
                      ? Text(
                          authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                          style: TextStyle(color: colorScheme.onPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(authorName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
                      Text(_formatRelativeDate(created), style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _CommentBodyWidget(
              body: body,
              attachments: attachments,
              loadedImageBytes: _loadedImageBytes,
              onNeedLoadImage: _loadDescriptionImage,
              onAttachmentPress: _onAttachmentPress,
              onMentionPress: _onMentionPress,
            ),
            if (commentId != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _replyToCommentId = commentId),
                    icon: const Icon(Icons.reply, size: 18),
                    label: const Text('Reply'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _onShareComment(commentId),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Share'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                  if (isOwnComment) ...[
                    TextButton.icon(
                      onPressed: () => _onEditComment(map),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit'),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _onDeleteComment(commentId),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.error,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
    if (depth <= 0) return card;
    return Padding(padding: EdgeInsets.only(left: depth * 24), child: card);
  }

  void _onShareComment(String commentId) {
    final base = context.read<JiraApiService>().jiraBaseUrl;
    if (base == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot build link')));
      return;
    }
    final url = '$base/browse/${widget.issueKey}?focusedCommentId=$commentId';
    Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comment link copied to clipboard')));
    }
  }

  String? _getIssueUrl() {
    final base = context.read<JiraApiService>().jiraBaseUrl;
    if (base == null) return null;
    return '$base/browse/${widget.issueKey}';
  }

  void _copyIssueLink() {
    final url = _getIssueUrl();
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot build link')));
      return;
    }
    Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).linkCopiedToClipboard)));
    }
  }

  Future<void> _openIssueInBrowser() async {
    final url = _getIssueUrl();
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot build link')));
      return;
    }
    final uri = Uri.parse(url);
    if (await url_launcher.canLaunchUrl(uri)) {
      await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot open link')));
    }
  }

  Future<void> _onEditComment(Map<String, dynamic> map) async {
    final commentId = map['id']?.toString();
    if (commentId == null) return;
    final body = map['body'] ?? map['renderedBody'] ?? '';
    final currentText = _plainText(body);
    final controller = TextEditingController(text: currentText);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit comment'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          maxLines: 5,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(AppLocalizations.of(context).save),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    final api = context.read<JiraApiService>();
    final err = await api.updateComment(widget.issueKey, commentId, result);
    if (mounted) {
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $err')));
      } else {
        await _load();
      }
    }
  }

  Future<void> _onDeleteComment(String commentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove comment'),
        content: const Text('Are you sure you want to remove this comment?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final api = context.read<JiraApiService>();
    final err = await api.deleteComment(widget.issueKey, commentId);
    if (mounted) {
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to remove: $err')));
      } else {
        await _load();
      }
    }
  }

  String _plainText(dynamic content) {
    if (content is String) {
      return content.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    if (content is Map) {
      final adf = _extractTextFromAdf(content);
      if (adf.isNotEmpty) return adf.trim();
    }
    final s = stringFromJson(content);
    if (s != null && s.isNotEmpty) return s;
    return content?.toString() ?? '';
  }

  /// Extract plain text from Atlassian Document Format (ADF) comment/description body.
  String _extractTextFromAdf(dynamic node) {
    if (node == null) return '';
    if (node is String) return node;
    if (node is Map) {
      final text = node['text'];
      if (text is String) return text;
      // ADF inlineCard / blockCard: show URL
      final type = node['type'];
      if (type == 'inlineCard' || type == 'blockCard') {
        final attrs = node['attrs'];
        if (attrs is Map) {
          final url = attrs['url'];
          if (url is String) return url;
        }
      }
      final content = node['content'];
      if (content is List) {
        return content.map((c) => _extractTextFromAdf(c)).join('');
      }
    }
    if (node is List) {
      return node.map((e) => _extractTextFromAdf(e)).join('');
    }
    return '';
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.month}/${d.day}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  /// Relative date like reference: "Just now", "5m ago", "1h ago", "2d ago", or full date.
  String _formatRelativeDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(d);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${d.month}/${d.day}/${d.year}';
    } catch (_) {
      return iso;
    }
  }
}

/// Renders comment body: string or ADF (paragraphs, links, mentions, mediaSingle/mediaInline as tappable attachments). Same as reference IssueCommentsSection renderCommentText.
class _CommentBodyWidget extends StatelessWidget {
  final dynamic body;
  final List<JiraAttachment> attachments;
  final Map<String, Uint8List>? loadedImageBytes;
  final void Function(JiraAttachment)? onNeedLoadImage;
  final void Function(JiraAttachment) onAttachmentPress;
  final void Function(String accountId, String displayName)? onMentionPress;

  const _CommentBodyWidget({
    required this.body,
    required this.attachments,
    this.loadedImageBytes,
    this.onNeedLoadImage,
    required this.onAttachmentPress,
    this.onMentionPress,
  });

  static String _plainText(dynamic content) {
    if (content == null) return '';
    if (content is String) return content.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (content is Map) {
      final text = content['text'];
      if (text is String) return text;
      final type = content['type'];
      if (type == 'mention') {
        final attrs = content['attrs'];
        if (attrs is Map) {
          final t = attrs['text'];
          if (t != null) return t.toString().trim();
          final id = attrs['id'];
          if (id != null) return '@${id.toString()}';
        }
        return '@user';
      }
      if (type == 'inlineCard' || type == 'blockCard') {
        final url = (content['attrs'] is Map) ? (content['attrs'] as Map)['url'] : null;
        if (url is String) return url;
      }
      final list = content['content'];
      if (list is List) return list.map((c) => _plainText(c)).join('');
    }
    if (content is List) return content.map((e) => _plainText(e)).join('');
    return content.toString();
  }

  /// Extract display text for a mention node: attrs.text (e.g. "@Sang Em Lam Van") or "@" + attrs.id.
  static String _mentionText(dynamic node) {
    if (node is! Map) return '@user';
    final attrs = node['attrs'];
    if (attrs is! Map) return '@user';
    final t = attrs['text'];
    if (t != null && t.toString().trim().isNotEmpty) return t.toString().trim();
    final id = attrs['id'];
    if (id != null) return id.toString();
    return '@user';
  }

  static JiraAttachment? _resolveAttachment(dynamic node, List<JiraAttachment> attachments) {
    if (node is! Map) return null;
    final attrs = node['attrs'];
    if (attrs is! Map) return null;
    final id = attrs['id']?.toString();
    final url = attrs['url'] as String?;
    final alt = attrs['alt'] as String?;
    if (id != null && id.isNotEmpty) {
      final found = attachments.cast<JiraAttachment?>().firstWhere(
        (a) => a?.id == id,
        orElse: () => null,
      );
      if (found != null) return found;
    }
    // Fallback: match by filename (alt) when id not found or comment ADF uses alt only
    if (alt != null && alt.isNotEmpty) {
      for (final a in attachments) {
        if (a.filename == alt || (a.filename.isNotEmpty && a.filename.contains(alt))) {
          return a;
        }
      }
    }
    if (url != null && url.isNotEmpty && (alt != null || id != null)) {
      return JiraAttachment(id: id ?? 'inline', filename: alt ?? 'Attachment', mimeType: 'application/octet-stream', content: url);
    }
    return null;
  }

  static String _fileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return '🖼️';
    if (mimeType.startsWith('video/')) return '🎥';
    if (mimeType == 'application/pdf') return '📄';
    return '📎';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (body is String) {
      return _LinkableText(body as String, style: TextStyle(fontSize: 14, height: 1.5, color: colorScheme.onSurface));
    }
    if (body is Map) {
      final content = body['content'];
      if (content is! List || content.isEmpty) {
        return _LinkableText(_plainText(body), style: TextStyle(fontSize: 14, height: 1.5, color: colorScheme.onSurface));
      }
      final children = <Widget>[];
      for (final node in content) {
        if (node is! Map) continue;
        final type = node['type'];
        if (type == 'paragraph') {
          final paragraphContent = node['content'];
          if (paragraphContent is List && paragraphContent.isNotEmpty) {
            final row = <Widget>[];
            for (final item in paragraphContent) {
              if (item is! Map) continue;
              final itemType = item['type'];
              if (itemType == 'text') {
                final text = item['text']?.toString() ?? '';
                final marks = item['marks'] as List?;
                final linkMark = marks?.cast<Map?>().firstWhere((m) => m != null && m['type'] == 'link', orElse: () => null);
                if (linkMark != null && linkMark['attrs'] is Map) {
                  final href = (linkMark['attrs'] as Map)['href']?.toString();
                  if (href != null && href.isNotEmpty) {
                    row.add(Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: InkWell(
                        onTap: () async {
                          final uri = Uri.tryParse(href);
                          if (uri != null && await url_launcher.canLaunchUrl(uri)) {
                            await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication);
                          }
                        },
                        borderRadius: BorderRadius.circular(2),
                        child: Text(
                          text.isEmpty ? href : text,
                          style: TextStyle(fontSize: 14, height: 1.5, color: colorScheme.primary, decoration: TextDecoration.underline),
                        ),
                      ),
                    ));
                    continue;
                  }
                }
                TextStyle textStyle = TextStyle(fontSize: 14, height: 1.5, color: colorScheme.onSurface);
                if (marks != null) {
                  for (final m in marks) {
                    if (m is Map) {
                      if (m['type'] == 'strong') textStyle = textStyle.copyWith(fontWeight: FontWeight.bold);
                      else if (m['type'] == 'em') textStyle = textStyle.copyWith(fontStyle: FontStyle.italic);
                      else if (m['type'] == 'code') textStyle = textStyle.copyWith(fontFamily: 'monospace', backgroundColor: colorScheme.surfaceContainerHighest);
                    }
                  }
                }
                final segment = _plainText(item);
                if (segment.isNotEmpty) {
                  row.add(_LinkableText(segment, style: textStyle));
                }
              } else if (itemType == 'mention') {
                final mentionLabel = _mentionText(item);
                final displayName = mentionLabel.startsWith('@') ? mentionLabel : '@$mentionLabel';
                String accountId = '';
                final attrs = item['attrs'];
                if (attrs is Map) {
                  final id = attrs['id'];
                  accountId = id?.toString() ?? '';
                }
                final chip = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5), width: 1),
                  ),
                  child: Text(
                    displayName,
                    style: TextStyle(fontSize: 13, color: colorScheme.primary, fontWeight: FontWeight.w500),
                  ),
                );
                row.add(Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: onMentionPress != null && accountId.isNotEmpty
                      ? InkWell(
                          onTap: () => onMentionPress?.call(accountId, displayName.replaceFirst('@', '').trim()),
                          borderRadius: BorderRadius.circular(4),
                          child: chip,
                        )
                      : chip,
                ));
              } else if (itemType == 'inlineCard') {
                final url = (item['attrs'] is Map) ? (item['attrs'] as Map)['url']?.toString() : null;
                if (url != null) {
                  row.add(Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InkWell(
                      onTap: () async {
                        final uri = Uri.tryParse(url);
                        if (uri != null && await url_launcher.canLaunchUrl(uri)) {
                          await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication);
                        }
                      },
                      borderRadius: BorderRadius.circular(2),
                      child: Text(url, style: TextStyle(fontSize: 14, height: 1.5, color: colorScheme.primary, decoration: TextDecoration.underline)),
                    ),
                  ));
                }
              } else if (itemType == 'mediaInline') {
                final att = _resolveAttachment(item, attachments);
                if (att != null) {
                  // Inline preview: image as small thumbnail, other files as icon + name
                  final isImage = att.mimeType.startsWith('image/');
                  final bytes = loadedImageBytes ?? {};
                  final onLoad = onNeedLoadImage;
                  if (isImage && onLoad != null) {
                    row.add(Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 4),
                      child: _InlineCommentThumbnail(
                        attachment: att,
                        loadedBytes: bytes[att.id],
                        onNeedLoad: onLoad,
                        onTap: () => onAttachmentPress(att),
                      ),
                    ));
                  } else {
                    row.add(Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () => onAttachmentPress(att),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFFF4F5F7), borderRadius: BorderRadius.circular(4)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_fileIcon(att.mimeType), style: const TextStyle(fontSize: 16)),
                              const SizedBox(width: 4),
                              Text(att.filename, style: const TextStyle(fontSize: 13, color: Color(0xFF0052CC), fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ),
                    ));
                  }
                }
              }
            }
            if (row.isNotEmpty) {
              children.add(Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 0,
                  runSpacing: 4,
                  children: row,
                ),
              ));
            }
          } else {
            final text = _plainText(paragraphContent is List ? {'content': paragraphContent} : node);
            if (text.isNotEmpty) {
              children.add(Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _LinkableText(text, style: TextStyle(fontSize: 14, height: 1.5, color: colorScheme.onSurface)),
              ));
            }
          }
        } else if (type == 'mediaSingle' && node['content'] is List) {
          final bytes = loadedImageBytes ?? {};
          final onLoad = onNeedLoadImage;
          final contentList = node['content'] as List;
          // ADF: content may contain { type: 'media', attrs: { id, ... } }
          for (final media in contentList) {
            final mediaNode = media is Map && media['type'] == 'media' ? media : media;
            final att = _resolveAttachment(mediaNode, attachments);
            if (att != null) {
              if (onLoad != null && att.mimeType.startsWith('image/')) {
                children.add(Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: _InlineDescriptionMedia(
                    attachment: att,
                    loadedBytes: bytes[att.id],
                    onNeedLoad: onLoad,
                    onTap: () => onAttachmentPress(att),
                  ),
                ));
              } else {
                children.add(Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: InkWell(
                    onTap: () => onAttachmentPress(att),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFDFE1E6)),
                      ),
                      child: Row(
                        children: [
                          Text(_fileIcon(att.mimeType), style: const TextStyle(fontSize: 32)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(att.filename, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF172B4D)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                if (att.size != null)
                                  Text('${(att.size! / 1024).toStringAsFixed(1)} KB', style: const TextStyle(fontSize: 12, color: Color(0xFF7A869A))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ));
              }
            }
          }
        } else if (type == 'mediaGroup' && node['content'] is List) {
          final bytes = loadedImageBytes ?? {};
          final onLoad = onNeedLoadImage;
          final group = <Widget>[];
          final contentList = node['content'] as List;
          for (final media in contentList) {
            final mediaNode = media is Map && media['type'] == 'media' ? media : media;
            final att = _resolveAttachment(mediaNode, attachments);
            if (att != null) {
              if (onLoad != null && att.mimeType.startsWith('image/')) {
                group.add(Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: _InlineDescriptionMedia(
                    attachment: att,
                    loadedBytes: bytes[att.id],
                    onNeedLoad: onLoad,
                    onTap: () => onAttachmentPress(att),
                  ),
                ));
              } else {
                group.add(Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: InkWell(
                    onTap: () => onAttachmentPress(att),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFDFE1E6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_fileIcon(att.mimeType), style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 8),
                          Text(att.filename, style: const TextStyle(fontSize: 13, color: Color(0xFF172B4D)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ),
                ));
              }
            }
          }
          if (group.isNotEmpty) {
            children.add(Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Wrap(children: group),
            ));
          }
        } else if (type == 'codeBlock' && node['content'] is List) {
          final code = (node['content'] as List).map((c) => _plainText(c)).join('');
          children.add(Container(
            margin: const EdgeInsets.only(top: 4, bottom: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F7),
              borderRadius: BorderRadius.circular(4),
              border: Border(left: BorderSide(color: const Color(0xFFDFE1E6), width: 3)),
            ),
            child: SelectableText(code, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Color(0xFF172B4D))),
          ));
        }
      }
      if (children.isEmpty) {
        return _LinkableText(_plainText(body), style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF42526E)));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
    }
    return _LinkableText(_plainText(body), style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF42526E)));
  }
}

/// Full-screen rich text editor for description (QuillEditor + toolbar). Converts ADF ↔ Quill Delta.
class _DescriptionEditPage extends StatefulWidget {
  final dynamic initialDescription;
  final List<JiraAttachment> attachments;
  final Map<String, Uint8List> loadedImageBytes;

  const _DescriptionEditPage({
    required this.initialDescription,
    required this.attachments,
    required this.loadedImageBytes,
  });

  @override
  State<_DescriptionEditPage> createState() => _DescriptionEditPageState();
}

class _DescriptionEditPageState extends State<_DescriptionEditPage> {
  late quill.QuillController _controller;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final Map<String, Uint8List> _previewBytes = {};
  JiraAttachment? _previewAttachment;

  Map<String, Uint8List> get _mergedImageBytes => {...widget.loadedImageBytes, ..._previewBytes};

  @override
  void initState() {
    super.initState();
    final ops = adfToQuillOps(widget.initialDescription);
    quill.Document doc;
    try {
      doc = quill.Document.fromJson(ops);
    } catch (_) {
      doc = quill.Document.fromJson([{'insert': '\n'}]);
    }
    _controller = quill.QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _loadPreviewImage(JiraAttachment att) {
    if (_previewBytes.containsKey(att.id)) return;
    context.read<JiraApiService>().fetchAttachmentBytes(att.content).then((bytes) {
      if (mounted && bytes != null) setState(() => _previewBytes[att.id] = Uint8List.fromList(bytes));
    });
  }

  void _onPreviewAttachmentPress(JiraAttachment att) {
    setState(() => _previewAttachment = att);
    if (att.mimeType.startsWith('image/')) _loadPreviewImage(att);
  }

  void _save() {
    final delta = _controller.document.toDelta();
    final ops = delta.toJson();
    final adf = quillOpsToAdf(ops);
    Navigator.of(context).pop<Map<String, dynamic>>(adf);
  }

  Widget _buildPreviewOverlay() {
    final att = _previewAttachment!;
    final isImage = att.mimeType.startsWith('image/');
    final bytes = _mergedImageBytes[att.id];
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => setState(() => _previewAttachment = null),
              ),
            ),
            Expanded(
              child: Center(
                child: isImage
                    ? (bytes != null
                        ? InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain))
                        : const CircularProgressIndicator(color: Colors.white))
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_fileIconForEdit(att.mimeType), style: const TextStyle(fontSize: 48)),
                            const SizedBox(height: 16),
                            Text(att.filename, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: () async {
                                final api = context.read<JiraApiService>();
                                final data = await api.fetchAttachmentBytes(att.content);
                                if (data == null || !mounted) return;
                                final dir = await Directory.systemTemp.createTemp();
                                final ext = att.filename.contains('.') ? att.filename.split('.').last : 'bin';
                                final file = File('${dir.path}/jira_${att.id}.$ext');
                                await file.writeAsBytes(data);
                                OpenFile.open(file.path);
                                setState(() => _previewAttachment = null);
                              },
                              icon: const Icon(Icons.open_in_new),
                              label: Text(AppLocalizations.of(context).open),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fileIconForEdit(String mimeType) {
    if (mimeType.startsWith('image/')) return '🖼️';
    if (mimeType.startsWith('video/')) return '🎥';
    if (mimeType == 'application/pdf') return '📄';
    return '📎';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Description'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(AppLocalizations.of(context).save),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
        children: [
          // Preview: current description with format and inline images (read-only)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220),
            color: const Color(0xFFF4F5F7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text('Preview', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: const Color(0xFF5E6C84), fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _DescriptionBodyWidget(
                      description: widget.initialDescription,
                      attachments: widget.attachments,
                      loadedImageBytes: _mergedImageBytes,
                      onAttachmentPress: _onPreviewAttachmentPress,
                      onNeedLoadImage: _loadPreviewImage,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 56,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: quill.QuillSimpleToolbar(
                controller: _controller,
                config: const quill.QuillSimpleToolbarConfig(
                  showUndo: true,
                  showRedo: true,
                  showBoldButton: true,
                  showItalicButton: true,
                  showUnderLineButton: true,
                  showStrikeThrough: false,
                  showInlineCode: true,
                  showLink: true,
                  showHeaderStyle: true,
                  showListNumbers: true,
                  showListBullets: true,
                  showListCheck: false,
                  showCodeBlock: true,
                  showIndent: false,
                  showDividers: false,
                  showSmallButton: false,
                  showSubscript: false,
                  showSuperscript: false,
                  showFontFamily: false,
                  showFontSize: false,
                  showColorButton: false,
                  showBackgroundColorButton: false,
                  showClearFormat: true,
                  showAlignmentButtons: false,
                ),
              ),
            ),
          ),
          Expanded(
            child: quill.QuillEditor.basic(
              controller: _controller,
              config: quill.QuillEditorConfig(
                placeholder: 'Add description...',
                padding: const EdgeInsets.all(16),
              ),
              focusNode: _focusNode,
              scrollController: _scrollController,
            ),
          ),
        ],
      ),
          if (_previewAttachment != null) _buildPreviewOverlay(),
        ],
      ),
    );
  }
}

/// Renders issue description: string or ADF with formatting, clickable links, and inline image/video preview. Matches reference IssueDescriptionCard.
class _DescriptionBodyWidget extends StatelessWidget {
  final dynamic description;
  final List<JiraAttachment> attachments;
  final Map<String, Uint8List> loadedImageBytes;
  final void Function(JiraAttachment) onAttachmentPress;
  final void Function(JiraAttachment) onNeedLoadImage;

  const _DescriptionBodyWidget({
    required this.description,
    required this.attachments,
    required this.loadedImageBytes,
    required this.onAttachmentPress,
    required this.onNeedLoadImage,
  });

  static JiraAttachment? _resolveByAlt(List<JiraAttachment> attachments, String altText) {
    if (altText.isEmpty) return null;
    for (final a in attachments) {
      if (a.filename == altText || a.filename.contains(altText) || altText.contains(a.filename)) return a;
    }
    return null;
  }

  static String _plainText(dynamic content) {
    if (content == null) return '';
    if (content is String) return content.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (content is Map) {
      final text = content['text'];
      if (text is String) return text;
      final list = content['content'];
      if (list is List) return list.map((c) => _plainText(c)).join('');
    }
    if (content is List) return content.map((e) => _plainText(e)).join('');
    return content.toString();
  }

  static String _mentionText(dynamic node) {
    if (node is! Map) return '@user';
    final attrs = node['attrs'];
    if (attrs is! Map) return '@user';
    final t = attrs['text'];
    if (t != null && t.toString().trim().isNotEmpty) return t.toString().trim();
    final id = attrs['id'];
    if (id != null) return id.toString();
    return '@user';
  }

  Widget _renderInlineContent(BuildContext context, List<dynamic> content, [TextStyle? baseStyle]) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = baseStyle ?? TextStyle(fontSize: 14, height: 1.5, color: colorScheme.onSurface);
    final row = <Widget>[];
    for (var i = 0; i < content.length; i++) {
      final item = content[i];
      if (item is! Map) continue;
      final itemType = item['type'];
      if (itemType == 'text') {
        final text = item['text']?.toString() ?? '';
        final marks = item['marks'] as List?;
        final linkMark = marks?.cast<Map?>().firstWhere((m) => m != null && m['type'] == 'link', orElse: () => null);
        if (linkMark != null && linkMark['attrs'] is Map) {
          final href = (linkMark['attrs'] as Map)['href']?.toString();
          if (href != null && href.isNotEmpty) {
            row.add(Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                onTap: () async {
                  final uri = Uri.tryParse(href);
                  if (uri != null && await url_launcher.canLaunchUrl(uri)) {
                    await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication);
                  }
                },
                borderRadius: BorderRadius.circular(2),
                child: Text(text.isEmpty ? href : text, style: style.copyWith(color: colorScheme.primary, decoration: TextDecoration.underline)),
              ),
            ));
            continue;
          }
        }
        TextStyle s = style;
        if (marks != null) {
          for (final m in marks) {
            if (m is Map) {
              if (m['type'] == 'strong') s = s.copyWith(fontWeight: FontWeight.bold);
              else if (m['type'] == 'em') s = s.copyWith(fontStyle: FontStyle.italic);
              else if (m['type'] == 'code') s = s.copyWith(fontFamily: 'monospace', backgroundColor: colorScheme.surfaceContainerHighest);
            }
          }
        }
        if (text.isNotEmpty) row.add(_LinkableText(text, style: s));
      } else if (itemType == 'mention') {
        final displayName = _mentionText(item);
        final name = displayName.startsWith('@') ? displayName : '@$displayName';
        row.add(Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5), width: 1),
            ),
            child: Text(name, style: TextStyle(fontSize: 13, color: colorScheme.primary, fontWeight: FontWeight.w500)),
          ),
        ));
      } else if (itemType == 'inlineCard') {
        final url = (item['attrs'] is Map) ? (item['attrs'] as Map)['url']?.toString() : null;
        if (url != null) {
          row.add(Padding(
            padding: const EdgeInsets.only(right: 4),
            child: InkWell(
              onTap: () async {
                final uri = Uri.tryParse(url);
                if (uri != null && await url_launcher.canLaunchUrl(uri)) {
                  await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication);
                }
              },
              borderRadius: BorderRadius.circular(2),
              child: Text(url, style: style.copyWith(color: colorScheme.primary, decoration: TextDecoration.underline)),
            ),
          ));
        }
      } else if (itemType == 'hardBreak') {
        row.add(Text('\n', style: TextStyle(fontSize: 14, height: 1.5, color: colorScheme.onSurface)));
      }
    }
    if (row.isEmpty) return const SizedBox.shrink();
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 0, runSpacing: 4, children: row);
  }

  Widget _renderList(BuildContext context, dynamic listNode, int listIndex) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = listNode is Map ? listNode['content'] as List? : null;
    if (content == null) return const SizedBox.shrink();
    final isOrdered = listNode is Map && listNode['type'] == 'orderedList';
    final start = (listNode is Map && listNode['attrs'] is Map) ? intFromJson((listNode['attrs'] as Map)['order']) ?? 1 : 1;
    final items = <Widget>[];
    for (var i = 0; i < content.length; i++) {
      final listItem = content[i];
      if (listItem is! Map || listItem['type'] != 'listItem') continue;
      final bullet = isOrdered ? '${start + i}. ' : '• ';
      final itemContent = listItem['content'] as List?;
      if (itemContent != null) {
        for (final node in itemContent) {
          if (node is Map && node['type'] == 'paragraph' && node['content'] != null) {
            items.add(Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 24, child: Text(bullet, style: TextStyle(fontSize: 14, color: colorScheme.onSurface))),
                  Expanded(child: _renderInlineContent(context, node['content'] as List)),
                ],
              ),
            ));
          } else if (node is Map && (node['type'] == 'bulletList' || node['type'] == 'orderedList')) {
            items.add(Padding(padding: const EdgeInsets.only(left: 20), child: _renderList(context, node, i)));
          }
        }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: items);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (description == null) {
      return Text('No description', style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant, height: 1.5));
    }
    if (description is String) {
      final s = (description as String).trim();
      if (s.isEmpty) return Text('No description', style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant, height: 1.5));
      return _LinkableText(s, style: TextStyle(fontSize: 15, color: colorScheme.onSurface, height: 1.5));
    }
    if (description is! Map) return Text('No description', style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant, height: 1.5));
    final content = description['content'];
    if (content is! List || content.isEmpty) {
      final plain = _plainText(description);
      if (plain.trim().isEmpty) return Text('No description', style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant, height: 1.5));
      return _LinkableText(plain, style: TextStyle(fontSize: 15, color: colorScheme.onSurface, height: 1.5));
    }
    final children = <Widget>[];
    for (final node in content) {
      if (node is! Map) continue;
      final type = node['type'];
      if (type == 'paragraph') {
        final paragraphContent = node['content'];
        if (paragraphContent is List && paragraphContent.isNotEmpty) {
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _renderInlineContent(context, paragraphContent),
          ));
        } else {
          final text = _plainText(paragraphContent is List ? {'content': paragraphContent} : node);
          if (text.isNotEmpty) {
            children.add(Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LinkableText(text, style: TextStyle(fontSize: 15, color: colorScheme.onSurface, height: 1.5)),
            ));
          }
        }
      } else if (type == 'heading' && node['content'] is List) {
        final level = (node['attrs'] is Map) ? intFromJson((node['attrs'] as Map)['level']) ?? 1 : 1;
        TextStyle headingStyle = TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface);
        if (level == 1) headingStyle = headingStyle.copyWith(fontSize: 24);
        else if (level == 2) headingStyle = headingStyle.copyWith(fontSize: 20);
        else if (level == 3) headingStyle = headingStyle.copyWith(fontSize: 18);
        else if (level == 4) headingStyle = headingStyle.copyWith(fontSize: 16);
        else headingStyle = headingStyle.copyWith(fontSize: 14);
        children.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: _renderInlineContent(context, node['content'] as List, headingStyle),
        ));
      } else if (type == 'bulletList' || type == 'orderedList') {
        children.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: _renderList(context, node, 0)));
      } else if (type == 'codeBlock' && node['content'] is List) {
        final code = (node['content'] as List).map((c) => _plainText(c)).join('');
        children.add(Container(
          margin: const EdgeInsets.only(top: 4, bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            border: Border(left: BorderSide(color: colorScheme.outline, width: 3)),
          ),
          child: SelectableText(code, style: TextStyle(fontSize: 13, fontFamily: 'monospace', color: colorScheme.onSurface)),
        ));
      } else if (type == 'mediaSingle' && node['content'] is List) {
        for (final media in node['content'] as List) {
          if (media is! Map) continue;
          final attrs = media['attrs'];
          final alt = attrs is Map ? (attrs['alt'] ?? attrs['id']?.toString() ?? '')?.toString() ?? '' : '';
          JiraAttachment? att = _CommentBodyWidget._resolveAttachment(media, attachments);
          if (att == null && alt.isNotEmpty) att = _resolveByAlt(attachments, alt);
          final attachment = att;
          if (attachment != null) {
            children.add(Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: _InlineDescriptionMedia(
                attachment: attachment,
                loadedBytes: loadedImageBytes[attachment.id],
                onNeedLoad: onNeedLoadImage,
                onTap: () => onAttachmentPress(attachment),
              ),
            ));
          }
        }
      } else if (type == 'mediaGroup' && node['content'] is List) {
        final group = <Widget>[];
        for (final media in node['content'] as List) {
          if (media is! Map) continue;
          final attrs = media['attrs'];
          final alt = attrs is Map ? (attrs['alt'] ?? attrs['id']?.toString() ?? '')?.toString() ?? '' : '';
          JiraAttachment? att = _CommentBodyWidget._resolveAttachment(media, attachments);
          if (att == null && alt.isNotEmpty) att = _resolveByAlt(attachments, alt);
          final attachment = att;
          if (attachment != null) {
            group.add(Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: _InlineDescriptionMedia(
                attachment: attachment,
                loadedBytes: loadedImageBytes[attachment.id],
                onNeedLoad: onNeedLoadImage,
                onTap: () => onAttachmentPress(attachment),
              ),
            ));
          }
        }
        if (group.isNotEmpty) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Wrap(children: group),
          ));
        }
      }
    }
    if (children.isEmpty) {
      final plain = _plainText(description);
      if (plain.trim().isEmpty) return const Text('No description', style: TextStyle(fontSize: 15, color: Color(0xFF8993A4), height: 1.5));
      return _LinkableText(plain, style: const TextStyle(fontSize: 15, color: Color(0xFF172B4D), height: 1.5));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Small inline image thumbnail in comments (e.g. mediaInline); loads on demand, tap opens full preview.
class _InlineCommentThumbnail extends StatefulWidget {
  final JiraAttachment attachment;
  final Uint8List? loadedBytes;
  final void Function(JiraAttachment) onNeedLoad;
  final VoidCallback onTap;

  const _InlineCommentThumbnail({
    required this.attachment,
    required this.loadedBytes,
    required this.onNeedLoad,
    required this.onTap,
  });

  @override
  State<_InlineCommentThumbnail> createState() => _InlineCommentThumbnailState();
}

class _InlineCommentThumbnailState extends State<_InlineCommentThumbnail> {
  bool _loadStarted = false;

  @override
  void initState() {
    super.initState();
    if (widget.loadedBytes == null && !_loadStarted) {
      _loadStarted = true;
      widget.onNeedLoad(widget.attachment);
    }
  }

  @override
  void didUpdateWidget(covariant _InlineCommentThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loadedBytes == null && !_loadStarted) {
      _loadStarted = true;
      widget.onNeedLoad(widget.attachment);
    }
  }

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F5F7),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFDFE1E6)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: widget.loadedBytes != null
                ? Image.memory(widget.loadedBytes!, fit: BoxFit.cover)
                : const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0052CC)),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Inline image or video placeholder in description; tap to open full preview.
class _InlineDescriptionMedia extends StatefulWidget {
  final JiraAttachment attachment;
  final Uint8List? loadedBytes;
  final void Function(JiraAttachment) onNeedLoad;
  final VoidCallback onTap;

  const _InlineDescriptionMedia({
    required this.attachment,
    required this.loadedBytes,
    required this.onNeedLoad,
    required this.onTap,
  });

  @override
  State<_InlineDescriptionMedia> createState() => _InlineDescriptionMediaState();
}

class _InlineDescriptionMediaState extends State<_InlineDescriptionMedia> {
  bool _loadStarted = false;

  @override
  void initState() {
    super.initState();
    if (widget.attachment.mimeType.startsWith('image/') && widget.loadedBytes == null && !_loadStarted) {
      _loadStarted = true;
      widget.onNeedLoad(widget.attachment);
    }
  }

  @override
  void didUpdateWidget(covariant _InlineDescriptionMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.attachment.mimeType.startsWith('image/') && widget.loadedBytes == null && !_loadStarted) {
      _loadStarted = true;
      widget.onNeedLoad(widget.attachment);
    }
  }

  @override
  Widget build(BuildContext context) {
    final att = widget.attachment;
    final isImage = att.mimeType.startsWith('image/');
    final isVideo = att.mimeType.startsWith('video/');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF4F5F7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDFE1E6)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: isImage
                ? SizedBox(
                    width: double.infinity,
                    height: 200,
                    child: widget.loadedBytes != null
                        ? Image.memory(widget.loadedBytes!, fit: BoxFit.contain)
                        : Stack(
                            alignment: Alignment.center,
                            children: [
                              const Center(child: CircularProgressIndicator(color: Color(0xFF0052CC))),
                            ],
                          ),
                  )
                : isVideo
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🎥', style: TextStyle(fontSize: 40)),
                            const SizedBox(height: 8),
                            Text(att.filename, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF172B4D)), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            const Text('Tap to play', style: TextStyle(fontSize: 12, color: Color(0xFF7A869A))),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Text('📎', style: TextStyle(fontSize: 24)),
                            const SizedBox(width: 12),
                            Expanded(child: Text(att.filename, style: const TextStyle(fontSize: 14, color: Color(0xFF172B4D)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
        ),
      ),
    ),
    );
  }
}

/// Renders text with URLs as tappable links (description and comments).
class _LinkableText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _LinkableText(this.text, {required this.style});

  static final _urlRegex = RegExp(r"(https?://[^\s<>]+)");

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final spans = <TextSpan>[];
    int start = 0;
    for (final match in _urlRegex.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(
          text: text.substring(start, match.start),
          style: style,
        ));
      }
      final url = match.group(0)!;
      final trimmed = url.replaceFirst(RegExp(r'[.,;:!?)\)\]]+$'), '');
      spans.add(TextSpan(
        text: url,
        style: (style.copyWith(
          color: const Color(0xFF0052CC),
          decoration: TextDecoration.underline,
          decorationColor: const Color(0xFF0052CC),
        )),
        recognizer: TapGestureRecognizer()
          ..onTap = () async {
            final uri = Uri.tryParse(trimmed);
            if (uri != null && await url_launcher.canLaunchUrl(uri)) {
              await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication);
            }
          },
      ));
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: style));
    }
    return SelectableText.rich(
      TextSpan(children: spans, style: style),
    );
  }
}
