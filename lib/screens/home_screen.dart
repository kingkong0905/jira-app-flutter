import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/jira_models.dart';
import '../services/storage_service.dart';
import '../services/jira_api_service.dart';
import '../widgets/logo.dart';
import '../widgets/issue_card.dart';
import '../widgets/create_sprint_dialog.dart';
import 'issue_detail_screen.dart';
import 'create_issue_screen.dart';

/// Home: board selector, Board/Backlog tabs, assignee filter, issue list (same flow as reference app).
class HomeScreen extends StatefulWidget {
  final VoidCallback onOpenSettings;

  const HomeScreen({super.key, required this.onOpenSettings});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<JiraBoard> _boards = [];
  JiraBoard? _selectedBoard;
  List<JiraIssue> _issues = [];
  List<JiraIssue> _backlogIssues = [];
  List<JiraSprint> _sprints = [];
  JiraSprint? _activeSprint;
  List<BoardAssignee> _assignees = [];
  String _selectedAssignee = 'all';
  String _boardSearch = '';
  String _issueSearch = '';
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  int _boardsStartAt = 0;
  bool _hasMoreBoards = true;
  bool _loadingMoreBoards = false;
  int _activeTab = 0; // 0 = Board, 1 = Backlog, 2 = Timeline
  bool _boardDropdownOpen = false;
  Set<int> _collapsedSprints = {};
  bool _backlogCollapsed = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final storage = context.read<StorageService>();
    final api = context.read<JiraApiService>();
    try {
      final config = await storage.getConfig();
      if (config != null) {
        api.initialize(config);
        final defaultId = await storage.getDefaultBoardId();
        await _loadBoards(reset: true, defaultBoardId: defaultId);
      }
    } catch (e) {
      _showSnack('Failed to initialize. Check settings.', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadBoards({bool reset = true, int? defaultBoardId}) async {
    final api = context.read<JiraApiService>();
    setState(() {
      _error = null;
      if (reset) _boardsStartAt = 0;
    });
    try {
      final startAt = reset ? 0 : _boardsStartAt;
      final res = await api.getBoards(
        startAt: startAt,
        maxResults: 50,
        searchQuery: _boardSearch.isEmpty ? null : _boardSearch,
      );
      JiraBoard? toSelect;
      if (reset && res.boards.isNotEmpty) {
        if (defaultBoardId != null) {
          final def = res.boards.where((b) => b.id == defaultBoardId).firstOrNull;
          if (def != null) {
            toSelect = def;
            final others = res.boards.where((b) => b.id != defaultBoardId).toList();
            setState(() => _boards = [def, ...others]);
          } else {
            try {
              final b = await api.getBoardById(defaultBoardId);
              if (b != null) {
                toSelect = b;
                setState(() => _boards = [b, ...res.boards]);
              } else {
                setState(() => _boards = res.boards);
                toSelect = res.boards.first;
              }
            } catch (_) {
              setState(() => _boards = res.boards);
              toSelect = res.boards.first;
            }
          }
        } else {
          setState(() => _boards = res.boards);
          toSelect = res.boards.first;
        }
      } else {
        setState(() => _boards = [..._boards, ...res.boards]);
      }
      setState(() {
        _boardsStartAt = startAt + 50;
        _hasMoreBoards = !res.isLast;
        if (toSelect != null) _selectedBoard = toSelect;
      });
      if (toSelect != null) await _loadIssuesForBoard(toSelect.id);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('JiraApiException(', '').replaceAll(')', '');
        if (_error != null && _error!.length > 120) _error = '${_error!.substring(0, 120)}...';
      });
      _showSnack('Failed to load boards. Check credentials and connection.', isError: true);
    }
  }

