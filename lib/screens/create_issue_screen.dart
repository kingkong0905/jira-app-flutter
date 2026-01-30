import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/jira_models.dart';
import '../services/jira_api_service.dart';
import '../l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../utils/adf_quill_converter.dart';
import '../widgets/attachment_upload_widget.dart';

/// Create Issue screen: allows user to create a new issue for the selected board.
/// Similar to React Native CreateIssueScreen.tsx
class CreateIssueScreen extends StatefulWidget {
  final int boardId;
  final String? projectKey;
  final VoidCallback onBack;
  final VoidCallback onIssueCreated;

  const CreateIssueScreen({
    super.key,
    required this.boardId,
    this.projectKey,
    required this.onBack,
    required this.onIssueCreated,
  });

  @override
  State<CreateIssueScreen> createState() => _CreateIssueScreenState();
}

class _CreateIssueScreenState extends State<CreateIssueScreen> {
  final _summaryController = TextEditingController();
  late quill.QuillController _descriptionController;
  final ScrollController _descriptionScrollController = ScrollController();
  final FocusNode _descriptionFocusNode = FocusNode();
  final _storyPointsController = TextEditingController();

  List<Map<String, dynamic>> _issueTypes = [];
  List<JiraSprint> _sprints = [];
  List<JiraUser> _assignableUsers = [];
  List<Map<String, dynamic>> _priorities = [];
  List<JiraIssue> _parentIssues = [];

  String? _selectedIssueTypeId;
  String? _selectedPriorityId;
  String? _selectedAssignee;
  int? _selectedSprintId;
  String? _selectedParentKey;
  DateTime? _dueDate;

  bool _loading = true;
  bool _creating = false;
  bool _loadingParents = false;
  List<AttachmentItem> _attachments = [];

  @override
  void initState() {
    super.initState();
    // Initialize Quill controller with empty document
    final doc = quill.Document.fromJson([{'insert': '\n'}]);
    _descriptionController = quill.QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _loadInitialData();
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _descriptionController.dispose();
    _descriptionScrollController.dispose();
    _descriptionFocusNode.dispose();
    _storyPointsController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (widget.projectKey == null) {
      _showSnack(AppLocalizations.of(context).noProjectSelected, isError: true);
      widget.onBack();
      return;
    }

    debugPrint('CreateIssueScreen initialized');
    debugPrint('Board ID: ${widget.boardId}');
    debugPrint('Project Key: ${widget.projectKey}');

    final api = context.read<JiraApiService>();
    setState(() => _loading = true);

    try {
      final results = await Future.wait([
        api.getIssueTypesForProject(widget.projectKey!),
        api.getSprintsForBoard(widget.boardId),
        api.getAssignableUsersForProject(widget.projectKey!),
        api.getPriorities(),
      ]);

      final issueTypes = results[0] as List<Map<String, dynamic>>;
      final sprints = results[1] as List<JiraSprint>;
      final users = results[2] as List<JiraUser>;
      final priorities = results[3] as List<Map<String, dynamic>>;

      // Filter active and future sprints
      final activeAndFutureSprints = sprints.where((s) => s.state == 'active' || s.state == 'future').toList();

      setState(() {
        _issueTypes = issueTypes;
        _sprints = activeAndFutureSprints;
        _assignableUsers = users;
        _priorities = priorities;
        _selectedIssueTypeId = issueTypes.isNotEmpty ? issueTypes[0]['id'] as String? : null;
        _loading = false;
      });

      // Debug: Print available issue types
      debugPrint('Available issue types:');
      for (final type in issueTypes) {
        debugPrint('  - ${type['name']} (id: ${type['id']})');
      }

      // Load parent issues if the initial issue type requires a parent
      if (_shouldShowParentField()) {
        debugPrint('Initial issue type requires parent, loading...');
        _loadParentIssues();
      }
    } catch (e) {
      setState(() => _loading = false);
      _showSnack('Failed to load form data', isError: true);
    }
  }

