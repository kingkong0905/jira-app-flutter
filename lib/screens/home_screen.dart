import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/jira_models.dart';
import '../services/storage_service.dart';
import '../services/jira_api_service.dart';
import '../l10n/app_localizations.dart';
import '../l10n/locale_notifier.dart';
import '../widgets/logo.dart';
import '../widgets/issue_card.dart';
import '../widgets/create_sprint_dialog.dart';
import '../widgets/update_sprint_dialog.dart';
import 'issue_detail_screen.dart';
import 'create_issue_screen.dart';
import 'sentry_screen.dart';
import 'settings_screen.dart';

/// Home: board selector, Board/Backlog tabs, assignee filter, issue list (same flow as reference app).
class HomeScreen extends StatefulWidget {
  final VoidCallback onOpenSettings;
  final VoidCallback onLogout;

  const HomeScreen({super.key, required this.onOpenSettings, required this.onLogout});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<JiraBoard> _boards = [];
  JiraBoard? _selectedBoard;
  List<JiraIssue> _issues = [];
  List<JiraIssue> _backlogIssues = [];
  bool _backlogHasMore = false;
  bool _backlogLoadingMore = false;
  bool _backlogUseJql = false;
  String? _backlogProjectKey;
  List<JiraSprint> _sprints = [];
  JiraSprint? _activeSprint;
  List<BoardAssignee> _assignees = [];
  String _selectedAssignee = 'all';
  String _boardSearch = '';
  String _issueSearch = '';
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  bool _errorDismissed = false;
  int _boardsStartAt = 0;
  bool _hasMoreBoards = true;
  bool _loadingMoreBoards = false;
  int _activeTab = 0; // 0 = Board, 1 = Backlog, 2 = Timeline
  bool _boardDropdownOpen = false;
  Set<int> _collapsedSprints = {};
  bool _backlogCollapsed = false;
  JiraUser? _currentUser;
  bool _sentryTokenConfigured = false;
  Timer? _assigneeDebounceTimer;
  Timer? _boardSearchDebounceTimer;

  /// Backlog screen shows User Story, Story, Bug, Task (no Epic, Sub-task, etc.)
  static const _backlogAllowedIssueTypes = {'user story', 'story', 'bug', 'task'};