  Future<void> _loadIssuesForBoard(int boardId) async {
    final api = context.read<JiraApiService>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final assigneesData = await api.getBoardAssignees(boardId);
      final board = _boards.where((b) => b.id == boardId).firstOrNull ?? _selectedBoard;
      final isKanban = board?.type.toLowerCase() == 'kanban';

      if (!isKanban) {
        final sprintsData = await api.getSprintsForBoard(boardId);
        setState(() {
          _sprints = sprintsData;
          _activeSprint = sprintsData.where((s) => s.state == 'active').firstOrNull;
        });
        if ((_activeTab == 0 || _activeTab == 2) && _activeSprint != null) {
          final issues = await api.getSprintIssues(
            boardId,
            _activeSprint!.id,
            assignee: _selectedAssignee == 'all' ? null : _selectedAssignee,
          );
          setState(() {
            _issues = issues;
            _backlogIssues = [];
            _assignees = assigneesData;
            _loading = false;
          });
          return;
        }
        if (_activeTab == 1) {
          // Backlog tab: Load backlog issues
          final backlog = await api.getBacklogIssues(
            boardId,
            assignee: _selectedAssignee == 'all' ? null : _selectedAssignee,
          );
          
          // Load all sprint issues for backlog view
          final allSprintIssues = <JiraIssue>[];
          final issueKeys = <String>{};
          for (final sprint in _sprints) {
            try {
              final sprintIssues = await api.getSprintIssues(
                boardId,
                sprint.id,
                assignee: _selectedAssignee == 'all' ? null : _selectedAssignee,
              );
              // Deduplicate by issue key
              for (final issue in sprintIssues) {
                if (!issueKeys.contains(issue.key)) {
                  issueKeys.add(issue.key);
                  allSprintIssues.add(issue);
                }
              }
            } catch (e) {
              debugPrint('Error loading sprint ${sprint.id}: $e');
              // Continue loading other sprints
            }
          }
          
          setState(() {
            _backlogIssues = backlog;
            _issues = allSprintIssues;
            _assignees = assigneesData;
            _loading = false;
          });
          return;
        }
        // Scrum but no active sprint for Board/Timeline: show empty
        setState(() {
          _issues = [];
          _assignees = assigneesData;
          _loading = false;
        });
        return;
      }

      final assigneeParam = _selectedAssignee == 'all' ? null : _selectedAssignee;
      final issues = await api.getBoardIssues(boardId, assignee: assigneeParam);
      setState(() {
        _sprints = [];
        _activeSprint = null;
        _issues = issues;
        _backlogIssues = [];
        _assignees = assigneesData;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _issues = [];
        _backlogIssues = [];
        _loading = false;
      });
      _showSnack('Failed to load issues.', isError: true);
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    _boardsStartAt = 0;
    _hasMoreBoards = true;
    if (_selectedBoard != null) {
      await _loadIssuesForBoard(_selectedBoard!.id);
    } else {
      await _loadBoards(reset: true);
    }
    if (mounted) setState(() => _refreshing = false);
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

  List<JiraIssue> get _displayIssues {
    if (_activeTab == 1) return _backlogIssues;
    // Board and Timeline both use _issues (sprint for scrum, board for kanban)
    return _issues;
  }

  List<JiraIssue> get _filteredIssues {
    var list = _displayIssues.where((i) => i.fields.issuetype.name.toLowerCase() != 'epic').toList();
    if (_issueSearch.trim().isEmpty) return list;
    final q = _issueSearch.toLowerCase().trim();
    return list.where((i) {
      return i.key.toLowerCase().contains(q) || i.fields.summary.toLowerCase().contains(q);
    }).toList();
  }

  Map<String, List<JiraIssue>> get _groupedByStatus {
    final map = <String, List<JiraIssue>>{};
    for (final i in _filteredIssues) {
      final s = i.fields.status.name;
      map.putIfAbsent(s, () => []).add(i);
    }
    return map;
  }

  /// Timeline groups: Overdue, Today, This week, Next week, Later, No due date
  Map<String, List<JiraIssue>> get _groupedByDueDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endOfWeek = today.add(const Duration(days: 7));
    final endOfNextWeek = today.add(const Duration(days: 14));
    final map = <String, List<JiraIssue>>{
      'Overdue': [],
      'Today': [],
      'This week': [],
      'Next week': [],
      'Later': [],
      'No due date': [],
    };
    for (final i in _filteredIssues) {
      final d = i.fields.duedate;
      if (d == null || d.isEmpty) {
        map['No due date']!.add(i);
        continue;
      }
      DateTime? parsed;
      try {
        parsed = DateTime.parse(d);
      } catch (_) {}
      if (parsed == null) {
        map['No due date']!.add(i);
        continue;
      }
      final day = DateTime(parsed.year, parsed.month, parsed.day);
      if (day.isBefore(today)) {
        map['Overdue']!.add(i);
      } else if (day == today) {
        map['Today']!.add(i);
      } else if (day.isBefore(endOfWeek)) {
        map['This week']!.add(i);
      } else if (day.isBefore(endOfNextWeek)) {
        map['Next week']!.add(i);
      } else {
        map['Later']!.add(i);
      }
    }
    return map;
  }