  Future<void> _loadParentIssues() async {
    if (widget.projectKey == null || _selectedIssueTypeId == null) return;

    setState(() => _loadingParents = true);

    final api = context.read<JiraApiService>();
    final selectedType = _issueTypes.where((t) => t['id'] == _selectedIssueTypeId).firstOrNull;
    if (selectedType == null) {
      setState(() => _loadingParents = false);
      return;
    }

    final typeName = (selectedType['name'] as String).toLowerCase();
    debugPrint('Loading parents for issue type: $typeName');
    debugPrint('Using project key: ${widget.projectKey}');
    debugPrint('Board ID: ${widget.boardId}');
    String jql = '';

    // Determine parent issue types based on current issue type
    // Note: Using project key for filtering
    if (typeName == 'bug' || typeName == 'story' || typeName == 'user story') {
      // For Bug/Story, parent is Epic
      final epicType = _issueTypes.where((t) => (t['name'] as String).toLowerCase() == 'epic').firstOrNull;
      if (epicType != null) {
        jql = 'project = ${widget.projectKey} AND issuetype = ${epicType['id']} ORDER BY created DESC';
      } else {
        jql = 'project = ${widget.projectKey} AND issuetype = Epic ORDER BY created DESC';
      }
    } else if (typeName == 'task') {
      // For Task, parent can be Epic or Story
      final epicType = _issueTypes.where((t) => (t['name'] as String).toLowerCase() == 'epic').firstOrNull;
      final storyType = _issueTypes.where((t) => (t['name'] as String).toLowerCase() == 'story').firstOrNull;
      
      final types = <String>[];
      if (epicType != null) types.add(epicType['id'].toString());
      if (storyType != null) types.add(storyType['id'].toString());
      
      if (types.isNotEmpty) {
        jql = 'project = ${widget.projectKey} AND issuetype in (${types.join(',')}) ORDER BY created DESC';
      } else {
        jql = 'project = ${widget.projectKey} AND (issuetype = Epic OR issuetype = Story) ORDER BY created DESC';
      }
    } else if (typeName.contains('sub-task') || typeName.contains('subtask') || typeName == 'sub task') {
      // For Subtask, parent can be Task, Story, or Bug
      final taskType = _issueTypes.where((t) => (t['name'] as String).toLowerCase() == 'task').firstOrNull;
      final storyType = _issueTypes.where((t) => (t['name'] as String).toLowerCase() == 'story').firstOrNull;
      final bugType = _issueTypes.where((t) => (t['name'] as String).toLowerCase() == 'bug').firstOrNull;
      
      final types = <String>[];
      if (taskType != null) types.add(taskType['id'].toString());
      if (storyType != null) types.add(storyType['id'].toString());
      if (bugType != null) types.add(bugType['id'].toString());
      
      if (types.isNotEmpty) {
        jql = 'project = ${widget.projectKey} AND issuetype in (${types.join(',')}) ORDER BY created DESC';
      } else {
        jql = 'project = ${widget.projectKey} AND (issuetype = Task OR issuetype = Story OR issuetype = Bug) ORDER BY created DESC';
      }
    }

    if (jql.isEmpty) {
      debugPrint('No JQL query for issue type: $typeName');
      setState(() => _loadingParents = false);
      return;
    }

    debugPrint('Searching parents with JQL: $jql');
    try {
      final issues = await api.searchIssues(jql, maxResults: 100);
      debugPrint('Found ${issues.length} potential parent issues');
      if (issues.isNotEmpty) {
        debugPrint('First parent: ${issues[0].key} - ${issues[0].fields.summary}');
      } else {
        // Debug: Try to find ANY issue in the project to verify the query works
        debugPrint('No results found. Testing if ANY issues exist in project...');
        try {
          final testIssues = await api.searchIssues('project = ${widget.projectKey} ORDER BY created DESC', maxResults: 5);
          debugPrint('Test query found ${testIssues.length} total issues in project');
          if (testIssues.isNotEmpty) {
            for (final issue in testIssues) {
              debugPrint('  - ${issue.key}: ${issue.fields.issuetype.name} - ${issue.fields.summary}');
            }
          }
        } catch (testError) {
          debugPrint('Test query error: $testError');
        }
      }
      setState(() {
        _parentIssues = issues;
        _loadingParents = false;
      });
    } catch (e) {
      debugPrint('Error loading parent issues: $e');
      setState(() => _loadingParents = false);
    }
  }

