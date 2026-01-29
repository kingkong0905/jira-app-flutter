import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:open_file/open_file.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:video_player/video_player.dart';
import '../models/jira_models.dart';
import '../services/jira_api_service.dart';
import '../utils/adf_quill_converter.dart';

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
  // Description edit
  bool _updatingDescription = false;
  // Assignee search
  final TextEditingController _assigneeSearchController = TextEditingController();
  Timer? _assigneeSearchTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _previewVideoController?.dispose();
    _previewVideoController = null;
    _newCommentController.dispose();
    _storyPointsController?.dispose();
    _assigneeSearchController.dispose();
    _assigneeSearchTimer?.cancel();
    super.dispose();
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
        setState(() {
          _issue = issue;
          _comments = comments;
          _currentUser = currentUser;
          _loading = false;
        });
        _loadSubtasks();
        _loadParent(issue);
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
      if (mounted) setState(() {
        _subtasks = list;
        _loadingSubtasks = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _subtasks = [];
        _loadingSubtasks = false;
      });
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
      body: Stack(
        children: [
          _loading
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
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSummaryCard(),
                          _buildDetailsCard(),
                          const SizedBox(height: 16),
                          _buildDescriptionCard(),
                          if ((_issue!.fields.attachment ?? []).isNotEmpty) ...[
                            const SizedBox(height: 24),
                            const Text('Attachments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            _buildAttachmentsSection(),
                          ],
                          if (_issue!.fields.parent != null) ...[
                            const SizedBox(height: 24),
                            const Text('Parent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            _buildParentCard(),
                          ],
                          const SizedBox(height: 24),
                          const Text('Subtasks', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          _buildSubtasksSection(),
                          const SizedBox(height: 24),
                          const Text('Comments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          if (_replyToCommentId != null) _buildReplyBanner(),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _newCommentController,
                                  decoration: const InputDecoration(
                                    hintText: 'Add a comment... (type @ to mention)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  maxLines: 4,
                                  minLines: 1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: _addingComment ? null : _onAddComment,
                                child: _addingComment
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Post comment'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_comments.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('No comments yet. Be the first to comment!', style: TextStyle(color: Color(0xFF5E6C84), fontStyle: FontStyle.italic)),
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
        ],
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
                            : const Text('Failed to load image', style: TextStyle(color: Colors.white)))
                    : isVideo
                        ? (videoError != null
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.error_outline, color: Colors.white, size: 48),
                                    const SizedBox(height: 16),
                                    Text('Video failed to load', style: const TextStyle(color: Colors.white, fontSize: 16)),
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
                                      label: const Text('Open externally'),
                                    ),
                                  ],
                                ),
                              )
                            : videoController != null && videoController.value.isInitialized
                                ? _buildVideoPreviewPlayer(videoController)
                                : const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(color: Colors.white),
                                        SizedBox(height: 16),
                                        Text('Loading video...', style: TextStyle(color: Colors.white, fontSize: 14)),
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
                                  label: const Text('Open'),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: const Color(0xFF0052CC),
          backgroundImage: user.avatar48 != null ? NetworkImage(user.avatar48!) : null,
          child: user.avatar48 == null
              ? Text(
                  user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
                  style: TextStyle(color: Colors.white, fontSize: radius > 14 ? 16 : 12, fontWeight: FontWeight.w600),
                )
              : null,
        ),
        const SizedBox(width: 8),
        Flexible(child: Text(user.displayName, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  /// IssueSummaryCard-style: key+status row, divider, Summary header + priority emoji + Edit, summary text.
  Widget _buildSummaryCard() {
    final statusColor = _statusColor(_issue!.fields.status.statusCategory.key);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E4E8)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
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
                  const Text('ISSUE KEY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF5E6C84), letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Text(_issue!.key, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF0052CC), letterSpacing: 0.3)),
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
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 2, offset: const Offset(0, 1))],
                    ),
                    child: Text(_issue!.fields.status.name.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5)),
                  ),
                )
              else
                _chip(_issue!.fields.status.name, statusColor),
            ],
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: const Color(0xFFE1E4E8)),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('📝', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  const Text('Summary', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF172B4D), letterSpacing: 0.2)),
                  if (_issue!.fields.priority != null) ...[
                    const SizedBox(width: 8),
                    Text(_getPriorityEmoji(_issue!.fields.priority!.name), style: const TextStyle(fontSize: 16)),
                  ],
                ],
              ),
              if (_canEdit)
                TextButton(
                  onPressed: () => _openSummaryEdit(),
                  child: const Text('Edit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0052CC))),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _issue!.fields.summary,
            style: const TextStyle(fontSize: 20, color: Color(0xFF172B4D), fontWeight: FontWeight.w600, height: 1.5, letterSpacing: 0.1),
          ),
        ],
      ),
    );
  }

  /// IssueDetailsFields-style: card with icon+label rows (Assignee, Reporter, Priority, Type, Sprint, Story Points, Due Date).
  Widget _buildDetailsCard() {
    final sprintDisplay = _formatSprint(_issue!.fields.sprint);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E4E8)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('📋', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text('Details', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF172B4D), letterSpacing: 0.2)),
            ],
          ),
          const SizedBox(height: 16),
          _detailRowTap(
            icon: '👤',
            label: 'Assignee',
            value: _issue!.fields.assignee != null ? _userTile(_issue!.fields.assignee!, radius: 12) : const Text('Unassigned', style: TextStyle(fontSize: 15, color: Color(0xFF8993A4), fontStyle: FontStyle.italic)),
            onTap: _canEdit ? _openAssigneePicker : null,
          ),
          if (_issue!.fields.reporter != null)
            _detailRowStatic(
              icon: '📝',
              label: 'Reporter',
              value: _userTile(_issue!.fields.reporter!, radius: 12),
            ),
          _detailRowTap(
            icon: '⚡',
            label: 'Priority',
            value: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_getPriorityEmoji(_issue!.fields.priority?.name), style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(_issue!.fields.priority?.name ?? 'None', style: const TextStyle(fontSize: 15, color: Color(0xFF172B4D), fontWeight: FontWeight.w500)),
              ],
            ),
            onTap: _canEdit ? _openPriorityPicker : null,
          ),
          _detailRowStatic(icon: '🏷️', label: 'Type', value: Text(_issue!.fields.issuetype.name, style: const TextStyle(fontSize: 14, color: Color(0xFF5E6C84), fontWeight: FontWeight.w500))),
          _detailRowTap(
            icon: '🏃',
            label: 'Sprint',
            value: Text(sprintDisplay, style: const TextStyle(fontSize: 15, color: Color(0xFF172B4D), fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: _canEdit ? _openSprintPicker : null,
          ),
          _detailRowTap(
            icon: '🎯',
            label: 'Story Points',
            value: Text(_issue!.fields.customfield_10016?.toString() ?? 'Not set', style: const TextStyle(fontSize: 15, color: Color(0xFF172B4D), fontWeight: FontWeight.w500)),
            onTap: _canEdit ? _openStoryPointsPicker : null,
          ),
          _detailRowTap(
            icon: '📅',
            label: 'Due Date',
            value: Text(
              _issue!.fields.duedate != null ? _formatDueDate(_issue!.fields.duedate!) : 'Not set',
              style: const TextStyle(fontSize: 15, color: Color(0xFF172B4D), fontWeight: FontWeight.w500),
            ),
            onTap: _canEdit ? _openDueDatePicker : null,
          ),
        ],
      ),
    );
  }

  /// Description card with Edit (plain/ADF display, edit as plain text → ADF).
  Widget _buildDescriptionCard() {
    final plain = _plainText(_issue!.fields.description).trim();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E4E8)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Description', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF172B4D), letterSpacing: 0.2)),
              if (_canEdit)
                TextButton(
                  onPressed: _updatingDescription ? null : _openDescriptionEdit,
                  child: _updatingDescription
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0052CC)))
                      : const Text('Edit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0052CC))),
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Description updated')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }

  String _formatSprint(dynamic sprint) {
    if (sprint == null) return 'None';
    if (sprint is List) {
      if (sprint.isEmpty) return 'None';
      final last = sprint is List<JiraSprintRef> ? sprint.last : (sprint as List).last;
      return last is JiraSprintRef ? last.name : (last is Map ? (last['name']?.toString() ?? 'None') : 'None');
    }
    if (sprint is JiraSprintRef) return sprint.name;
    return sprint.toString();
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
                  Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF5E6C84))),
                ],
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0x050052CC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(child: value),
                    if (onTap != null) const Text(' ›', style: TextStyle(fontSize: 20, color: Color(0xFF8993A4), fontWeight: FontWeight.w300)),
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
                Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF5E6C84))),
              ],
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0x050052CC),
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
        title: const Text('Edit Summary'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    final err = await context.read<JiraApiService>().updateIssueField(widget.issueKey, {'summary': result});
    if (mounted) {
      if (err == null) {
        await _refreshIssue();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Summary updated')));
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

  void _openSprintPicker() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sprint picker coming soon')));
  }

  Future<void> _refreshIssue() async {
    final api = context.read<JiraApiService>();
    final issue = await api.getIssueDetails(widget.issueKey);
    if (mounted) setState(() => _issue = issue);
  }

  Widget _buildAssigneePickerModal() {
    return _modalSheet(
      title: 'Assignee',
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
              decoration: const InputDecoration(
                hintText: 'Search assignee...',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 20),
              ),
              onChanged: _debouncedAssigneeSearch,
            ),
          ),
          if (_loadingUsers)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: Color(0xFF0052CC))))
          else ...[
            ListTile(
              title: const Text('Unassigned', style: TextStyle(fontStyle: FontStyle.italic)),
              onTap: () async {
                setState(() => _updatingAssignee = 'unassign');
                final err = await context.read<JiraApiService>().updateIssueField(widget.issueKey, {'assignee': null});
                if (mounted) {
                  setState(() { _updatingAssignee = null; _showAssigneePicker = false; });
                  if (err == null) {
                    await _refreshIssue();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assignee cleared')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                }
              },
              trailing: _updatingAssignee == 'unassign' ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            ),
            ..._assignableUsers.map((u) {
              final isCurrent = _issue!.fields.assignee?.accountId == u.accountId;
              return ListTile(
                leading: CircleAvatar(radius: 16, backgroundImage: u.avatar48 != null ? NetworkImage(u.avatar48!) : null, child: u.avatar48 == null ? Text(u.displayName.isNotEmpty ? u.displayName[0] : '?') : null),
                title: Text(u.displayName),
                subtitle: u.emailAddress != null ? Text(u.emailAddress!, style: const TextStyle(fontSize: 12)) : null,
                selected: isCurrent,
                onTap: isCurrent ? null : () async {
                  setState(() => _updatingAssignee = u.accountId);
                  final err = await context.read<JiraApiService>().updateIssueField(widget.issueKey, {'assignee': {'accountId': u.accountId}});
                  if (mounted) {
                    setState(() { _updatingAssignee = null; _showAssigneePicker = false; });
                    if (err == null) {
                      await _refreshIssue();
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assignee updated')));
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

  Widget _buildStatusPickerModal() {
    return _modalSheet(
      title: 'Status',
      onClose: () => setState(() => _showStatusPicker = false),
      child: _loadingTransitions
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: Color(0xFF0052CC))))
          : _transitions.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Text('No transitions available', style: TextStyle(color: Color(0xFF5E6C84))))
              : ListView(
                  shrinkWrap: true,
                  children: _transitions.map((t) {
                    final id = t['id']?.toString() ?? '';
                    final name = t['name']?.toString() ?? id;
                    final to = t['to'];
                    final toName = to is Map ? (to['name']?.toString() ?? '') : '';
                    final isTransitioning = _transitioningStatusId == id;
                    return ListTile(
                      title: Text(name),
                      subtitle: toName.isNotEmpty ? Text('→ $toName') : null,
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
    );
  }

  Widget _buildPriorityPickerModal() {
    return _modalSheet(
      title: 'Priority',
      onClose: () => setState(() => _showPriorityPicker = false),
      child: _loadingPriorities
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: Color(0xFF0052CC))))
          : ListView(
              shrinkWrap: true,
              children: _priorities.map((p) {
                final id = p['id']?.toString() ?? '';
                final name = p['name']?.toString() ?? 'Unknown';
                final isUpdating = _updatingPriorityId == id;
                return ListTile(
                  leading: Text(_getPriorityEmoji(name), style: const TextStyle(fontSize: 20)),
                  title: Text(name),
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
      title: 'Due Date',
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

  Widget _modalSheet({required String title, required VoidCallback onClose, required Widget child}) {
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
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      IconButton(icon: const Icon(Icons.close), onPressed: onClose),
                    ],
                  ),
                ),
                Flexible(child: SingleChildScrollView(child: child)),
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
    if (_loadingParent) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(height: 44, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0052CC)))),
      );
    }
    final parent = _parentIssue ?? _issue?.fields.parent;
    if (parent == null) return const SizedBox.shrink();
    final key = parent is JiraIssue ? parent.key : (parent as JiraIssueParent).key;
    final summary = parent is JiraIssue ? parent.fields.summary : (parent as JiraIssueParent).summary ?? '';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _navigateToIssue(key),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDFE1E6)),
          ),
          child: Row(
            children: [
              Icon(Icons.account_tree, color: Colors.grey.shade600, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(key, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0052CC), fontSize: 14)),
                    if (summary.isNotEmpty)
                      Text(summary, style: const TextStyle(fontSize: 13, color: Color(0xFF5E6C84)), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF5E6C84)),
            ],
          ),
        ),
      ),
    );
  }

  /// Subtasks section: same as reference IssueSubtasksCard — list of subtasks, tap to open.
  Widget _buildSubtasksSection() {
    if (_loadingSubtasks) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(height: 44, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0052CC)))),
      );
    }
    if (_subtasks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text('No subtasks.', style: TextStyle(color: Color(0xFF5E6C84), fontSize: 14)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _subtasks.map((issue) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => _navigateToIssue(issue.key),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDFE1E6)),
                ),
                child: Row(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(issue.key, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0052CC), fontSize: 13)),
                          Text(issue.fields.summary, style: const TextStyle(fontSize: 13, color: Color(0xFF172B4D)), maxLines: 2, overflow: TextOverflow.ellipsis),
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
          setState(() => _replyToCommentId = null);
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
    final card = Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFFF4F5F7),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF0052CC),
                  backgroundImage: author?.avatar48 != null ? NetworkImage(author!.avatar48!) : null,
                  child: author?.avatar48 == null
                      ? Text(
                          authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(authorName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF172B4D))),
                      Text(_formatRelativeDate(created), style: const TextStyle(fontSize: 12, color: Color(0xFF7A869A))),
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
                      foregroundColor: const Color(0xFF42526E),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _onShareComment(commentId),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Share'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF42526E),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                  if (isOwnComment) ...[
                    TextButton.icon(
                      onPressed: () => _onEditComment(map),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF42526E),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _onDeleteComment(commentId),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFF5630),
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
            child: const Text('Save'),
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
    if (id != null) {
      final found = attachments.cast<JiraAttachment?>().firstWhere(
        (a) => a?.id == id,
        orElse: () => null,
      );
      if (found != null) return found;
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
    if (body is String) {
      return _LinkableText(body as String, style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF42526E)));
    }
    if (body is Map) {
      final content = body['content'];
      if (content is! List || content.isEmpty) {
        return _LinkableText(_plainText(body), style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF42526E)));
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
                          style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF0052CC), decoration: TextDecoration.underline),
                        ),
                      ),
                    ));
                    continue;
                  }
                }
                TextStyle textStyle = const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF42526E));
                if (marks != null) {
                  for (final m in marks) {
                    if (m is Map) {
                      if (m['type'] == 'strong') textStyle = textStyle.copyWith(fontWeight: FontWeight.bold);
                      else if (m['type'] == 'em') textStyle = textStyle.copyWith(fontStyle: FontStyle.italic);
                      else if (m['type'] == 'code') textStyle = textStyle.copyWith(fontFamily: 'monospace', backgroundColor: const Color(0xFFF4F5F7));
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
                    color: const Color(0xFFE6FCFF),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFB3D4FF), width: 1),
                  ),
                  child: Text(
                    displayName,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF0052CC), fontWeight: FontWeight.w500),
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
                      child: Text(url, style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF0052CC), decoration: TextDecoration.underline)),
                    ),
                  ));
                }
              } else if (itemType == 'mediaInline') {
                final att = _resolveAttachment(item, attachments);
                if (att != null) {
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
                child: _LinkableText(text, style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF42526E))),
              ));
            }
          }
        } else if (type == 'mediaSingle' && node['content'] is List) {
          final bytes = loadedImageBytes ?? {};
          final onLoad = onNeedLoadImage;
          for (final media in node['content'] as List) {
            final att = _resolveAttachment(media, attachments);
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
          for (final media in node['content'] as List) {
            final att = _resolveAttachment(media, attachments);
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
                              label: const Text('Open'),
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
            child: const Text('Save'),
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

  Widget _renderInlineContent(List<dynamic> content, [TextStyle? baseStyle]) {
    final style = baseStyle ?? const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF42526E));
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
                child: Text(text.isEmpty ? href : text, style: style.copyWith(color: const Color(0xFF0052CC), decoration: TextDecoration.underline)),
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
              else if (m['type'] == 'code') s = s.copyWith(fontFamily: 'monospace', backgroundColor: const Color(0xFFF4F5F7));
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
              color: const Color(0xFFE6FCFF),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFB3D4FF), width: 1),
            ),
            child: Text(name, style: const TextStyle(fontSize: 13, color: Color(0xFF0052CC), fontWeight: FontWeight.w500)),
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
              child: Text(url, style: style.copyWith(color: const Color(0xFF0052CC), decoration: TextDecoration.underline)),
            ),
          ));
        }
      } else if (itemType == 'hardBreak') {
        row.add(const Text('\n', style: TextStyle(fontSize: 14, height: 1.5)));
      }
    }
    if (row.isEmpty) return const SizedBox.shrink();
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 0, runSpacing: 4, children: row);
  }

  Widget _renderList(dynamic listNode, int listIndex) {
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
                  SizedBox(width: 24, child: Text(bullet, style: const TextStyle(fontSize: 14, color: Color(0xFF42526E)))),
                  Expanded(child: _renderInlineContent(node['content'] as List)),
                ],
              ),
            ));
          } else if (node is Map && (node['type'] == 'bulletList' || node['type'] == 'orderedList')) {
            items.add(Padding(padding: const EdgeInsets.only(left: 20), child: _renderList(node, i)));
          }
        }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: items);
  }

  @override
  Widget build(BuildContext context) {
    if (description == null) {
      return const Text('No description', style: TextStyle(fontSize: 15, color: Color(0xFF8993A4), height: 1.5));
    }
    if (description is String) {
      final s = (description as String).trim();
      if (s.isEmpty) return const Text('No description', style: TextStyle(fontSize: 15, color: Color(0xFF8993A4), height: 1.5));
      return _LinkableText(s, style: const TextStyle(fontSize: 15, color: Color(0xFF172B4D), height: 1.5));
    }
    if (description is! Map) return const Text('No description', style: TextStyle(fontSize: 15, color: Color(0xFF8993A4), height: 1.5));
    final content = description['content'];
    if (content is! List || content.isEmpty) {
      final plain = _plainText(description);
      if (plain.trim().isEmpty) return const Text('No description', style: TextStyle(fontSize: 15, color: Color(0xFF8993A4), height: 1.5));
      return _LinkableText(plain, style: const TextStyle(fontSize: 15, color: Color(0xFF172B4D), height: 1.5));
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
            child: _renderInlineContent(paragraphContent),
          ));
        } else {
          final text = _plainText(paragraphContent is List ? {'content': paragraphContent} : node);
          if (text.isNotEmpty) {
            children.add(Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LinkableText(text, style: const TextStyle(fontSize: 15, color: Color(0xFF172B4D), height: 1.5)),
            ));
          }
        }
      } else if (type == 'heading' && node['content'] is List) {
        final level = (node['attrs'] is Map) ? intFromJson((node['attrs'] as Map)['level']) ?? 1 : 1;
        TextStyle headingStyle = const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF172B4D));
        if (level == 1) headingStyle = headingStyle.copyWith(fontSize: 24);
        else if (level == 2) headingStyle = headingStyle.copyWith(fontSize: 20);
        else if (level == 3) headingStyle = headingStyle.copyWith(fontSize: 18);
        else if (level == 4) headingStyle = headingStyle.copyWith(fontSize: 16);
        else headingStyle = headingStyle.copyWith(fontSize: 14);
        children.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: _renderInlineContent(node['content'] as List, headingStyle),
        ));
      } else if (type == 'bulletList' || type == 'orderedList') {
        children.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: _renderList(node, 0)));
      } else if (type == 'codeBlock' && node['content'] is List) {
        final code = (node['content'] as List).map((c) => _plainText(c)).join('');
        children.add(Container(
          margin: const EdgeInsets.only(top: 4, bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F5F7),
            borderRadius: BorderRadius.circular(4),
            border: const Border(left: BorderSide(color: Color(0xFFDFE1E6), width: 3)),
          ),
          child: SelectableText(code, style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: Color(0xFF172B4D))),
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
