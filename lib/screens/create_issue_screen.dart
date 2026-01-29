import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/jira_models.dart';
import '../services/jira_api_service.dart';
import 'package:intl/intl.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../utils/adf_quill_converter.dart';

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
      _showSnack('No project selected', isError: true);
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
    final error = await api.createIssue(
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

    setState(() => _creating = false);

    if (error == null) {
      _showSnack('Issue created successfully');
      widget.onIssueCreated();
    } else {
      _showSnack(error, isError: true);
    }
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
        backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF0052CC),
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
    if (_selectedPriorityId == null) return 'None';
    final priority = _priorities.where((p) => p['id'] == _selectedPriorityId).firstOrNull;
    return priority?['name'] as String? ?? 'None';
  }

  String _getSelectedAssigneeName() {
    if (_selectedAssignee == null) return 'Unassigned';
    final user = _assignableUsers.where((u) => u.accountId == _selectedAssignee).firstOrNull;
    return user?.displayName ?? 'Unassigned';
  }

  String _getSelectedSprintName() {
    if (_selectedSprintId == null) return 'None';
    final sprint = _sprints.where((s) => s.id == _selectedSprintId).firstOrNull;
    return sprint?.name ?? 'None';
  }

  String _getSelectedParentName() {
    if (_selectedParentKey == null) return 'None';
    final parent = _parentIssues.where((i) => i.key == _selectedParentKey).firstOrNull;
    return parent != null ? '${parent.key}: ${parent.fields.summary}' : 'None';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0052CC),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: const Text('Create Issue', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Issue Type
                  _buildFieldLabel('Issue Type', required: true),
                  const SizedBox(height: 8),
                  _buildDropdownButton(
                    value: _getSelectedIssueTypeName(),
                    onTap: () => _showIssueTypePicker(),
                  ),
                  const SizedBox(height: 20),

                  // Priority
                  _buildFieldLabel('Priority'),
                  const SizedBox(height: 8),
                  _buildDropdownButton(
                    value: _getSelectedPriorityName(),
                    onTap: () => _showPriorityPicker(),
                  ),
                  const SizedBox(height: 20),

                  // Parent (conditional)
                  if (_shouldShowParentField()) ...[
                    _buildFieldLabel('Parent'),
                    const SizedBox(height: 8),
                    _buildDropdownButton(
                      value: _loadingParents 
                          ? 'Loading...' 
                          : (_parentIssues.isEmpty 
                              ? 'No parent issues found - Create Epic/Story first' 
                              : _getSelectedParentName()),
                      onTap: _loadingParents || _parentIssues.isEmpty ? null : () => _showParentPicker(),
                    ),
                    if (_parentIssues.isEmpty && !_loadingParents) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Create an Epic or Story issue first to use as parent',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6B778C), fontStyle: FontStyle.italic),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],

                  // Summary
                  _buildFieldLabel('Summary', required: true),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _summaryController,
                    decoration: _inputDecoration('Enter issue summary'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),

                  // Description
                  _buildFieldLabel('Description'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFDFE1E6)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        // Toolbar
                        Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFFF4F5F7),
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
                            color: Colors.white,
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
                  const SizedBox(height: 20),

                  // Assignee
                  _buildFieldLabel('Assignee'),
                  const SizedBox(height: 8),
                  _buildAssigneeButton(),
                  const SizedBox(height: 20),

                  // Due Date
                  _buildFieldLabel('Due Date'),
                  const SizedBox(height: 8),
                  _buildDropdownButton(
                    value: _dueDate != null ? DateFormat('MMM dd, yyyy').format(_dueDate!) : 'No due date',
                    onTap: () => _showDatePicker(),
                    trailing: _dueDate != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () => setState(() => _dueDate = null),
                          )
                        : null,
                  ),
                  const SizedBox(height: 20),

                  // Story Points
                  _buildFieldLabel('Story Points'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _storyPointsController,
                    decoration: _inputDecoration('Enter story points (e.g., 3, 5, 8)'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 20),

                  // Sprint
                  _buildFieldLabel('Sprint'),
                  const SizedBox(height: 8),
                  _buildDropdownButton(
                    value: _sprints.isEmpty ? 'No sprints available' : _getSelectedSprintName(),
                    onTap: _sprints.isEmpty ? null : () => _showSprintPicker(),
                  ),
                  const SizedBox(height: 32),

                  // Create Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _creating ? null : _handleCreate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0052CC),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: _creating
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Create Issue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFieldLabel(String label, {bool required = false}) {
    return Text.rich(
      TextSpan(
        text: label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF172B4D)),
        children: required
            ? [const TextSpan(text: ' *', style: TextStyle(color: Colors.red))]
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDFE1E6)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: onTap == null ? Colors.grey : const Color(0xFF172B4D),
                ),
              ),
            ),
            trailing ?? const Icon(Icons.arrow_drop_down, color: Color(0xFF6B778C)),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDFE1E6)),
        ),
        child: Row(
          children: [
            // Avatar
            if (selectedUser != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: CircleAvatar(
                  radius: 16,
                  backgroundImage: selectedUser.avatar48 != null ? NetworkImage(selectedUser.avatar48!) : null,
                  backgroundColor: const Color(0xFF0052CC),
                  child: selectedUser.avatar48 == null
                      ? Text(
                          selectedUser.displayName.isNotEmpty ? selectedUser.displayName[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.person_off, color: Colors.white, size: 16),
                  ),
                ),
              ),
            // Name
            Expanded(
              child: Text(
                _getSelectedAssigneeName(),
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF172B4D),
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Color(0xFF6B778C)),
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
        borderSide: const BorderSide(color: Color(0xFFDFE1E6)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDFE1E6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF0052CC), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  void _showIssueTypePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildPickerSheet(
        title: 'Select Issue Type',
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
        title: 'Select Priority',
        items: [
          {'id': null, 'name': 'None'},
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
        title: 'Select Sprint',
        items: [
          {'id': null, 'name': 'None'},
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
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const Divider(height: 24),
          ListView(
            shrinkWrap: true,
            children: items.map((item) {
              final isSelected = item['id'] == selectedId;
              return ListTile(
                title: Text(item['name']),
                trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF0052CC)) : null,
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
            colorScheme: const ColorScheme.light(primary: Color(0xFF0052CC)),
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
      padding: const EdgeInsets.only(top: 16),
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
                    'Select Assignee',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
                hintText: 'Search assignee...',
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
                  borderSide: const BorderSide(color: Color(0xFFDFE1E6)),
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
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No users found', style: TextStyle(color: Color(0xFF6B778C))),
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
                              color: Colors.grey.shade400,
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(Icons.person_off, color: Colors.white, size: 20),
                            ),
                          ),
                          title: const Text('Unassigned', style: TextStyle(fontStyle: FontStyle.italic)),
                          trailing: widget.selectedAssignee == null
                              ? const Icon(Icons.check, color: Color(0xFF0052CC))
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
                            backgroundColor: const Color(0xFF0052CC),
                            child: user.avatar48 == null
                                ? Text(
                                    user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          title: Text(user.displayName),
                          subtitle: user.emailAddress != null
                              ? Text(user.emailAddress!, style: const TextStyle(fontSize: 12, color: Color(0xFF6B778C)))
                              : null,
                          trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF0052CC)) : null,
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
      padding: const EdgeInsets.only(top: 16),
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
                hintText: 'Search parent issue...',
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
                  borderSide: const BorderSide(color: Color(0xFFDFE1E6)),
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
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No issues found', style: TextStyle(color: Color(0xFF6B778C))),
                    ),
                  )
                : ListView.builder(
                    itemCount: (_searchController.text.isEmpty ? 1 : 0) + _displayIssues.length,
                    itemBuilder: (context, index) {
                      // "None" option when not searching
                      if (_searchController.text.isEmpty && index == 0) {
                        return ListTile(
                          title: const Text('None', style: TextStyle(fontStyle: FontStyle.italic)),
                          trailing: widget.selectedParentKey == null
                              ? const Icon(Icons.check, color: Color(0xFF0052CC))
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
                          style: const TextStyle(fontSize: 12, color: Color(0xFF6B778C)),
                        ),
                        trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF0052CC)) : null,
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
