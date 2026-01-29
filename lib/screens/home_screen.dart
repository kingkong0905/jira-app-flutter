import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/jira_models.dart';
import '../services/storage_service.dart';
import '../services/jira_api_service.dart';
import '../widgets/logo.dart';
import '../widgets/issue_card.dart';
import 'issue_detail_screen.dart';

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
  int _activeTab = 0; // 0 = Board, 1 = Backlog
  bool _boardDropdownOpen = false;

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
        if (_activeTab == 0 && _activeSprint != null) {
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
          final backlog = await api.getBacklogIssues(
            boardId,
            assignee: _selectedAssignee == 'all' ? null : _selectedAssignee,
          );
          setState(() {
            _backlogIssues = backlog;
            _issues = [];
            _assignees = assigneesData;
            _loading = false;
          });
          return;
        }
      }

      final issues = await api.getBoardIssues(boardId);
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
          Expanded(
            child: _tab(0, 'Board', Icons.dashboard),
          ),
          Expanded(
            child: _tab(1, 'Backlog', Icons.inventory_2),
          ),
        ],
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
    return Expanded(
      child: Column(
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
      ),
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
}