  bool _shouldShowParentField() {
    if (_selectedIssueTypeId == null) return false;
    final selectedType = _issueTypes.where((t) => t['id'] == _selectedIssueTypeId).firstOrNull;
    if (selectedType == null) return false;

    final typeName = (selectedType['name'] as String).toLowerCase();
    // More flexible matching for various subtask naming
    return typeName == 'bug' ||
        typeName == 'task' ||
        typeName == 'story' ||
        typeName == 'user story' ||
        typeName.contains('sub-task') ||
        typeName.contains('subtask') ||
        typeName == 'sub task';
  }

  Future<void> _handleCreate() async {
    // Validation
    if (_selectedIssueTypeId == null) {
      _showSnack('Please select an issue type', isError: true);
      return;
    }

    if (_summaryController.text.trim().isEmpty) {
      _showSnack('Please enter a summary', isError: true);
      return;
    }

    setState(() => _creating = true);

    final api = context.read<JiraApiService>();
    
    // Create issue first
    final result = await api.createIssue(
      projectKey: widget.projectKey!,
      issueTypeId: _selectedIssueTypeId!,
      summary: _summaryController.text.trim(),
      descriptionAdf: _getDescriptionAdf(),
      assigneeAccountId: _selectedAssignee,
      priorityId: _selectedPriorityId,
      dueDate: _dueDate != null ? DateFormat('yyyy-MM-dd').format(_dueDate!) : null,
      storyPoints: _storyPointsController.text.trim().isEmpty ? null : double.tryParse(_storyPointsController.text.trim()),
      sprintId: _selectedSprintId,
      parentKey: _selectedParentKey,
    );

    if (result == null || result.startsWith('ERROR:')) {
      setState(() => _creating = false);
      _showSnack(result?.substring(6) ?? 'Failed to create issue', isError: true);
      return;
    }

    // Upload attachments if we have them and insert into description
    final createdIssueKey = result;
    if (_attachments.isNotEmpty) {
      try {
        for (final attachment in _attachments) {
          if (!attachment.isUploaded && attachment.hasFile) {
            Map<String, String>? uploadResult;
            if (attachment.filePath != null) {
              uploadResult = await api.uploadAttachment(
                createdIssueKey,
                attachment.filePath!,
                attachment.filename,
              );
            } else if (attachment.fileBytes != null) {
              uploadResult = await api.uploadAttachmentFromBytes(
                createdIssueKey,
                attachment.fileBytes!,
                attachment.filename,
              );
            }
            
            // If upload successful, insert attachment marker into editor
            if (uploadResult != null && uploadResult['id'] != null) {
              final attachmentId = uploadResult['id']!;
              final filename = uploadResult['filename'] ?? attachment.filename;
              final mimeType = uploadResult['mimeType'] ?? '';
              final isImage = mimeType.startsWith('image/') || attachment.isImage;
              
              // Insert attachment marker into Quill editor
              final marker = isImage 
                  ? '[image:$attachmentId:$filename]'
                  : '[attachment:$attachmentId:$filename]';
              
              final index = _descriptionController.selection.baseOffset;
              final currentDelta = _descriptionController.document.toDelta();
              final currentOps = currentDelta.toJson() as List<dynamic>;
              final newOps = <dynamic>[];
              int currentPos = 0;
              bool inserted = false;
              
              for (final op in currentOps) {
                if (op is Map && !inserted) {
                  final insert = op['insert'];
                  final retain = op['retain'] as int?;
                  if (retain != null) {
                    if (currentPos + retain <= index) {
                      newOps.add(op);
                      currentPos += retain;
                    } else if (currentPos < index) {
                      final before = index - currentPos;
                      final after = retain - before;
                      if (before > 0) newOps.add({'retain': before});
                      newOps.add({'insert': marker});
                      inserted = true;
                      if (after > 0) newOps.add({'retain': after});
                      currentPos += retain;
                    } else {
                      if (!inserted) {
                        newOps.add({'insert': marker});
                        inserted = true;
                      }
                      newOps.add(op);
                      currentPos += retain;
                    }
                  } else if (insert != null) {
                    final text = insert.toString();
                    final textLength = text.length;
                    if (currentPos + textLength <= index) {
                      newOps.add(op);
                      currentPos += textLength;
                    } else if (currentPos < index) {
                      final splitPos = index - currentPos;
                      final before = text.substring(0, splitPos);
                      final after = text.substring(splitPos);
                      if (before.isNotEmpty) newOps.add({'insert': before});
                      newOps.add({'insert': marker});
                      inserted = true;
                      if (after.isNotEmpty) {
                        final afterOp = Map<String, dynamic>.from(op);
                        afterOp['insert'] = after;
                        newOps.add(afterOp);
                      }
                      currentPos += textLength;
                    } else {
                      if (!inserted) {
                        newOps.add({'insert': marker});
                        inserted = true;
                      }
                      newOps.add(op);
                      currentPos += textLength;
                    }
                  } else {
                    newOps.add(op);
                  }
                } else {
                  newOps.add(op);
                }
              }
              if (!inserted) {
                if (currentPos < index) newOps.add({'retain': index - currentPos});
                newOps.add({'insert': marker});
              }
              _descriptionController.document = quill.Document.fromJson(newOps);
              _descriptionController.updateSelection(
                TextSelection.collapsed(offset: index + marker.length),
                quill.ChangeSource.local,
              );
              
              // Update attachment with upload info
              final updatedAttachment = AttachmentItem(
                filePath: attachment.filePath,
                filename: filename,
                size: attachment.size,
                fileBytes: attachment.fileBytes,
                attachmentId: attachmentId,
                contentUrl: uploadResult['content'],
                mimeType: mimeType,
              );
              
              // Replace old attachment with updated one
              setState(() {
                final idx = _attachments.indexOf(attachment);
                if (idx >= 0) {
                  _attachments[idx] = updatedAttachment;
                }
              });
            }
          }
        }
      } catch (e) {
        debugPrint('Failed to upload attachments: $e');
        // Continue even if attachment upload fails
      }
    }

    setState(() => _creating = false);

    _showSnack('Issue created successfully');
    widget.onIssueCreated();
  }