  bool _isAllowedOnBacklogScreen(JiraIssue issue) {
    return _backlogAllowedIssueTypes.contains(issue.fields.issuetype.name.toLowerCase());
  }

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _assigneeDebounceTimer?.cancel();
    _boardSearchDebounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final storage = context.read<StorageService>();
    final api = context.read<JiraApiService>();
    try {
      final config = await storage.getConfig();
      if (config != null) {
        api.initialize(config);
        final defaultId = await storage.getDefaultBoardId();
        // Load boards and current user in parallel so sidebar shows user even if boards are slow
        final userFuture = api.getMyself();
        await _loadBoards(reset: true, defaultBoardId: defaultId);
        final user = await userFuture;
        final sentryToken = await storage.getSentryApiToken();
        if (mounted) {
          setState(() {
            _currentUser = user;
            _sentryTokenConfigured = sentryToken != null && sentryToken.trim().isNotEmpty;
          });
        }
      }
    } catch (e) {
      _showSnack(AppLocalizations.of(context).failedToInitialize, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshSentryConfig() async {
    final storage = context.read<StorageService>();
    final token = await storage.getSentryApiToken();
    if (mounted) {
      setState(() => _sentryTokenConfigured = token != null && token.trim().isNotEmpty);
    }
  }

  Future<void> _loadBoards({bool reset = true, int? defaultBoardId}) async {
    final api = context.read<JiraApiService>();
    setState(() {
      _error = null;
      _errorDismissed = false;
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
      _showSnack(AppLocalizations.of(context).failedToLoadBoards, isError: true);
    }
  }

  /// [targetTab] when set (e.g. when switching tabs) forces loading for that tab (0=Board, 1=Backlog, 2=Timeline).

  /// Retry helper for operations that might timeout
  Future<T> _retryOperation<T>(Future<T> Function() operation, {int maxRetries = 2}) async {
    int attempt = 0;
    while (attempt < maxRetries) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        if (attempt >= maxRetries || !e.toString().contains('Timeout')) {
          rethrow;
        }
        // Wait briefly before retrying (exponential backoff)
        await Future.delayed(Duration(milliseconds: 500 * attempt));
        debugPrint('Retrying operation (attempt $attempt/$maxRetries) after timeout');
      }
    }
    throw Exception('Max retries exceeded');
  }

  Future<void> _loadIssuesForBoard(int boardId, {int? targetTab}) async {
    final api = context.read<JiraApiService>();
    final tab = targetTab ?? _activeTab;
    setState(() {
      _loading = true;
      _error = null;
      _errorDismissed = false;
    });
    try {
      // Retry critical operations that might timeout
      final assigneesData = await _retryOperation(() => api.getBoardAssignees(boardId));
      final board = _boards.where((b) => b.id == boardId).firstOrNull ?? _selectedBoard;
      final isKanban = board?.type.toLowerCase() == 'kanban';

      if (!isKanban) {
        final sprintsData = await _retryOperation(() => api.getSprintsForBoard(boardId));
        setState(() {
          _sprints = sprintsData;
          _activeSprint = sprintsData.where((s) => s.state == 'active').firstOrNull;
        });
        if ((tab == 0 || tab == 2) && _activeSprint != null) {
          final issues = await api.getSprintIssues(
            boardId,
            _activeSprint!.id,
            assignee: _selectedAssignee == 'all' ? null : _selectedAssignee,
          );
          setState(() {
            _issues = issues;
            // Keep previous _backlogIssues so switching back to Backlog shows them until reload
            _assignees = assigneesData;
            _loading = false;
          });
          return;
        }
        if (tab == 1) {
          // Backlog tab: Load first page of backlog (with pagination; "Load more" fetches next pages)
          final assigneeParam = _selectedAssignee == 'all' ? null : _selectedAssignee;
          var backlog = <JiraIssue>[];
          var backlogHasMore = false;
          var backlogUseJql = false;
          String? backlogProjectKey = board?.location?.projectKey;
          if ((backlogProjectKey == null || backlogProjectKey.isEmpty) && boardId != 0) {
            final fullBoard = await api.getBoardById(boardId);
            backlogProjectKey = fullBoard?.location?.projectKey;
          }
          try {
            final page = await api.getBacklogIssuesPage(
              boardId,
              startAt: 0,
              maxResults: 50,
              assignee: assigneeParam,
            );
            backlog = page.issues;
            backlogHasMore = page.hasMore;
          } catch (e) {
            debugPrint('Backlog API failed (will try JQL fallback): $e');
          }
          if (backlog.isEmpty && backlogProjectKey != null && backlogProjectKey.isNotEmpty) {
            try {
              final page = await api.getBacklogIssuesByJqlPage(
                backlogProjectKey,
                startAt: 0,
                maxResults: 50,
                assignee: assigneeParam,
              );
              backlog = page.issues;
              backlogHasMore = page.hasMore;
              backlogUseJql = true;
            } catch (e) {
              debugPrint('Backlog JQL fallback failed: $e');
            }
          }
          if (backlog.isEmpty) {
            try {
              final allBoard = await api.getBoardIssuesAll(
                boardId,
                assignee: assigneeParam,
              );
              backlog = allBoard.where((i) => i.fields.sprint == null).toList();
              backlogHasMore = false;
            } catch (e) {
              debugPrint('Backlog board-issues fallback failed: $e');
            }
          }

          // OPTIMIZED: Load sprint issues in parallel instead of sequentially
          final allSprintIssues = <JiraIssue>[];
          final issueKeys = <String>{};
          
          // Load only active and future sprints (skip closed sprints for performance)
          final sprintsToLoad = _sprints.where((s) => s.state == 'active' || s.state == 'future').toList();
          
          // Parallel loading with Future.wait
          final sprintIssueFutures = <Future<List<JiraIssue>>>[];
          for (final sprint in sprintsToLoad) {
            sprintIssueFutures.add(
              api.getSprintIssues(
                boardId,
                sprint.id,
                assignee: assigneeParam,
              ).catchError((e) {
                debugPrint('Error loading sprint ${sprint.id}: $e');
                return <JiraIssue>[];
              })
            );
          }
          
          final sprintIssuesResults = await Future.wait(sprintIssueFutures);
          
          // Combine results
          for (final sprintIssues in sprintIssuesResults) {
            for (final issue in sprintIssues) {
              if (!issueKeys.contains(issue.key)) {
                issueKeys.add(issue.key);
                allSprintIssues.add(issue);
              }
            }
          }

          setState(() {
            _backlogIssues = backlog;
            _backlogHasMore = backlogHasMore;
            _backlogLoadingMore = false;
            _backlogUseJql = backlogUseJql;
            _backlogProjectKey = backlogProjectKey;
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
      final issues = await api.getBoardIssuesAll(boardId, assignee: assigneeParam);
      setState(() {
        _sprints = [];
        _activeSprint = null;
        _issues = issues;
        _backlogIssues = [];
        _backlogHasMore = false;
        _backlogLoadingMore = false;
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
      _showSnack(AppLocalizations.of(context).failedToLoadIssues, isError: true);
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

  static const int _backlogPageSize = 50;

  Future<void> _loadMoreBacklog() async {
    if (_backlogLoadingMore || !_backlogHasMore || _selectedBoard == null) return;
    final boardId = _selectedBoard!.id;
    final assigneeParam = _selectedAssignee == 'all' ? null : _selectedAssignee;
    setState(() => _backlogLoadingMore = true);
    try {
      if (_backlogUseJql && _backlogProjectKey != null && _backlogProjectKey!.isNotEmpty) {
        final page = await context.read<JiraApiService>().getBacklogIssuesByJqlPage(
          _backlogProjectKey!,
          startAt: _backlogIssues.length,
          maxResults: _backlogPageSize,
          assignee: assigneeParam,
        );
        if (mounted) {
          setState(() {
            _backlogIssues = [..._backlogIssues, ...page.issues];
            _backlogHasMore = page.hasMore;
            _backlogLoadingMore = false;
          });
        }
      } else {
        final page = await context.read<JiraApiService>().getBacklogIssuesPage(
          boardId,
          startAt: _backlogIssues.length,
          maxResults: _backlogPageSize,
          assignee: assigneeParam,
        );
        if (mounted) {
          setState(() {
            _backlogIssues = [..._backlogIssues, ...page.issues];
            _backlogHasMore = page.hasMore;
            _backlogLoadingMore = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Load more backlog failed: $e');
      if (mounted) setState(() => _backlogLoadingMore = false);
    }
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
    
    // Add active sprint at the top (always show, even if empty). Only User Story, Bug, Task.
    if (_activeSprint != null) {
      final activeSprintIssues = _issues.where((issue) {
        if (!_isAllowedOnBacklogScreen(issue)) return false;
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
        if (!_isAllowedOnBacklogScreen(issue)) return false;
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

    // Backlog section: only User Story, Bug, Task; exclude resolved/done; no sprint
    final filteredBacklog = _backlogIssues.where((issue) {
      if (!_isAllowedOnBacklogScreen(issue)) return false;
      if (issue.fields.status.statusCategory.key == 'done') return false; // resolved/done
      if (issue.fields.sprint != null) return false;
      if (_issueSearch.trim().isNotEmpty) {
        final q = _issueSearch.toLowerCase().trim();
        if (!(issue.key.toLowerCase().contains(q) ||
            issue.fields.summary.toLowerCase().contains(q))) return false;
      }
      return true;
    }).toList();

    // Add any issue from _issues that wasn't placed in active or future sprint (e.g. closed sprint)
    final backlogIssueKeys = filteredBacklog.map((i) => i.key).toSet();
    for (final issue in _issues) {
      if (addedIssueKeys.contains(issue.key) || backlogIssueKeys.contains(issue.key)) continue;
      if (!_isAllowedOnBacklogScreen(issue)) continue;
      if (issue.fields.status.statusCategory.key == 'done') continue;
      if (_issueSearch.trim().isNotEmpty) {
        final q = _issueSearch.toLowerCase().trim();
        if (!(issue.key.toLowerCase().contains(q) ||
            issue.fields.summary.toLowerCase().contains(q))) continue;
      }
      backlogIssueKeys.add(issue.key);
      filteredBacklog.add(issue);
    }

    // Always show Backlog section at bottom (even when empty)
    groups.add((
      sprint: 'Backlog',
      sprintId: null,
      issues: filteredBacklog,
    ));

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_loading && !_refreshing && _boards.isEmpty) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context).loadingJiraBoard,
                style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant) ?? TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: _buildDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_error != null && _error!.isNotEmpty && !_errorDismissed)
              _buildErrorBanner(),
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
        color: Theme.of(context).colorScheme.primary,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Center(child: Logo()),
          Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (ctx) => Semantics(
                label: AppLocalizations.of(context).openMenu,
                button: true,
                child: IconButton(
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                  icon: const Icon(Icons.menu, color: Colors.white, size: 26),
                  tooltip: AppLocalizations.of(context).menu,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCurrentUserIfNeeded() async {
    if (_currentUser != null) return;
    try {
      final user = await context.read<JiraApiService>().getMyself();
      if (mounted) setState(() => _currentUser = user);
    } catch (_) {}
  }

  Widget _buildDrawer() {
    final user = _currentUser;
    final displayName = (user?.displayName ?? '').trim();
    final email = (user?.emailAddress ?? '').trim();
    final showName = displayName.isNotEmpty ? displayName : AppLocalizations.of(context).user;
    final initial = showName.isNotEmpty ? showName[0].toUpperCase() : '?';
    final hasAvatar = user != null && (user.avatar48 ?? '').isNotEmpty;

    // If user not loaded yet, fetch when drawer is built (e.g. opened)
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadCurrentUserIfNeeded());
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: AppTheme.primary,
              ),
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    backgroundImage: hasAvatar ? NetworkImage(user.avatar48!) : null,
                    child: hasAvatar
                        ? null
                        : Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          showName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (email.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.dashboard, color: Theme.of(context).colorScheme.onSurface),
              title: Text(AppLocalizations.of(context).management, style: const TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.of(context).pop();
              },
            ),
            if (_sentryTokenConfigured)
              ListTile(
                leading: Icon(Icons.bug_report, color: Theme.of(context).colorScheme.onSurface),
                title: Text(AppLocalizations.of(context).sentry, style: const TextStyle(fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => SentryScreen(
                        onBack: () => Navigator.of(context).pop(),
                      ),
                    ),
                  );
                },
              ),
            ListTile(
              leading: Icon(Icons.language, color: Theme.of(context).colorScheme.onSurface),
              title: Text(AppLocalizations.of(context).language, style: const TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.of(context).pop();
                _showLanguagePicker();
              },
            ),
            ListTile(
              leading: Icon(Icons.settings, color: Theme.of(context).colorScheme.onSurface),
              title: Text(AppLocalizations.of(context).settings, style: const TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => SettingsScreen(
                      onBack: () => Navigator.of(context).pop(),
                      onLogout: widget.onLogout,
                    ),
                  ),
                ).then((_) => _refreshSentryConfig());
              },
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
              title: Text(AppLocalizations.of(context).logout, style: TextStyle(fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.of(context).pop();
                _showLogoutConfirm();
              },
            ),
          ],
        ),
      ),
    );
  }

  static const _languageFlags = {'en': '🇺🇸', 'vi': '🇻🇳'};

  Future<void> _showLanguagePicker() async {
    final l10n = AppLocalizations.of(context);
    final localeNotifier = context.read<LocaleNotifier>();
    final currentCode = localeNotifier.locale.languageCode;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.language),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Text(_languageFlags['en']!, style: const TextStyle(fontSize: 28)),
              title: Text(l10n.languageEnglish),
              selected: currentCode == 'en',
              onTap: () {
                localeNotifier.setLocale('en');
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: Text(_languageFlags['vi']!, style: const TextStyle(fontSize: 28)),
              title: Text(l10n.languageVietnamese),
              selected: currentCode == 'vi',
              onTap: () {
                localeNotifier.setLocale('vi');
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLogoutConfirm() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.logoutConfirmTitle),
        content: Text(l10n.logoutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) widget.onLogout();
  }

  Widget _buildErrorBanner() {
    final colorScheme = Theme.of(context).colorScheme;
    final errorColor = colorScheme.error;
    final errorBg = colorScheme.errorContainer;
    final onErrorBg = colorScheme.onErrorContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      color: errorBg,
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: onErrorBg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(color: onErrorBg, fontSize: 13),
            ),
          ),
          Semantics(
            label: AppLocalizations.of(context).retryLoading,
            button: true,
            child: TextButton(
              onPressed: () => _refresh(),
              child: Text(AppLocalizations.of(context).retry, style: TextStyle(fontWeight: FontWeight.w600, color: errorColor)),
            ),
          ),
          Semantics(
            label: AppLocalizations.of(context).dismissError,
            button: true,
            child: IconButton(
              icon: Icon(Icons.close, size: 20, color: onErrorBg),
              onPressed: () => setState(() => _errorDismissed = true),
              tooltip: AppLocalizations.of(context).dismiss,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardSelector() {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: InkWell(
        onTap: () => setState(() => _boardDropdownOpen = !_boardDropdownOpen),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Text(
                AppLocalizations.of(context).board + ':',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _selectedBoard != null
                      ? '${_selectedBoard!.name} (${_selectedBoard!.type})'
                      : AppLocalizations.of(context).selectBoard + '...',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: colorScheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(_boardDropdownOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    final isKanban = _selectedBoard!.type.toLowerCase() == 'kanban';
    if (isKanban) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surface,
      child: Row(
        children: [
          Expanded(child: _tab(0, AppLocalizations.of(context).board, Icons.dashboard)),
          Expanded(child: _tab(1, AppLocalizations.of(context).backlog, Icons.inventory_2)),
          Expanded(child: _tab(2, AppLocalizations.of(context).timeline, Icons.timeline)),
        ],
      ),
    );
  }

  Widget _buildAssigneeFilter() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: colorScheme.surface,
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context).assignee + ':',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _assigneeChip(AppLocalizations.of(context).all, 'all'),
                  _assigneeChip(AppLocalizations.of(context).unassigned, 'unassigned'),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
          ),
        ),
        selected: selected,
        onSelected: (sel) {
          if (!sel) return;
          setState(() => _selectedAssignee = value);
          
          // Debounce the API call to prevent rapid reloads
          _assigneeDebounceTimer?.cancel();
          _assigneeDebounceTimer = Timer(const Duration(milliseconds: 300), () {
            if (_selectedBoard != null && mounted) {
              _loadIssuesForBoard(_selectedBoard!.id);
            }
          });
        },
        selectedColor: colorScheme.primary,
        checkmarkColor: colorScheme.onPrimary,
      ),
    );
  }

  Widget _tab(int index, String label, IconData icon) {
    final active = _activeTab == index;
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final muted = colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () async {
        setState(() => _activeTab = index);
        if (_selectedBoard != null) await _loadIssuesForBoard(_selectedBoard!.id, targetTab: index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: active ? primary : muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? primary : muted,
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: colorScheme.primary, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '🏃 ${s.name}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colorScheme.onPrimaryContainer),
              ),
            ],
          ),
          if (s.startDate != null || s.endDate != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (s.startDate != null)
                  Text(
                    'Start: ${_formatDate(s.startDate!)}',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                if (s.startDate != null && s.endDate != null) const SizedBox(width: 16),
                if (s.endDate != null)
                  Text(
                    'End: ${_formatDate(s.endDate!)}',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _issueSearch = v),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).searchIssues,
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            label: AppLocalizations.of(context).createIssue,
            button: true,
            child: FilledButton.icon(
              onPressed: _openCreateIssue,
              icon: const Icon(Icons.add, size: 20),
              label: Text(AppLocalizations.of(context).create),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          if (_activeTab == 1 && _selectedBoard != null && _selectedBoard!.type.toLowerCase() != 'kanban') ...[
            const SizedBox(width: 8),
            Semantics(
              label: AppLocalizations.of(context).createSprint,
              button: true,
              child: OutlinedButton.icon(
                onPressed: _openCreateSprint,
                icon: const Icon(Icons.directions_run, size: 18),
                label: Text(AppLocalizations.of(context).sprint),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (_boardDropdownOpen) {
      return _buildBoardDropdown();
    }
    if (_selectedBoard == null) {
      return Center(
        child: Text(
          AppLocalizations.of(context).selectBoardToViewIssues,
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15),
        ),
      );
    }
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }
    // Backlog tab shows sprint groups + backlog; empty only when no groups at all
    final isEmptyForCurrentView = _activeTab == 1
        ? _groupedBySprint.isEmpty
        : _filteredIssues.isEmpty;
    if (isEmptyForCurrentView) {
      final isBacklog = _activeTab == 1;
      final isScrum = _selectedBoard != null && _selectedBoard!.type.toLowerCase() != 'kanban';
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox, size: 64, color: colorScheme.outline),
              const SizedBox(height: AppTheme.spaceLg),
              Text(
                AppLocalizations.of(context).noIssuesFound,
                style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spaceSm),
              Text(
                _selectedBoard != null ? AppLocalizations.of(context).thisBoardHasNoIssues : AppLocalizations.of(context).selectBoardToViewIssues + '.',
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              if (_selectedBoard != null) ...[
                const SizedBox(height: AppTheme.spaceXl),
                FilledButton.icon(
                  onPressed: _openCreateIssue,
                  icon: const Icon(Icons.add, size: 20),
                  label: Text(AppLocalizations.of(context).createIssue),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                ),
                if (isBacklog && isScrum) ...[
                  const SizedBox(height: AppTheme.spaceMd),
                  OutlinedButton.icon(
                    onPressed: _openCreateSprint,
                    icon: const Icon(Icons.directions_run, size: 18),
                    label: Text(AppLocalizations.of(context).createSprint),
                  ),
                ],
              ],
            ],
          ),
        ),
      );
    }

    if (_activeTab == 0 && _selectedBoard!.type.toLowerCase() != 'kanban' && _groupedByStatus.isNotEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        color: colorScheme.primary,
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
        'Overdue': colorScheme.error,
        'Today': AppTheme.success,
        'This week': colorScheme.primary,
        'Next week': AppTheme.statusTodo,
        'Later': colorScheme.onSurfaceVariant,
        'No due date': colorScheme.outline,
      };
      return RefreshIndicator(
        onRefresh: _refresh,
        color: colorScheme.primary,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          itemCount: _groupedByDueDate.entries.where((e) => e.value.isNotEmpty).length,
          itemBuilder: (context, idx) {
            final entry = _groupedByDueDate.entries.where((e) => e.value.isNotEmpty).elementAt(idx);
            final color = timelineColors[entry.key] ?? AppTheme.textSecondary;
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
                          '${AppLocalizations.of(context).timelineGroupLabel(entry.key)} (${entry.value.length})',
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
        color: colorScheme.primary,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          itemCount: _groupedBySprint.length,
          itemBuilder: (context, idx) {
            final group = _groupedBySprint[idx];
            final isBacklog = group.sprintId == null;
            final isActiveSprint = _activeSprint != null && group.sprintId == _activeSprint!.id;
            final isFirstUpcomingSprint = !isBacklog &&
                group.sprintId != null &&
                ((_activeSprint != null && idx == 1) || (_activeSprint == null && idx == 0));

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
                      color: isActiveSprint ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: isActiveSprint
                          ? Border.all(color: colorScheme.primary, width: 2)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          (isBacklog ? _backlogCollapsed : (group.sprintId != null && _collapsedSprints.contains(group.sprintId!)))
                              ? Icons.chevron_right
                              : Icons.expand_more,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
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
                                      isBacklog ? '📋 ${AppLocalizations.of(context).backlog}' : '🏃 ${group.sprint}',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  if (isActiveSprint)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        AppLocalizations.of(context).active,
                                        style: TextStyle(
                                          color: colorScheme.onPrimary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (!isBacklog && group.sprintId != null)
                                    PopupMenuButton<String>(
                                      padding: EdgeInsets.zero,
                                      icon: Icon(Icons.more_vert, size: 20, color: colorScheme.onSurfaceVariant),
                                      onSelected: (value) {
                                        if (value == 'complete') {
                                          _completeSprint(group.sprintId!, group.sprint);
                                        } else if (value == 'start') {
                                          _startSprint(group.sprintId!, group.sprint);
                                        } else if (value == 'update') {
                                          _openUpdateSprint(group.sprintId!, group.sprint);
                                        } else if (value == 'delete') {
                                          _confirmDeleteSprint(group.sprintId!, group.sprint);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        if (isActiveSprint)
                                          PopupMenuItem(
                                            value: 'complete',
                                            child: Row(
                                              children: [
                                                Icon(Icons.check_circle_outline, size: 20, color: colorScheme.primary),
                                                const SizedBox(width: 8),
                                                Text(AppLocalizations.of(context).completeSprint),
                                              ],
                                            ),
                                          ),
                                        if (isFirstUpcomingSprint)
                                          PopupMenuItem(
                                            value: 'start',
                                            child: Row(
                                              children: [
                                                Icon(Icons.play_arrow, size: 20, color: colorScheme.primary),
                                                const SizedBox(width: 8),
                                                Text(AppLocalizations.of(context).startSprint),
                                              ],
                                            ),
                                          ),
                                        PopupMenuItem(
                                          value: 'update',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit, size: 20, color: colorScheme.onSurfaceVariant),
                                              const SizedBox(width: 8),
                                              Text(AppLocalizations.of(context).updateSprint),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_outline, size: 20, color: colorScheme.error),
                                              const SizedBox(width: 8),
                                              Text(AppLocalizations.of(context).deleteSprint, style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.w600)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              if (group.issues.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${group.issues.length} issues  •  ✅ $doneCount  •  🔄 $inProgressCount  •  📝 $todoCount',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
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
                if (isBacklog && _backlogHasMore)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: _backlogLoadingMore
                          ? SizedBox(
                              height: 32,
                              width: 32,
                              child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                            )
                          : TextButton.icon(
                              onPressed: _loadMoreBacklog,
                              icon: Icon(Icons.add_circle_outline, size: 20, color: colorScheme.primary),
                              label: Text(
                                AppLocalizations.of(context).loadMore,
                                style: TextStyle(color: colorScheme.primary),
                              ),
                            ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: colorScheme.primary,
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

  Widget _buildBoardDropdown() {
    final colorScheme = Theme.of(context).colorScheme;
    // Do not wrap in Expanded: caller already uses Expanded(child: _buildContent())
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: TextField(
              onChanged: (v) {
                setState(() => _boardSearch = v);

                // Debounce the board search to prevent rapid reloads
                _boardSearchDebounceTimer?.cancel();
                _boardSearchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
                  if (mounted) {
                    _loadBoards(reset: true);
                  }
                });
              },
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).searchBoards,
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
                              child: Text(AppLocalizations.of(context).loadMore),
                            ),
                    ),
                  );
                }
                final b = _boards[i];
                final selected = _selectedBoard?.id == b.id;
                return ListTile(
                  leading: Icon(
                    b.type.toLowerCase() == 'kanban' ? Icons.view_kanban : Icons.directions_run,
                    color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    b.name,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? colorScheme.primary : colorScheme.onSurface,
                    ),
                  ),
                  subtitle: b.location?.projectName != null ? Text('📁 ${b.location!.projectName}') : null,
                  trailing: selected ? Icon(Icons.check, color: colorScheme.primary) : null,
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
      _showSnack(AppLocalizations.of(context).pleaseSelectBoardFirst, isError: true);
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
        _showSnack(AppLocalizations.of(context).failedToCreateSprint(error), isError: true);
      } else {
        _showSnack(AppLocalizations.of(context).sprintCreatedSuccess);
        await _refresh();
      }
    } catch (e) {
      _showSnack(AppLocalizations.of(context).errorCreatingSprint(e.toString()), isError: true);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _openUpdateSprint(int sprintId, String sprintName) {
    final sprint = _sprints.where((s) => s.id == sprintId).firstOrNull;
    if (sprint == null) return;

    DateTime? start;
    DateTime? end;
    if (sprint.startDate != null && sprint.startDate!.isNotEmpty) {
      start = DateTime.tryParse(sprint.startDate!);
    }
    if (sprint.endDate != null && sprint.endDate!.isNotEmpty) {
      end = DateTime.tryParse(sprint.endDate!);
    }

    showDialog<void>(
      context: context,
      builder: (context) => UpdateSprintDialog(
        sprintId: sprintId,
        initialName: sprint.name,
        initialGoal: sprint.goal ?? '',
        initialStartDate: start,
        initialEndDate: end,
        onUpdate: (id, name, goal, startDate, endDate) async {
          await _handleUpdateSprint(id, name, goal, startDate, endDate);
        },
      ),
    );
  }

  Future<void> _handleUpdateSprint(
    int sprintId,
    String name,
    String goal,
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    try {
      final api = context.read<JiraApiService>();
      final startStr = startDate != null ? DateFormat('yyyy-MM-dd').format(startDate) : null;
      final endStr = endDate != null ? DateFormat('yyyy-MM-dd').format(endDate) : null;
      final error = await api.updateSprint(
        sprintId: sprintId,
        name: name,
        goal: goal.isNotEmpty ? goal : null,
        startDate: startStr,
        endDate: endStr,
      );
      if (error != null) {
        _showSnack(AppLocalizations.of(context).failedToUpdateSprint(error), isError: true);
      } else {
        _showSnack(AppLocalizations.of(context).sprintUpdated);
        if (_selectedBoard != null) {
          await _loadIssuesForBoard(_selectedBoard!.id, targetTab: 1);
        }
      }
    } catch (e) {
      _showSnack(AppLocalizations.of(context).errorUpdatingSprint(e.toString()), isError: true);
    }
  }

  Future<void> _confirmDeleteSprint(int sprintId, String sprintName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).deleteSprint),
        content: Text(AppLocalizations.of(context).deleteSprintConfirm(sprintName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: Text(AppLocalizations.of(context).delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final api = context.read<JiraApiService>();
      final error = await api.deleteSprint(sprintId);
      if (error != null) {
        _showSnack(AppLocalizations.of(context).failedToDeleteSprint(error), isError: true);
      } else {
        _showSnack(AppLocalizations.of(context).sprintDeleted);
        if (_selectedBoard != null) {
          await _loadIssuesForBoard(_selectedBoard!.id, targetTab: 1);
        }
      }
    } catch (e) {
      _showSnack(AppLocalizations.of(context).errorDeletingSprint(e.toString()), isError: true);
    }
  }

  Future<void> _completeSprint(int sprintId, String sprintName) async {
    try {
      final api = context.read<JiraApiService>();
      await api.completeSprint(sprintId);
      if (mounted) {
        _showSnack(AppLocalizations.of(context).sprintCompleted);
        if (_selectedBoard != null) {
          await _loadIssuesForBoard(_selectedBoard!.id, targetTab: 1);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnack(AppLocalizations.of(context).errorCompletingSprint(e.toString()), isError: true);
      }
    }
  }

  Future<void> _startSprint(int sprintId, String sprintName) async {
    try {
      final api = context.read<JiraApiService>();
      await api.startSprint(sprintId);
      if (mounted) {
        _showSnack(AppLocalizations.of(context).sprintStarted);
        if (_selectedBoard != null) {
          await _loadIssuesForBoard(_selectedBoard!.id, targetTab: 1);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnack(AppLocalizations.of(context).errorStartingSprint(e.toString()), isError: true);
      }
    }
  }

  void _openCreateIssue() {
    if (_selectedBoard == null) {
      _showSnack(AppLocalizations.of(context).pleaseSelectBoardFirst, isError: true);
      return;
    }

    final projectKey = _selectedBoard!.location?.projectKey;
    if (projectKey == null || projectKey.isEmpty) {
      _showSnack(AppLocalizations.of(context).selectedBoardNoProjectKey, isError: true);
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