  /// Group issues by sprint for Backlog tab (matching React Native logic)
  List<({String sprint, int? sprintId, List<JiraIssue> issues})> get _groupedBySprint {
    if (_activeTab != 1) return [];
    
    final groups = <({String sprint, int? sprintId, List<JiraIssue> issues})>[];
    final addedIssueKeys = <String>{};
    
    // Add active sprint at the top (always show, even if empty)
    if (_activeSprint != null) {
      final activeSprintIssues = _issues.where((issue) {
        if (issue.fields.sprint != null && 
            issue.fields.sprint!.id == _activeSprint!.id && 
            !addedIssueKeys.contains(issue.key)) {
          addedIssueKeys.add(issue.key);
          return true;
        }
        return false;
      }).toList();
      
      groups.add((
        sprint: _activeSprint!.name,
        sprintId: _activeSprint!.id,
        issues: activeSprintIssues,
      ));
    }
    
    // Add other sprints (only future sprints, exclude closed/completed)
    final otherSprints = _sprints
        .where((sprint) {
          // Exclude active sprint (already shown above)
          if (_activeSprint != null && sprint.id == _activeSprint!.id) return false;
          // Only include future sprints
          return sprint.state == 'future';
        })
        .toList()
      ..sort((a, b) {
        // Sort by start date if available
        if (a.startDate != null && b.startDate != null) {
          return DateTime.parse(a.startDate!).compareTo(DateTime.parse(b.startDate!));
        }
        if (a.startDate != null) return -1;
        if (b.startDate != null) return 1;
        return 0;
      });
    
    for (final sprint in otherSprints) {
      final sprintIssues = _issues.where((issue) {
        if (issue.fields.sprint != null && 
            issue.fields.sprint!.id == sprint.id && 
            !addedIssueKeys.contains(issue.key)) {
          addedIssueKeys.add(issue.key);
          return true;
        }
        return false;
      }).toList();
      
      groups.add((
        sprint: sprint.name,
        sprintId: sprint.id,
        issues: sprintIssues,
      ));
    }
    
    // Add backlog issues (exclude Done status and issues already in sprints)
    final filteredBacklog = _backlogIssues.where((issue) {
      // Exclude Epic issue types
      if (issue.fields.issuetype.name.toLowerCase() == 'epic') return false;
      
      // Exclude issues with Done status
      if (issue.fields.status.statusCategory.key == 'done') return false;
      
      // Exclude issues that already have a sprint assigned
      if (issue.fields.sprint != null) return false;
      
      // Apply search filter
      if (_issueSearch.trim().isNotEmpty) {
        final q = _issueSearch.toLowerCase().trim();
        if (! (issue.key.toLowerCase().contains(q) || 
               issue.fields.summary.toLowerCase().contains(q))) {
          return false;
        }
      }
      
      return true;
    }).toList();
    
    if (filteredBacklog.isNotEmpty) {
      groups.add((
        sprint: 'Backlog',
        sprintId: null,
        issues: filteredBacklog,
      ));
    }
    
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_refreshing && _boards.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF0052CC)),
              const SizedBox(height: 16),
              Text('Loading Jira Board...', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_error != null && _error!.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: const Color(0xFFFFE5E5),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFBF2600), fontSize: 13)),
              ),
            if (_boards.isNotEmpty) _buildBoardSelector(),
            if (_selectedBoard != null) _buildTabs(),
            if (_selectedBoard != null && _selectedBoard!.type.toLowerCase() != 'kanban' && _activeSprint != null && _activeTab == 0)
              _buildSprintCard(),
            if (_selectedBoard != null) _buildAssigneeFilter(),
            if (_selectedBoard != null) _buildIssueSearch(),
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0052CC),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          const Logo(),
          const Spacer(),
          IconButton(
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings, color: Colors.white, size: 26),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardSelector() {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => setState(() => _boardDropdownOpen = !_boardDropdownOpen),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
          ),
          child: Row(
            children: [
              Text(
                'Board:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _selectedBoard != null
                      ? '${_selectedBoard!.name} (${_selectedBoard!.type})'
                      : 'Select a board...',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF172B4D)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(_boardDropdownOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: const Color(0xFF5E6C84)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    final isKanban = _selectedBoard!.type.toLowerCase() == 'kanban';
    if (isKanban) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      child: Row(
        children: [
          Expanded(child: _tab(0, 'Board', Icons.dashboard)),
          Expanded(child: _tab(1, 'Backlog', Icons.inventory_2)),
          Expanded(child: _tab(2, 'Timeline', Icons.timeline)),
        ],
      ),
    );
  }

  Widget _buildAssigneeFilter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          Text(
            'Assignee:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _assigneeChip('All', 'all'),
                  _assigneeChip('Unassigned', 'unassigned'),
                  ..._assignees.map((a) => _assigneeChip(a.name, a.key)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _assigneeChip(String label, String value) {
    final selected = _selectedAssignee == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 13, color: selected ? Colors.white : null)),
        selected: selected,
        onSelected: (sel) async {
          if (!sel) return;
          setState(() => _selectedAssignee = value);
          if (_selectedBoard != null) await _loadIssuesForBoard(_selectedBoard!.id);
        },
        selectedColor: const Color(0xFF0052CC),
        checkmarkColor: Colors.white,
      ),
    );
  }

  Widget _tab(int index, String label, IconData icon) {
    final active = _activeTab == index;
    return InkWell(
      onTap: () async {
        setState(() => _activeTab = index);
        if (_selectedBoard != null) await _loadIssuesForBoard(_selectedBoard!.id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? const Color(0xFF0052CC) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: active ? const Color(0xFF0052CC) : const Color(0xFF6B778C)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? const Color(0xFF0052CC) : const Color(0xFF6B778C),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSprintCard() {
    if (_activeSprint == null) return const SizedBox.shrink();
    final s = _activeSprint!;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(14),
        border: const Border(left: BorderSide(color: Color(0xFF0052CC), width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('🏃 ${s.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF172B4D))),
            ],
          ),
          if (s.startDate != null || s.endDate != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (s.startDate != null)
                  Text('Start: ${_formatDate(s.startDate!)}', style: const TextStyle(fontSize: 12, color: Color(0xFF5E6C84))),
                if (s.startDate != null && s.endDate != null) const SizedBox(width: 16),
                if (s.endDate != null)
                  Text('End: ${_formatDate(s.endDate!)}', style: const TextStyle(fontSize: 12, color: Color(0xFF5E6C84))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.month}/${d.day}/${d.year}';
    } catch (_) {
      return iso;
    }
  }

  Widget _buildIssueSearch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _issueSearch = v),
              decoration: InputDecoration(
                hintText: 'Search issues...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Create Sprint Button (Backlog tab only)
          if (_activeTab == 1 && _selectedBoard?.type?.toLowerCase() != 'kanban')
            Material(
              color: const Color(0xFF6554C0),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _openCreateSprint,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, color: Colors.white, size: 20),
                      SizedBox(width: 6),
                      Text(
                        'Sprint',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_activeTab == 1 && _selectedBoard?.type?.toLowerCase() != 'kanban')
            const SizedBox(width: 12),
          // Create Issue Button
          Material(
            color: const Color(0xFF0052CC),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _openCreateIssue,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, color: Colors.white, size: 20),
                    SizedBox(width: 6),
                    Text(
                      'Create',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_boardDropdownOpen) {
      return _buildBoardDropdown();
    }
    if (_selectedBoard == null) {
      return const Center(
        child: Text('Select a board to view issues', style: TextStyle(color: Color(0xFF5E6C84), fontSize: 15)),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF0052CC)));
    }
    if (_filteredIssues.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('No issues found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF42526E))),
            const SizedBox(height: 8),
            Text(
              _selectedBoard != null ? 'This board has no issues' : 'Select a board to view issues',
              style: const TextStyle(fontSize: 15, color: Color(0xFF5E6C84)),
            ),
          ],
        ),
      );
    }

    if (_activeTab == 0 && _selectedBoard!.type.toLowerCase() != 'kanban' && _groupedByStatus.isNotEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        color: const Color(0xFF0052CC),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          itemCount: _groupedByStatus.length,
          itemBuilder: (context, idx) {
            final entry = _groupedByStatus.entries.elementAt(idx);
            final statusColor = _statusColor(entry.value.first.fields.status.statusCategory.key);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${entry.key} (${entry.value.length})',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                ...entry.value.map((issue) => IssueCard(
                      issue: issue,
                      onTap: () => _openIssue(issue.key),
                    )),
              ],
            );
          },
        ),
      );
    }

    if (_activeTab == 2 && _groupedByDueDate.entries.any((e) => e.value.isNotEmpty)) {
      final timelineColors = <String, Color>{
        'Overdue': const Color(0xFFDE350B),
        'Today': const Color(0xFF00875A),
        'This week': const Color(0xFF0052CC),
        'Next week': const Color(0xFF6554C0),
        'Later': const Color(0xFF5E6C84),
        'No due date': const Color(0xFF97A0AF),
      };
      return RefreshIndicator(
        onRefresh: _refresh,
        color: const Color(0xFF0052CC),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          itemCount: _groupedByDueDate.entries.where((e) => e.value.isNotEmpty).length,
          itemBuilder: (context, idx) {
            final entry = _groupedByDueDate.entries.where((e) => e.value.isNotEmpty).elementAt(idx);
            final color = timelineColors[entry.key] ?? const Color(0xFF5E6C84);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.event, size: 18, color: color),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${entry.key} (${entry.value.length})',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                ...entry.value.map((issue) => IssueCard(
                      issue: issue,
                      onTap: () => _openIssue(issue.key),
                    )),
              ],
            );
          },
        ),
      );
    }

    // Backlog tab: show sprint-grouped issues
    if (_activeTab == 1 && _groupedBySprint.isNotEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        color: const Color(0xFF0052CC),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          itemCount: _groupedBySprint.length,
          itemBuilder: (context, idx) {
            final group = _groupedBySprint[idx];
            final isBacklog = group.sprintId == null;
            final isActiveSprint = _activeSprint != null && group.sprintId == _activeSprint!.id;
            
            // Calculate stats
            final doneCount = group.issues.where((i) => i.fields.status.statusCategory.key == 'done').length;
            final inProgressCount = group.issues.where((i) => i.fields.status.statusCategory.key == 'indeterminate').length;
            final todoCount = group.issues.where((i) => i.fields.status.statusCategory.key != 'done' && i.fields.status.statusCategory.key != 'indeterminate').length;
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isBacklog) {
                        _backlogCollapsed = !_backlogCollapsed;
                      } else if (group.sprintId != null) {
                        if (_collapsedSprints.contains(group.sprintId!)) {
                          _collapsedSprints.remove(group.sprintId!);
                        } else {
                          _collapsedSprints.add(group.sprintId!);
                        }
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isActiveSprint ? const Color(0xFFE3F2FD) : const Color(0xFFF4F5F7),
                      borderRadius: BorderRadius.circular(8),
                      border: isActiveSprint
                          ? Border.all(color: const Color(0xFF0052CC), width: 2)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          (isBacklog ? _backlogCollapsed : (group.sprintId != null && _collapsedSprints.contains(group.sprintId!)))
                              ? Icons.chevron_right
                              : Icons.expand_more,
                          size: 20,
                          color: const Color(0xFF42526E),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      isBacklog ? '📋 ${group.sprint}' : '🏃 ${group.sprint}',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF172B4D),
                                      ),
                                    ),
                                  ),
                                  if (isActiveSprint)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0052CC),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'ACTIVE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (group.issues.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${group.issues.length} issues  •  ✅ $doneCount  •  🔄 $inProgressCount  •  📝 $todoCount',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF5E6C84),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Show issues if not collapsed
                if (!(isBacklog ? _backlogCollapsed : (group.sprintId != null && _collapsedSprints.contains(group.sprintId!))))
                  ...group.issues.map((issue) => IssueCard(
                        issue: issue,
                        onTap: () => _openIssue(issue.key),
                      )),
                const SizedBox(height: 12),
              ],
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFF0052CC),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: _filteredIssues.length,
        itemBuilder: (context, i) {
          final issue = _filteredIssues[i];
          return IssueCard(issue: issue, onTap: () => _openIssue(issue.key));
        },
      ),
    );
  }

  Color _statusColor(String? key) {
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

  Widget _buildBoardDropdown() {
    // Do not wrap in Expanded: caller already uses Expanded(child: _buildContent())
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: TextField(
              onChanged: (v) async {
                setState(() => _boardSearch = v);
                await _loadBoards(reset: true);
              },
              decoration: InputDecoration(
                hintText: 'Search boards...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _boards.length + (_hasMoreBoards ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= _boards.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: _loadingMoreBoards
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : TextButton(
                              onPressed: () async {
                                setState(() => _loadingMoreBoards = true);
                                await _loadBoards(reset: false);
                                setState(() => _loadingMoreBoards = false);
                              },
                              child: const Text('Load more'),
                            ),
                    ),
                  );
                }
                final b = _boards[i];
                final selected = _selectedBoard?.id == b.id;
                return ListTile(
                  leading: Icon(
                    b.type.toLowerCase() == 'kanban' ? Icons.view_kanban : Icons.directions_run,
                    color: selected ? const Color(0xFF0052CC) : null,
                  ),
                  title: Text(
                    b.name,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? const Color(0xFF0052CC) : const Color(0xFF172B4D),
                    ),
                  ),
                  subtitle: b.location?.projectName != null ? Text('📁 ${b.location!.projectName}') : null,
                  trailing: selected ? const Icon(Icons.check, color: Color(0xFF0052CC)) : null,
                  onTap: () async {
                    setState(() {
                      _selectedBoard = b;
                      _boardDropdownOpen = false;
                    });
                    await _loadIssuesForBoard(b.id);
                  },
                );
                },
              ),
            ),
        ],
    );
  }

  void _openIssue(String key) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => IssueDetailScreen(
          issueKey: key,
          onBack: () => Navigator.of(context).pop(),
          onRefresh: () {
            if (_selectedBoard != null) _loadIssuesForBoard(_selectedBoard!.id);
          },
        ),
      ),
    );
  }

  void _openCreateSprint() {
    if (_selectedBoard == null) {
      _showSnack('Please select a board first', isError: true);
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => CreateSprintDialog(
        onCreate: (name, goal, startDate, endDate) async {
          Navigator.of(context).pop();
          await _handleCreateSprint(name, goal, startDate, endDate);
        },
      ),
    );
  }

  Future<void> _handleCreateSprint(
    String name,
    String goal,
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    if (_selectedBoard == null) return;

    setState(() => _loading = true);

    try {
      final api = context.read<JiraApiService>();
      
      // Format dates to ISO 8601
      final String? formattedStartDate = startDate != null
          ? DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(startDate.toUtc())
          : null;
      final String? formattedEndDate = endDate != null
          ? DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(endDate.toUtc())
          : null;

      final error = await api.createSprint(
        boardId: _selectedBoard!.id,
        name: name,
        goal: goal.isNotEmpty ? goal : null,
        startDate: formattedStartDate,
        endDate: formattedEndDate,
      );

      if (error != null) {
        _showSnack('Failed to create sprint: $error', isError: true);
      } else {
        _showSnack('Sprint created successfully');
        await _refresh();
      }
    } catch (e) {
      _showSnack('Error creating sprint: $e', isError: true);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _openCreateIssue() {
    if (_selectedBoard == null) {
      _showSnack('Please select a board first', isError: true);
      return;
    }

    final projectKey = _selectedBoard!.location?.projectKey;
    if (projectKey == null || projectKey.isEmpty) {
      _showSnack('Selected board has no project key', isError: true);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CreateIssueScreen(
          boardId: _selectedBoard!.id,
          projectKey: projectKey,
          onBack: () => Navigator.of(context).pop(),
          onIssueCreated: () {
            Navigator.of(context).pop();
            _refresh();
          },
        ),
      ),
    );
  }
}