  Map<String, dynamic>? _getDescriptionAdf() {
    final delta = _descriptionController.document.toDelta();
    final ops = delta.toJson();
    final adf = quillOpsToAdf(ops);
    // Return null if description is empty
    final plainText = _descriptionController.document.toPlainText().trim();
    return plainText.isEmpty ? null : adf;
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : AppTheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _getSelectedIssueTypeName() {
    if (_selectedIssueTypeId == null) return 'Select Issue Type';
    final type = _issueTypes.where((t) => t['id'] == _selectedIssueTypeId).firstOrNull;
    return type?['name'] as String? ?? 'Select Issue Type';
  }

  String _getSelectedPriorityName() {
    if (_selectedPriorityId == null) return AppLocalizations.of(context).none;
    final priority = _priorities.where((p) => p['id'] == _selectedPriorityId).firstOrNull;
    return priority?['name'] as String? ?? AppLocalizations.of(context).none;
  }

  String _getSelectedAssigneeName() {
    if (_selectedAssignee == null) return AppLocalizations.of(context).unassigned;
    final user = _assignableUsers.where((u) => u.accountId == _selectedAssignee).firstOrNull;
    return user?.displayName ?? AppLocalizations.of(context).unassigned;
  }

  String _getSelectedSprintName() {
    if (_selectedSprintId == null) return AppLocalizations.of(context).none;
    final sprint = _sprints.where((s) => s.id == _selectedSprintId).firstOrNull;
    return sprint?.name ?? AppLocalizations.of(context).none;
  }

  String _getSelectedParentName() {
    if (_selectedParentKey == null) return AppLocalizations.of(context).none;
    final parent = _parentIssues.where((i) => i.key == _selectedParentKey).firstOrNull;
    return parent != null ? '${parent.key}: ${parent.fields.summary}' : AppLocalizations.of(context).none;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        leading: Semantics(
          label: AppLocalizations.of(context).back,
          button: true,
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
        ),
        title: Text(AppLocalizations.of(context).createIssue, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(AppLocalizations.of(context).basics),
                  const SizedBox(height: 12),
                  _buildFieldLabel(AppLocalizations.of(context).issueType, required: true),
                  const SizedBox(height: 8),
                  _buildDropdownButton(
                    value: _getSelectedIssueTypeName(),
                    onTap: () => _showIssueTypePicker(),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel(AppLocalizations.of(context).priority),
                  const SizedBox(height: 8),
                  _buildDropdownButton(
                    value: _getSelectedPriorityName(),
                    onTap: () => _showPriorityPicker(),
                  ),
                  const SizedBox(height: 20),

                  if (_shouldShowParentField()) ...[
                    _buildFieldLabel(AppLocalizations.of(context).parent),
                    const SizedBox(height: 8),
                    _buildDropdownButton(
                      value: _loadingParents 
                          ? AppLocalizations.of(context).loading 
                          : (_parentIssues.isEmpty 
                              ? AppLocalizations.of(context).noParentIssuesFound 
                              : _getSelectedParentName()),
                      onTap: _loadingParents || _parentIssues.isEmpty ? null : () => _showParentPicker(),
                    ),
                    if (_parentIssues.isEmpty && !_loadingParents) ...[
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.of(context).createEpicOrStoryFirst,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted, fontStyle: FontStyle.italic),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],

                  _buildFieldLabel(AppLocalizations.of(context).summary, required: true),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _summaryController,
                    decoration: _inputDecoration(AppLocalizations.of(context).enterIssueSummary),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel(AppLocalizations.of(context).description),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        // Toolbar
                        Container(
                          decoration: const BoxDecoration(
                            color: AppTheme.surfaceMuted,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: quill.QuillSimpleToolbar(
                              controller: _descriptionController,
                              config: const quill.QuillSimpleToolbarConfig(
                                showUndo: false,
                                showRedo: false,
                                showBoldButton: true,
                                showItalicButton: true,
                                showUnderLineButton: false,
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
                                showClearFormat: false,
                                showAlignmentButtons: false,
                              ),
                            ),
                          ),
                        ),
                        // Editor
                        Container(
                          height: 200,
                          decoration: const BoxDecoration(
                            color: AppTheme.white,
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
                          ),
                          child: quill.QuillEditor.basic(
                            controller: _descriptionController,
                            config: const quill.QuillEditorConfig(
                              placeholder: 'Enter issue description...',
                              padding: EdgeInsets.all(12),
                            ),
                            focusNode: _descriptionFocusNode,
                            scrollController: _descriptionScrollController,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Attachment upload widget
                  AttachmentUploadWidget(
                    issueKey: null, // Will be set after issue creation
                    attachments: _attachments,
                    editorController: _descriptionController,
                    onAttachmentAdded: (attachment) {
                      setState(() {
                        _attachments.add(attachment);
                      });
                    },
                    onAttachmentRemoved: (attachment) {
                      setState(() {
                        _attachments.remove(attachment);
                      });
                    },
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader(AppLocalizations.of(context).details),
                  const SizedBox(height: 12),
                  _buildFieldLabel(AppLocalizations.of(context).assignee),
                  const SizedBox(height: 8),
                  _buildAssigneeButton(),
                  const SizedBox(height: 20),

                  // Due Date
                  _buildFieldLabel(AppLocalizations.of(context).dueDate),
                  const SizedBox(height: 8),
                  _buildDropdownButton(
                    value: _dueDate != null ? DateFormat('MMM dd, yyyy').format(_dueDate!) : AppLocalizations.of(context).noDueDate,
                    onTap: () => _showDatePicker(),
                    trailing: _dueDate != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () => setState(() => _dueDate = null),
                          )
                        : null,
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel(AppLocalizations.of(context).storyPoints),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _storyPointsController,
                    decoration: _inputDecoration('Enter story points (e.g., 3, 5, 8)'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader(AppLocalizations.of(context).planning),
                  const SizedBox(height: 12),
                  _buildFieldLabel(AppLocalizations.of(context).sprint),
                  const SizedBox(height: 8),
                  _buildDropdownButton(
                    value: _sprints.isEmpty ? AppLocalizations.of(context).noSprintsAvailable : _getSelectedSprintName(),
                    onTap: _sprints.isEmpty ? null : () => _showSprintPicker(),
                  ),
                  const SizedBox(height: 32),

                  Semantics(
                    label: AppLocalizations.of(context).createIssue,
                    button: true,
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _creating ? null : _handleCreate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: AppTheme.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: _creating
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(color: AppTheme.white, strokeWidth: 2),
                              )
                            : Text(AppLocalizations.of(context).createIssue, style: TextStyle(fontSize: AppTheme.fontSizeLg, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: AppTheme.paddingBottom4,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label, {bool required = false}) {
    return Text.rich(
      TextSpan(
        text: label,
        style: TextStyle(fontSize: AppTheme.fontSizeBase, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        children: required
            ? [const TextSpan(text: ' *', style: TextStyle(color: AppTheme.error))]
            : [],
      ),
    );
  }

  Widget _buildDropdownButton({required String value, VoidCallback? onTap, Widget? trailing}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: AppTheme.fontSizeBase,
                  color: onTap == null ? AppTheme.textMuted : AppTheme.textPrimary,
                ),
              ),
            ),
            trailing ?? const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildAssigneeButton() {
    final selectedUser = _selectedAssignee != null
        ? _assignableUsers.where((u) => u.accountId == _selectedAssignee).firstOrNull
        : null;

    return InkWell(
      onTap: () => _showAssigneePicker(),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            // Avatar
            if (selectedUser != null)
              Padding(
                padding: AppTheme.paddingRight12,
                child: CircleAvatar(
                  radius: 16,
                  backgroundImage: selectedUser.avatar48 != null ? NetworkImage(selectedUser.avatar48!) : null,
                  backgroundColor: AppTheme.primary,
                  child: selectedUser.avatar48 == null
                      ? Text(
                          selectedUser.displayName.isNotEmpty ? selectedUser.displayName[0].toUpperCase() : '?',
                          style: TextStyle(color: AppTheme.white, fontSize: AppTheme.fontSizeSm, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
              )
            else
              Padding(
                padding: AppTheme.paddingRight12,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.borderLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.person_off, color: AppTheme.white, size: AppTheme.iconSizeXs),
                  ),
                ),
              ),
            // Name
            Expanded(
              child: Text(
                _getSelectedAssigneeName(),
                style: const TextStyle(
                  fontSize: AppTheme.fontSizeBase,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  void _showIssueTypePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildPickerSheet(
        title: AppLocalizations.of(context).selectIssueType,
        items: _issueTypes.map((t) => {'id': t['id'], 'name': t['name']}).toList(),
        selectedId: _selectedIssueTypeId,
        onSelect: (id) {
          setState(() {
            _selectedIssueTypeId = id;
            _selectedParentKey = null; // Reset parent when changing issue type
            _parentIssues = [];
          });
          Navigator.pop(context);
          // Load parent issues after closing the modal
          if (_shouldShowParentField()) {
            _loadParentIssues();
          }
        },
      ),
    );
  }

  void _showPriorityPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildPickerSheet(
        title: AppLocalizations.of(context).selectPriority,
        items: [
          {'id': null, 'name': AppLocalizations.of(context).none},
          ..._priorities.map((p) => {'id': p['id'], 'name': p['name']}).toList(),
        ],
        selectedId: _selectedPriorityId,
        onSelect: (id) {
          setState(() => _selectedPriorityId = id);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showAssigneePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AssigneePickerSheet(
        projectKey: widget.projectKey!,
        assignableUsers: _assignableUsers,
        selectedAssignee: _selectedAssignee,
        onSelect: (accountId) {
          setState(() => _selectedAssignee = accountId);
        },
      ),
    );
  }

  void _showSprintPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildPickerSheet(
        title: AppLocalizations.of(context).selectSprint,
        items: [
          {'id': null, 'name': AppLocalizations.of(context).none},
          ..._sprints.map((s) => {'id': s.id, 'name': s.name}).toList(),
        ],
        selectedId: _selectedSprintId,
        onSelect: (id) {
          setState(() => _selectedSprintId = id is int ? id : null);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showParentPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ParentPickerSheet(
        projectKey: widget.projectKey!,
        parentIssues: _parentIssues,
        selectedParentKey: _selectedParentKey,
        selectedIssueTypeId: _selectedIssueTypeId,
        issueTypes: _issueTypes,
        onSelect: (key) {
          setState(() => _selectedParentKey = key);
        },
      ),
    );
  }

  Widget _buildPickerSheet({
    required String title,
    required List<Map<String, dynamic>> items,
    required dynamic selectedId,
    required Function(dynamic) onSelect,
  }) {
    return Container(
      padding: AppTheme.paddingTop16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(fontSize: AppTheme.fontSizeXl, fontWeight: FontWeight.w600)),
          const Divider(height: 24),
          ListView(
            shrinkWrap: true,
            children: items.map((item) {
              final isSelected = item['id'] == selectedId;
              return ListTile(
                title: Text(item['name']),
                trailing: isSelected ? const Icon(Icons.check, color: AppTheme.primary) : null,
                onTap: () => onSelect(item['id']),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _showDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: AppTheme.primary),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }
}

class _AssigneePickerSheet extends StatefulWidget {
  final String projectKey;
  final List<JiraUser> assignableUsers;
  final String? selectedAssignee;
  final Function(String?) onSelect;

  const _AssigneePickerSheet({
    required this.projectKey,
    required this.assignableUsers,
    required this.selectedAssignee,
    required this.onSelect,
  });

  @override
  State<_AssigneePickerSheet> createState() => _AssigneePickerSheetState();
}

class _AssigneePickerSheetState extends State<_AssigneePickerSheet> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;
  List<JiraUser> _displayUsers = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _displayUsers = widget.assignableUsers;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _searchAssignees(String query) {
    if (query.trim().isEmpty) {
      // Reset to full list when search is cleared
      setState(() => _isSearching = true);
      final api = context.read<JiraApiService>();
      api.getAssignableUsersForProject(widget.projectKey).then((users) {
        if (mounted) {
          setState(() {
            _displayUsers = users;
            _isSearching = false;
          });
        }
      });
      return;
    }

    // Call API with search query
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      setState(() => _isSearching = true);
      final api = context.read<JiraApiService>();
      api.getAssignableUsersForProject(widget.projectKey, query: query.trim()).then((users) {
        if (mounted) {
          setState(() {
            _displayUsers = users;
            _isSearching = false;
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      padding: AppTheme.paddingTop16,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with close button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).selectAssignee,
                    style: const TextStyle(fontSize: AppTheme.fontSizeXl, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    _debounceTimer?.cancel();
                    Navigator.pop(context);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).searchAssignee,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              onChanged: _searchAssignees,
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: _displayUsers.isEmpty && !_isSearching
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(AppLocalizations.of(context).noUsersFound, style: const TextStyle(color: AppTheme.textMuted)),
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      // Unassigned option (only show when not searching)
                      if (_searchController.text.isEmpty)
                        ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppTheme.border,
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(Icons.person_off, color: Colors.white, size: 20),
                            ),
                          ),
                          title: Text(AppLocalizations.of(context).unassigned, style: const TextStyle(fontStyle: FontStyle.italic)),
                          trailing: widget.selectedAssignee == null
                              ? const Icon(Icons.check, color: AppTheme.primary)
                              : null,
                          onTap: () {
                            widget.onSelect(null);
                            Navigator.pop(context);
                          },
                        ),
                      // Assignable users with avatars
                      ..._displayUsers.map((user) {
                        final isSelected = widget.selectedAssignee == user.accountId;
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundImage: user.avatar48 != null ? NetworkImage(user.avatar48!) : null,
                            backgroundColor: AppTheme.primary,
                            child: user.avatar48 == null
                                ? Text(
                                    user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          title: Text(user.displayName),
                          subtitle: user.emailAddress != null
                              ? Text(user.emailAddress!, style: const TextStyle(fontSize: AppTheme.fontSizeSm, color: AppTheme.textMuted))
                              : null,
                          trailing: isSelected ? const Icon(Icons.check, color: AppTheme.primary) : null,
                          onTap: () {
                            widget.onSelect(user.accountId);
                            Navigator.pop(context);
                          },
                        );
                      }),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ParentPickerSheet extends StatefulWidget {
  final String projectKey;
  final List<JiraIssue> parentIssues;
  final String? selectedParentKey;
  final String? selectedIssueTypeId;
  final List<Map<String, dynamic>> issueTypes;
  final Function(String?) onSelect;

  const _ParentPickerSheet({
    required this.projectKey,
    required this.parentIssues,
    required this.selectedParentKey,
    required this.selectedIssueTypeId,
    required this.issueTypes,
    required this.onSelect,
  });

  @override
  State<_ParentPickerSheet> createState() => _ParentPickerSheetState();
}

class _ParentPickerSheetState extends State<_ParentPickerSheet> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;
  List<JiraIssue> _displayIssues = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _displayIssues = widget.parentIssues;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _searchParentIssues(String query) {
    if (query.trim().isEmpty) {
      // Reset to full list when search is cleared
      setState(() {
        _displayIssues = widget.parentIssues;
        _isSearching = false;
      });
      return;
    }

    // Call API with search query
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isSearching = true);
      
      try {
        final api = context.read<JiraApiService>();
        
        // Build JQL based on issue type (same logic as _loadParentIssues)
        String jql = '';
        final typeName = widget.issueTypes
            .where((t) => t['id'] == widget.selectedIssueTypeId)
            .firstOrNull?['name'] as String?;

        if (typeName?.toLowerCase() == 'subtask') {
          final taskType = widget.issueTypes.where((t) => (t['name'] as String).toLowerCase() == 'task').firstOrNull;
          final storyType = widget.issueTypes.where((t) => (t['name'] as String).toLowerCase() == 'story').firstOrNull;
          final bugType = widget.issueTypes.where((t) => (t['name'] as String).toLowerCase() == 'bug').firstOrNull;
          
          final types = <String>[];
          if (taskType != null) types.add(taskType['id'].toString());
          if (storyType != null) types.add(storyType['id'].toString());
          if (bugType != null) types.add(bugType['id'].toString());
          
          if (types.isNotEmpty) {
            jql = 'project = ${widget.projectKey} AND issuetype in (${types.join(',')})';
          } else {
            jql = 'project = ${widget.projectKey} AND (issuetype = Task OR issuetype = Story OR issuetype = Bug)';
          }
        } else if (typeName?.toLowerCase() == 'story') {
          final epicType = widget.issueTypes.where((t) => (t['name'] as String).toLowerCase() == 'epic').firstOrNull;
          if (epicType != null) {
            jql = 'project = ${widget.projectKey} AND issuetype = ${epicType['id']}';
          } else {
            jql = 'project = ${widget.projectKey} AND issuetype = Epic';
          }
        }

        // Add search filter to JQL
        final searchTerm = query.trim();
        if (jql.isNotEmpty) {
          jql += ' AND (summary ~ "$searchTerm*" OR key = "$searchTerm") ORDER BY created DESC';
        }

        if (jql.isNotEmpty) {
          final issues = await api.searchIssues(jql, maxResults: 50);
          if (mounted) {
            setState(() {
              _displayIssues = issues;
              _isSearching = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _displayIssues = [];
              _isSearching = false;
            });
          }
        }
      } catch (e) {
        debugPrint('Error searching parent issues: $e');
        if (mounted) {
          setState(() => _isSearching = false);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      padding: AppTheme.paddingTop16,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with close button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Select Parent Issue',
                    style: TextStyle(fontSize: AppTheme.fontSizeXl, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    _debounceTimer?.cancel();
                    Navigator.pop(context);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).searchParentIssue,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              onChanged: _searchParentIssues,
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: _displayIssues.isEmpty && !_isSearching
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(AppLocalizations.of(context).noIssuesFound, style: const TextStyle(color: AppTheme.textMuted)),
                    ),
                  )
                : ListView.builder(
                    itemCount: (_searchController.text.isEmpty ? 1 : 0) + _displayIssues.length,
                    itemBuilder: (context, index) {
                      // "None" option when not searching
                      if (_searchController.text.isEmpty && index == 0) {
                        return ListTile(
                          title: Text(AppLocalizations.of(context).none, style: const TextStyle(fontStyle: FontStyle.italic)),
                          trailing: widget.selectedParentKey == null
                              ? const Icon(Icons.check, color: AppTheme.primary)
                              : null,
                          onTap: () {
                            widget.onSelect(null);
                            Navigator.pop(context);
                          },
                        );
                      }
                      
                      // Parent issues
                      final issueIndex = _searchController.text.isEmpty ? index - 1 : index;
                      final issue = _displayIssues[issueIndex];
                      final isSelected = widget.selectedParentKey == issue.key;
                      
                      return ListTile(
                        title: Text(issue.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          issue.fields.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: AppTheme.fontSizeSm, color: AppTheme.textMuted),
                        ),
                        trailing: isSelected ? const Icon(Icons.check, color: AppTheme.primary) : null,
                        onTap: () {
                          widget.onSelect(issue.key);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
