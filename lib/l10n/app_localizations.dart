import 'package:flutter/material.dart';

/// App strings for English and Vietnamese.
class AppLocalizations {
  AppLocalizations(this.locale)
      : _strings = Map<String, String>.from(_localizedValues['en']!)
          ..addAll(_localizedValues[locale.languageCode] ?? const {});

  final Locale locale;
  final Map<String, String> _strings;

  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'menu': 'Menu',
      'settings': 'Settings',
      'logout': 'Logout',
      'language': 'Language',
      'logoutConfirmTitle': 'Logout',
      'logoutConfirmMessage': 'Are you sure you want to logout? This will clear your credentials.',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'languageEnglish': 'English',
      'languageVietnamese': 'Tiếng Việt',
      'back': 'Back',
      'save': 'Save',
      'retry': 'Retry',
      'dismiss': 'Dismiss',
      'create': 'Create',
      'none': 'None',
      'unassigned': 'Unassigned',
      'user': 'User',
      'loading': 'Loading...',
      'openMenu': 'Open menu',
      'open': 'Open',
      'openExternally': 'Open externally',
      'notSet': 'Not set',
      'selectABoard': 'Select a board',
      'selectBoard': 'Select a board',
      'searchBoards': 'Search boards...',
      'loadingJiraBoard': 'Loading Jira Board...',
      'board': 'Board',
      'backlog': 'Backlog',
      'timeline': 'Timeline',
      'assignee': 'Assignee',
      'all': 'All',
      'selectBoardToViewIssues': 'Select a board to view issues',
      'noIssuesFound': 'No issues found',
      'thisBoardHasNoIssues': 'This board has no issues yet.',
      'searchIssues': 'Search issues...',
      'createIssue': 'Create issue',
      'createSprint': 'Create sprint',
      'sprint': 'Sprint',
      'overdue': 'Overdue',
      'today': 'Today',
      'thisWeek': 'This week',
      'nextWeek': 'Next week',
      'later': 'Later',
      'noDueDate': 'No due date',
      'active': 'ACTIVE',
      'updateSprint': 'Update sprint',
      'deleteSprint': 'Delete sprint',
      'deleteSprintConfirm': 'Are you sure you want to delete "%s"? This action cannot be undone.',
      'completeSprint': 'Complete sprint',
      'startSprint': 'Start sprint',
      'start': 'Start',
      'end': 'End',
      'retryLoading': 'Retry loading',
      'dismissError': 'Dismiss error',
      'failedToInitialize': 'Failed to initialize. Check settings.',
      'failedToLoadBoards': 'Failed to load boards. Check credentials and connection.',
      'failedToLoadIssues': 'Failed to load issues.',
      'pleaseSelectBoardFirst': 'Please select a board first',
      'failedToCreateSprint': 'Failed to create sprint: %s',
      'sprintCreatedSuccess': 'Sprint created successfully',
      'errorCreatingSprint': 'Error creating sprint: %s',
      'failedToUpdateSprint': 'Failed to update sprint: %s',
      'sprintUpdated': 'Sprint updated',
      'errorUpdatingSprint': 'Error updating sprint: %s',
      'failedToDeleteSprint': 'Failed to delete sprint: %s',
      'sprintDeleted': 'Sprint deleted',
      'errorDeletingSprint': 'Error deleting sprint: %s',
      'sprintCompleted': 'Sprint completed',
      'sprintStarted': 'Sprint started',
      'errorCompletingSprint': 'Error completing sprint: %s',
      'errorStartingSprint': 'Error starting sprint: %s',
      'selectedBoardNoProjectKey': 'Selected board has no project key',
      'loadMore': 'Load more',
      'shareIssueLink': 'Share link',
      'copyIssueLink': 'Copy link',
      'openInBrowser': 'Open in browser',
      'linkCopiedToClipboard': 'Link copied to clipboard',
      'jiraConfiguration': 'Jira Configuration',
      'email': 'Email',
      'jiraUrl': 'Jira URL',
      'apiToken': 'API Token',
      'showToken': 'Show token',
      'hideToken': 'Hide token',
      'apiTokenHint': 'Generate a new API token at id.atlassian.com → Security → API tokens',
      'saveChanges': 'Save Changes',
      'defaultBoard': 'Default Board',
      'defaultBoardSubtitle': 'Select a default board to load on startup.',
      'saveDefaultBoard': 'Save Default Board',
      'selectDefaultBoard': 'Select Default Board',
      'settingsSavedSuccess': 'Settings saved successfully!',
      'failedToSaveSettings': 'Failed to save settings.',
      'defaultBoardSaved': 'Default board saved',
      'failedToSaveDefaultBoard': 'Failed to save default board',
      'pleaseEnterEmail': 'Please enter your email',
      'pleaseEnterJiraUrl': 'Please enter your Jira URL',
      'pleaseEnterValidUrl': 'Please enter a valid URL',
      'pleaseEnterApiToken': 'Please enter your API token',
      'step1Of2': 'Step 1 of 2',
      'step2Of2': 'Step 2 of 2',
      'enterApiToken': 'Enter your API Token',
      'pasteApiToken': 'Paste your API token',
      'getApiTokenFrom': 'Generate an API token at:\nid.atlassian.com/manage-profile/security/api-tokens',
      'next': 'Next →',
      'connectToJiraWorkspace': 'Connect to your Jira workspace',
      'yourEmail': 'your@email.com',
      'jiraUrlPlaceholder': 'https://your-domain.atlassian.net',
      'jiraCloudOnlyHint': 'Jira Cloud only. Open this URL in Safari/Chrome to confirm it loads.',
      'letsGo': "Let's Go!",
      'configurationSavedSuccess': 'Configuration saved successfully!',
      'failedToSave': 'Failed to save: %s',
      'pleaseEnterValidUrlExample': 'Please enter a valid URL (e.g. https://your-domain.atlassian.net)',
      'selectIssueType': 'Select Issue Type',
      'selectPriority': 'Select Priority',
      'selectSprint': 'Select Sprint',
      'selectAssignee': 'Select Assignee',
      'searchAssignee': 'Search assignee...',
      'noUsersFound': 'No users found',
      'searchParentIssue': 'Search parent issue...',
      'createNewSprint': 'Create New Sprint',
      'sprintNameRequired': 'Sprint name is required',
      'startDateRequired': 'Start date is required',
      'endDateRequired': 'End date is required',
      'endDateAfterStart': 'End date must be after start date',
      'sprintName': 'Sprint Name *',
      'enterSprintName': 'Enter sprint name',
      'goalOverview': 'Goal (Overview)',
      'enterSprintGoal': 'Enter sprint goal',
      'startDate': 'Start Date *',
      'endDate': 'End Date *',
      'selectStartDate': 'Select start date',
      'selectEndDate': 'Select end date',
      'createSprintButton': 'Create Sprint',
      'updateSprintButton': 'Update Sprint',
      'issueNotFound': 'Issue not found',
      'attachments': 'Attachments',
      'parent': 'Parent',
      'subtasks': 'Subtasks',
      'comments': 'Comments',
      'addCommentHint': 'Add a comment... (type @ to mention)',
      'postComment': 'Post comment',
      'noCommentsYet': 'No comments yet. Be the first to comment!',
      'failedToLoadImage': 'Failed to load image',
      'videoFailedToLoad': 'Video failed to load',
      'loadingVideo': 'Loading video...',
      'issueKey': 'ISSUE KEY',
      'summary': 'Summary',
      'edit': 'Edit',
      'details': 'Details',
      'reporter': 'Reporter',
      'priority': 'Priority',
      'type': 'Type',
      'storyPoints': 'Story Points',
      'dueDate': 'Due Date',
      'description': 'Description',
      'editSummary': 'Edit Summary',
      'summaryUpdated': 'Summary updated',
      'descriptionUpdated': 'Description updated',
      'assigneeCleared': 'Assignee cleared',
      'assigneeUpdated': 'Assignee updated',
      'sprintPickerComingSoon': 'Sprint picker coming soon',
      'taskManager': 'Task Manager',
      'basics': 'Basics',
      'planning': 'Planning',
      'issueType': 'Issue Type',
      'enterIssueSummary': 'Enter issue summary',
      'noProjectSelected': 'No project selected',
      'noParentIssuesFound': 'No parent issues found - Create Epic/Story first',
      'createEpicOrStoryFirst': 'Create an Epic or Story issue first to use as parent',
      'noSprintsAvailable': 'No sprints available',
      'movedToBacklog': 'Moved to backlog',
      'sprintPickerNoProject': 'Cannot determine project for this issue',
      'sprintPickerNoBoard': 'No board found for this project',
      'linkedWorkItems': 'Linked work items',
      'noLinkedWorkItems': 'No linked work items.',
      'issuesInThisEpic': 'Issues in this Epic',
      'noIssuesInThisEpic': 'No issues in this Epic.',
      'development': 'Development',
      'branches': 'Branches',
      'commits': 'Commits',
      'pullRequests': 'Pull Requests',
      'noPullRequestsLinked': 'No GitHub pull requests linked.',
      'builds': 'Builds',
      'deployments': 'Deployments',
      'author': 'Author',
      'id': 'ID',
      'status': 'Status',
      'updated': 'Updated',
      'confluence': 'Confluence',
      'linkConfluencePage': 'Link Confluence page',
      'noConfluencePagesLinked': 'No Confluence pages linked.',
      'confluencePageUrl': 'Page URL',
      'confluencePageUrlHint': 'e.g. https://your-domain.atlassian.net/wiki/spaces/SPACE/pages/12345/Page+title',
      'confluencePageTitleOptional': 'Page title (optional)',
      'confluenceLinkAdded': 'Confluence page linked',
      'confluenceLinkFailed': 'Failed to link: %s',
      'confluenceLinkRemoved': 'Link removed',
      'confluenceLinkRemoveFailed': 'Failed to remove link: %s',
      'removeConfluenceLink': 'Remove link',
      'removeConfluenceLinkConfirm': 'Remove this Confluence link from the issue?',
      // Issue linking
      'linkIssue': 'Link issue',
      'addIssueLink': 'Add issue link',
      'linkType': 'Link type',
      'issueKeyHint': 'e.g., PROJ-123',
      'issueKeyRequired': 'Please enter an issue key',
      'cannotLinkToSelf': 'Cannot link an issue to itself',
      'selectLinkType': 'Select link type',
      'thisIssue': 'This issue',
      'linkedIssue': 'Linked issue',
      'addComment': 'Add comment (optional)',
      'issueLinkAdded': 'Issue link created',
      'issueLinkFailed': 'Failed to link: %s',
      'removeIssueLink': 'Remove link',
      'removeIssueLinkConfirm': 'Remove link to %s?',
      'issueLinkRemoved': 'Link removed',
      'issueLinkRemoveFailed': 'Failed to remove link: %s',
      'noLinkTypesAvailable': 'No link types available',
      'management': 'Management',
      'sentry': 'Sentry',
      'sentryLinkHint': 'Paste Sentry issue link (e.g. https://...sentry.io/issues/...)',
      'viewSentryIssue': 'View issue',
      'viewInSentry': 'View in Sentry',
      'invalidSentryLink': 'Please enter a valid Sentry issue link (sentry.io)',
      'sentryApiToken': 'Sentry API token (optional)',
      'sentryApiTokenHint': 'Create at sentry.io/settings/account/api/auth-tokens/ with event:read scope',
      'showMoreFrames': 'Show %s more frames',
      'viewMoreBreadcrumbs': 'View %s more',
      'eventCount': 'Events: %s',
      'contexts': 'Contexts',
      'additionalData': 'Additional Data',
      'formatted': 'Formatted',
      'raw': 'Raw',
    },
    'vi': {
      'menu': 'Menu',
      'settings': 'Cài đặt',
      'logout': 'Đăng xuất',
      'language': 'Ngôn ngữ',
      'logoutConfirmTitle': 'Đăng xuất',
      'logoutConfirmMessage': 'Bạn có chắc muốn đăng xuất? Thao tác này sẽ xóa thông tin đăng nhập.',
      'cancel': 'Hủy',
      'delete': 'Xóa',
      'languageEnglish': 'English',
      'languageVietnamese': 'Tiếng Việt',
      'back': 'Quay lại',
      'save': 'Lưu',
      'retry': 'Thử lại',
      'dismiss': 'Đóng',
      'create': 'Tạo',
      'none': 'Không có',
      'unassigned': 'Chưa giao',
      'user': 'Người dùng',
      'loading': 'Đang tải...',
      'openMenu': 'Mở menu',
      'open': 'Mở',
      'openExternally': 'Mở bên ngoài',
      'notSet': 'Chưa đặt',
      'selectABoard': 'Chọn bảng',
      'selectBoard': 'Chọn bảng',
      'searchBoards': 'Tìm bảng...',
      'loadingJiraBoard': 'Đang tải bảng Jira...',
      'board': 'Bảng',
      'backlog': 'Tồn đọng',
      'timeline': 'Dòng thời gian',
      'assignee': 'Người thực hiện',
      'all': 'Tất cả',
      'selectBoardToViewIssues': 'Chọn bảng để xem công việc',
      'noIssuesFound': 'Không tìm thấy công việc',
      'thisBoardHasNoIssues': 'Bảng này chưa có công việc.',
      'searchIssues': 'Tìm công việc...',
      'createIssue': 'Tạo công việc',
      'createSprint': 'Tạo sprint',
      'sprint': 'Sprint',
      'overdue': 'Quá hạn',
      'today': 'Hôm nay',
      'thisWeek': 'Tuần này',
      'nextWeek': 'Tuần sau',
      'later': 'Sau',
      'noDueDate': 'Chưa có hạn',
      'active': 'ĐANG CHẠY',
      'updateSprint': 'Cập nhật sprint',
      'deleteSprint': 'Xóa sprint',
      'deleteSprintConfirm': 'Bạn có chắc muốn xóa "%s"? Hành động này không thể hoàn tác.',
      'completeSprint': 'Hoàn thành sprint',
      'startSprint': 'Bắt đầu sprint',
      'start': 'Bắt đầu',
      'end': 'Kết thúc',
      'retryLoading': 'Thử tải lại',
      'dismissError': 'Đóng lỗi',
      'failedToInitialize': 'Khởi tạo thất bại. Kiểm tra cài đặt.',
      'failedToLoadBoards': 'Tải bảng thất bại. Kiểm tra thông tin đăng nhập và kết nối.',
      'failedToLoadIssues': 'Tải công việc thất bại.',
      'pleaseSelectBoardFirst': 'Vui lòng chọn một bảng trước',
      'failedToCreateSprint': 'Tạo sprint thất bại: %s',
      'sprintCreatedSuccess': 'Tạo sprint thành công',
      'errorCreatingSprint': 'Lỗi khi tạo sprint: %s',
      'failedToUpdateSprint': 'Cập nhật sprint thất bại: %s',
      'sprintUpdated': 'Đã cập nhật sprint',
      'errorUpdatingSprint': 'Lỗi khi cập nhật sprint: %s',
      'failedToDeleteSprint': 'Xóa sprint thất bại: %s',
      'sprintDeleted': 'Đã xóa sprint',
      'errorDeletingSprint': 'Lỗi khi xóa sprint: %s',
      'sprintCompleted': 'Đã hoàn thành sprint',
      'sprintStarted': 'Đã bắt đầu sprint',
      'errorCompletingSprint': 'Lỗi khi hoàn thành sprint: %s',
      'errorStartingSprint': 'Lỗi khi bắt đầu sprint: %s',
      'selectedBoardNoProjectKey': 'Bảng đã chọn không có mã dự án',
      'loadMore': 'Tải thêm',
      'shareIssueLink': 'Chia sẻ liên kết',
      'copyIssueLink': 'Sao chép liên kết',
      'openInBrowser': 'Mở trong trình duyệt',
      'linkCopiedToClipboard': 'Đã sao chép liên kết',
      'jiraConfiguration': 'Cấu hình Jira',
      'email': 'Email',
      'jiraUrl': 'Jira URL',
      'apiToken': 'API Token',
      'showToken': 'Hiện token',
      'hideToken': 'Ẩn token',
      'apiTokenHint': 'Tạo API token tại id.atlassian.com → Bảo mật → API tokens',
      'saveChanges': 'Lưu thay đổi',
      'defaultBoard': 'Bảng mặc định',
      'defaultBoardSubtitle': 'Chọn bảng mặc định khi mở ứng dụng.',
      'saveDefaultBoard': 'Lưu bảng mặc định',
      'selectDefaultBoard': 'Chọn bảng mặc định',
      'settingsSavedSuccess': 'Đã lưu cài đặt!',
      'failedToSaveSettings': 'Lưu cài đặt thất bại.',
      'defaultBoardSaved': 'Đã lưu bảng mặc định',
      'failedToSaveDefaultBoard': 'Lưu bảng mặc định thất bại',
      'pleaseEnterEmail': 'Vui lòng nhập email',
      'pleaseEnterJiraUrl': 'Vui lòng nhập Jira URL',
      'pleaseEnterValidUrl': 'Vui lòng nhập URL hợp lệ',
      'pleaseEnterApiToken': 'Vui lòng nhập API token',
      'step1Of2': 'Bước 1/2',
      'step2Of2': 'Bước 2/2',
      'enterApiToken': 'Nhập API Token',
      'pasteApiToken': 'Dán API token',
      'getApiTokenFrom': 'Tạo API token tại:\nid.atlassian.com/manage-profile/security/api-tokens',
      'next': 'Tiếp →',
      'connectToJiraWorkspace': 'Kết nối workspace Jira',
      'yourEmail': 'email@example.com',
      'jiraUrlPlaceholder': 'https://ten-mien.atlassian.net',
      'jiraCloudOnlyHint': 'Chỉ Jira Cloud. Mở URL này trên Safari/Chrome để xác nhận.',
      'letsGo': 'Bắt đầu!',
      'configurationSavedSuccess': 'Đã lưu cấu hình!',
      'failedToSave': 'Lưu thất bại: %s',
      'pleaseEnterValidUrlExample': 'Vui lòng nhập URL hợp lệ (vd: https://ten-mien.atlassian.net)',
      'selectIssueType': 'Chọn loại công việc',
      'selectPriority': 'Chọn độ ưu tiên',
      'selectSprint': 'Chọn sprint',
      'selectAssignee': 'Chọn người thực hiện',
      'searchAssignee': 'Tìm người thực hiện...',
      'noUsersFound': 'Không tìm thấy người dùng',
      'searchParentIssue': 'Tìm công việc cha...',
      'createNewSprint': 'Tạo sprint mới',
      'sprintNameRequired': 'Cần nhập tên sprint',
      'startDateRequired': 'Cần chọn ngày bắt đầu',
      'endDateRequired': 'Cần chọn ngày kết thúc',
      'endDateAfterStart': 'Ngày kết thúc phải sau ngày bắt đầu',
      'sprintName': 'Tên sprint *',
      'enterSprintName': 'Nhập tên sprint',
      'goalOverview': 'Mục tiêu (Tổng quan)',
      'enterSprintGoal': 'Nhập mục tiêu sprint',
      'startDate': 'Ngày bắt đầu *',
      'endDate': 'Ngày kết thúc *',
      'selectStartDate': 'Chọn ngày bắt đầu',
      'selectEndDate': 'Chọn ngày kết thúc',
      'createSprintButton': 'Tạo Sprint',
      'updateSprintButton': 'Cập nhật Sprint',
      'issueNotFound': 'Không tìm thấy công việc',
      'attachments': 'Đính kèm',
      'parent': 'Công việc cha',
      'subtasks': 'Công việc con',
      'comments': 'Bình luận',
      'addCommentHint': 'Thêm bình luận... (gõ @ để nhắc)',
      'postComment': 'Đăng bình luận',
      'noCommentsYet': 'Chưa có bình luận. Hãy là người đầu tiên!',
      'failedToLoadImage': 'Tải ảnh thất bại',
      'videoFailedToLoad': 'Tải video thất bại',
      'loadingVideo': 'Đang tải video...',
      'issueKey': 'MÃ CÔNG VIỆC',
      'summary': 'Tóm tắt',
      'edit': 'Chỉnh sửa',
      'details': 'Chi tiết',
      'reporter': 'Người báo cáo',
      'priority': 'Độ ưu tiên',
      'type': 'Loại',
      'storyPoints': 'Story Points',
      'dueDate': 'Hạn chót',
      'description': 'Mô tả',
      'editSummary': 'Chỉnh sửa tóm tắt',
      'summaryUpdated': 'Đã cập nhật tóm tắt',
      'descriptionUpdated': 'Đã cập nhật mô tả',
      'assigneeCleared': 'Đã xóa người thực hiện',
      'assigneeUpdated': 'Đã cập nhật người thực hiện',
      'sprintPickerComingSoon': 'Chọn sprint sẽ có trong phiên bản sau',
      'taskManager': 'Quản lý công việc',
      'basics': 'Cơ bản',
      'planning': 'Kế hoạch',
      'issueType': 'Loại công việc',
      'enterIssueSummary': 'Nhập tóm tắt công việc',
      'noProjectSelected': 'Chưa chọn dự án',
      'noParentIssuesFound': 'Không có công việc cha - Tạo Epic/Story trước',
      'createEpicOrStoryFirst': 'Tạo công việc Epic hoặc Story trước để dùng làm cha',
      'noSprintsAvailable': 'Không có sprint',
      'movedToBacklog': 'Đã chuyển vào tồn đọng',
      'sprintPickerNoProject': 'Không xác định được dự án của công việc này',
      'sprintPickerNoBoard': 'Không tìm thấy bảng cho dự án này',
      'linkedWorkItems': 'Công việc liên kết',
      'noLinkedWorkItems': 'Chưa có công việc liên kết.',
      'issuesInThisEpic': 'Công việc trong Epic này',
      'noIssuesInThisEpic': 'Chưa có công việc nào trong Epic này.',
      'development': 'Development',
      'branches': 'Branches',
      'commits': 'Commits',
      'pullRequests': 'Pull Requests',
      'noPullRequestsLinked': 'Chưa có pull request GitHub nào được liên kết.',
      'builds': 'Builds',
      'deployments': 'Deployments',
      'author': 'Tác giả',
      'id': 'ID',
      'status': 'Trạng thái',
      'updated': 'Cập nhật',
      'confluence': 'Confluence',
      'linkConfluencePage': 'Liên kết trang Confluence',
      'noConfluencePagesLinked': 'Chưa có trang Confluence nào được liên kết.',
      'confluencePageUrl': 'URL trang',
      'confluencePageUrlHint': 'e.g. https://your-domain.atlassian.net/wiki/spaces/SPACE/pages/12345/Page+title',
      'confluencePageTitleOptional': 'Tiêu đề trang (tùy chọn)',
      'confluenceLinkAdded': 'Đã liên kết trang Confluence',
      'confluenceLinkFailed': 'Liên kết thất bại: %s',
      'confluenceLinkRemoved': 'Đã xóa liên kết',
      'confluenceLinkRemoveFailed': 'Xóa liên kết thất bại: %s',
      'removeConfluenceLink': 'Xóa liên kết',
      'removeConfluenceLinkConfirm': 'Xóa liên kết Confluence này khỏi công việc?',
      // Issue linking
      'linkIssue': 'Liên kết vấn đề',
      'addIssueLink': 'Thêm liên kết',
      'linkType': 'Loại liên kết',
      'issueKeyHint': 'vd: PROJ-123',
      'issueKeyRequired': 'Vui lòng nhập mã vấn đề',
      'cannotLinkToSelf': 'Không thể liên kết với chính nó',
      'selectLinkType': 'Chọn loại liên kết',
      'thisIssue': 'Vấn đề này',
      'linkedIssue': 'Vấn đề liên kết',
      'addComment': 'Thêm bình luận (tùy chọn)',
      'issueLinkAdded': 'Đã tạo liên kết',
      'issueLinkFailed': 'Tạo liên kết thất bại: %s',
      'removeIssueLink': 'Xóa liên kết',
      'removeIssueLinkConfirm': 'Xóa liên kết đến %s?',
      'issueLinkRemoved': 'Đã xóa liên kết',
      'issueLinkRemoveFailed': 'Xóa liên kết thất bại: %s',
      'noLinkTypesAvailable': 'Không có loại liên kết',
      'management': 'Quản lý',
      'sentry': 'Sentry',
      'sentryLinkHint': 'Dán link Sentry (vd: https://...sentry.io/issues/...)',
      'viewSentryIssue': 'Xem lỗi',
      'viewInSentry': 'Xem trong Sentry',
      'invalidSentryLink': 'Vui lòng nhập link Sentry hợp lệ (sentry.io)',
      'sentryApiToken': 'Sentry API token (tùy chọn)',
      'sentryApiTokenHint': 'Tạo tại sentry.io/settings/account/api/auth-tokens/ với quyền event:read',
      'showMoreFrames': 'Hiện thêm %s frame',
      'viewMoreBreadcrumbs': 'Xem thêm %s',
      'eventCount': 'Sự kiện: %s',
      'contexts': 'Ngữ cảnh',
      'additionalData': 'Dữ liệu bổ sung',
      'formatted': 'Định dạng',
      'raw': 'Thô',
    },
  };

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  /// Safe lookup: use current locale, fallback to English so cached/incomplete maps never throw.
  String _s(String key) => _strings[key] ?? _localizedValues['en']![key]!;

  // Getters for all keys
  String get menu => _s('menu');
  String get settings => _s('settings');
  String get logout => _s('logout');
  String get language => _s('language');
  String get logoutConfirmTitle => _s('logoutConfirmTitle');
  String get logoutConfirmMessage => _s('logoutConfirmMessage');
  String get cancel => _s('cancel');
  String get delete => _s('delete');
  String get languageEnglish => _s('languageEnglish');
  String get languageVietnamese => _s('languageVietnamese');
  String get back => _s('back');
  String get save => _s('save');
  String get retry => _s('retry');
  String get dismiss => _s('dismiss');
  String get create => _s('create');
  String get none => _s('none');
  String get unassigned => _s('unassigned');
  String get user => _s('user');
  String get loading => _s('loading');
  String get openMenu => _s('openMenu');
  String get open => _s('open');
  String get openExternally => _s('openExternally');
  String get notSet => _s('notSet');
  String get selectABoard => _s('selectABoard');
  String get selectBoard => _s('selectBoard');
  String get searchBoards => _s('searchBoards');
  String get loadingJiraBoard => _s('loadingJiraBoard');
  String get board => _s('board');
  String get backlog => _s('backlog');
  String get timeline => _s('timeline');
  String get assignee => _s('assignee');
  String get all => _s('all');
  String get selectBoardToViewIssues => _s('selectBoardToViewIssues');
  String get noIssuesFound => _s('noIssuesFound');
  String get thisBoardHasNoIssues => _s('thisBoardHasNoIssues');
  String get searchIssues => _s('searchIssues');
  String get createIssue => _s('createIssue');
  String get createSprint => _s('createSprint');
  String get sprint => _s('sprint');
  String get overdue => _s('overdue');
  String get today => _s('today');
  String get thisWeek => _s('thisWeek');
  String get nextWeek => _s('nextWeek');
  String get later => _s('later');
  String get noDueDate => _s('noDueDate');
  String get active => _s('active');
  String get updateSprint => _s('updateSprint');
  String get deleteSprint => _s('deleteSprint');
  String get completeSprint => _s('completeSprint');
  String get startSprint => _s('startSprint');
  String get start => _s('start');
  String get end => _s('end');
  String get retryLoading => _s('retryLoading');
  String get dismissError => _s('dismissError');
  String get failedToInitialize => _s('failedToInitialize');
  String get failedToLoadBoards => _s('failedToLoadBoards');
  String get failedToLoadIssues => _s('failedToLoadIssues');
  String get pleaseSelectBoardFirst => _s('pleaseSelectBoardFirst');
  String get sprintCreatedSuccess => _s('sprintCreatedSuccess');
  String get sprintUpdated => _s('sprintUpdated');
  String get sprintDeleted => _s('sprintDeleted');
  String get sprintCompleted => _s('sprintCompleted');
  String get sprintStarted => _s('sprintStarted');
  String get selectedBoardNoProjectKey => _s('selectedBoardNoProjectKey');
  String get loadMore => _s('loadMore');
  String get shareIssueLink => _s('shareIssueLink');
  String get copyIssueLink => _s('copyIssueLink');
  String get openInBrowser => _s('openInBrowser');
  String get linkCopiedToClipboard => _s('linkCopiedToClipboard');
  String get jiraConfiguration => _s('jiraConfiguration');
  String get email => _s('email');
  String get jiraUrl => _s('jiraUrl');
  String get apiToken => _s('apiToken');
  String get showToken => _s('showToken');
  String get hideToken => _s('hideToken');
  String get apiTokenHint => _s('apiTokenHint');
  String get saveChanges => _s('saveChanges');
  String get defaultBoard => _s('defaultBoard');
  String get defaultBoardSubtitle => _s('defaultBoardSubtitle');
  String get saveDefaultBoard => _s('saveDefaultBoard');
  String get selectDefaultBoard => _s('selectDefaultBoard');
  String get settingsSavedSuccess => _s('settingsSavedSuccess');
  String get failedToSaveSettings => _s('failedToSaveSettings');
  String get defaultBoardSaved => _s('defaultBoardSaved');
  String get failedToSaveDefaultBoard => _s('failedToSaveDefaultBoard');
  String get pleaseEnterEmail => _s('pleaseEnterEmail');
  String get pleaseEnterJiraUrl => _s('pleaseEnterJiraUrl');
  String get pleaseEnterValidUrl => _s('pleaseEnterValidUrl');
  String get pleaseEnterApiToken => _s('pleaseEnterApiToken');
  String get step1Of2 => _s('step1Of2');
  String get step2Of2 => _s('step2Of2');
  String get enterApiToken => _s('enterApiToken');
  String get pasteApiToken => _s('pasteApiToken');
  String get getApiTokenFrom => _s('getApiTokenFrom');
  String get next => _s('next');
  String get connectToJiraWorkspace => _s('connectToJiraWorkspace');
  String get yourEmail => _s('yourEmail');
  String get jiraUrlPlaceholder => _s('jiraUrlPlaceholder');
  String get jiraCloudOnlyHint => _s('jiraCloudOnlyHint');
  String get letsGo => _s('letsGo');
  String get configurationSavedSuccess => _s('configurationSavedSuccess');
  String get pleaseEnterValidUrlExample => _s('pleaseEnterValidUrlExample');
  String get selectIssueType => _s('selectIssueType');
  String get selectPriority => _s('selectPriority');
  String get selectSprint => _s('selectSprint');
  String get selectAssignee => _s('selectAssignee');
  String get searchAssignee => _s('searchAssignee');
  String get noUsersFound => _s('noUsersFound');
  String get searchParentIssue => _s('searchParentIssue');
  String get createNewSprint => _s('createNewSprint');
  String get sprintNameRequired => _s('sprintNameRequired');
  String get startDateRequired => _s('startDateRequired');
  String get endDateRequired => _s('endDateRequired');
  String get endDateAfterStart => _s('endDateAfterStart');
  String get sprintName => _s('sprintName');
  String get enterSprintName => _s('enterSprintName');
  String get goalOverview => _s('goalOverview');
  String get enterSprintGoal => _s('enterSprintGoal');
  String get startDate => _s('startDate');
  String get endDate => _s('endDate');
  String get selectStartDate => _s('selectStartDate');
  String get selectEndDate => _s('selectEndDate');
  String get createSprintButton => _s('createSprintButton');
  String get updateSprintButton => _s('updateSprintButton');
  String get issueNotFound => _s('issueNotFound');
  String get attachments => _s('attachments');
  String get parent => _s('parent');
  String get subtasks => _s('subtasks');
  String get comments => _s('comments');
  String get addCommentHint => _s('addCommentHint');
  String get postComment => _s('postComment');
  String get noCommentsYet => _s('noCommentsYet');
  String get failedToLoadImage => _s('failedToLoadImage');
  String get videoFailedToLoad => _s('videoFailedToLoad');
  String get loadingVideo => _s('loadingVideo');
  String get issueKey => _s('issueKey');
  String get summary => _s('summary');
  String get edit => _s('edit');
  String get details => _s('details');
  String get reporter => _s('reporter');
  String get priority => _s('priority');
  String get type => _s('type');
  String get storyPoints => _s('storyPoints');
  String get dueDate => _s('dueDate');
  String get description => _s('description');
  String get editSummary => _s('editSummary');
  String get summaryUpdated => _s('summaryUpdated');
  String get descriptionUpdated => _s('descriptionUpdated');
  String get assigneeCleared => _s('assigneeCleared');
  String get assigneeUpdated => _s('assigneeUpdated');
  String get sprintPickerComingSoon => _s('sprintPickerComingSoon');
  String get taskManager => _s('taskManager');
  String get basics => _s('basics');
  String get planning => _s('planning');
  String get issueType => _s('issueType');
  String get enterIssueSummary => _s('enterIssueSummary');
  String get noProjectSelected => _s('noProjectSelected');
  String get noParentIssuesFound => _s('noParentIssuesFound');
  String get createEpicOrStoryFirst => _s('createEpicOrStoryFirst');
  String get noSprintsAvailable => _s('noSprintsAvailable');
  String get movedToBacklog => _s('movedToBacklog');
  String get sprintPickerNoProject => _s('sprintPickerNoProject');
  String get sprintPickerNoBoard => _s('sprintPickerNoBoard');
  String get linkedWorkItems => _s('linkedWorkItems');
  String get noLinkedWorkItems => _s('noLinkedWorkItems');
  String get issuesInThisEpic => _s('issuesInThisEpic');
  String get noIssuesInThisEpic => _s('noIssuesInThisEpic');
  String get development => _s('development');
  String get branches => _s('branches');
  String get commits => _s('commits');
  String get pullRequests => _s('pullRequests');
  String get noPullRequestsLinked => _s('noPullRequestsLinked');
  String get builds => _s('builds');
  String get deployments => _s('deployments');
  String get author => _s('author');
  String get id => _s('id');
  String get status => _s('status');
  String get updated => _s('updated');
  String get confluence => _s('confluence');
  String get linkConfluencePage => _s('linkConfluencePage');
  String get noConfluencePagesLinked => _s('noConfluencePagesLinked');
  String get confluencePageUrl => _s('confluencePageUrl');
  String get confluencePageUrlHint => _s('confluencePageUrlHint');
  String get confluencePageTitleOptional => _s('confluencePageTitleOptional');
  String get confluenceLinkAdded => _s('confluenceLinkAdded');
  String get confluenceLinkRemoved => _s('confluenceLinkRemoved');

  String confluenceLinkFailed(String msg) =>
      (_strings['confluenceLinkFailed'] ?? _localizedValues['en']!['confluenceLinkFailed']!).replaceAll('%s', msg);
  String confluenceLinkRemoveFailed(String msg) =>
      (_strings['confluenceLinkRemoveFailed'] ?? _localizedValues['en']!['confluenceLinkRemoveFailed']!).replaceAll('%s', msg);
  String get removeConfluenceLink => _s('removeConfluenceLink');
  String get removeConfluenceLinkConfirm => _s('removeConfluenceLinkConfirm');

  // Issue linking
  String get linkIssue => _s('linkIssue');
  String get addIssueLink => _s('addIssueLink');
  String get linkType => _s('linkType');
  String get issueKeyHint => _s('issueKeyHint');
  String get issueKeyRequired => _s('issueKeyRequired');
  String get cannotLinkToSelf => _s('cannotLinkToSelf');
  String get selectLinkType => _s('selectLinkType');
  String get thisIssue => _s('thisIssue');
  String get linkedIssue => _s('linkedIssue');
  String get addComment => _s('addComment');
  String get issueLinkAdded => _s('issueLinkAdded');
  String issueLinkFailed(String error) =>
      (_strings['issueLinkFailed'] ?? _localizedValues['en']!['issueLinkFailed']!).replaceAll('%s', error);
  String get removeIssueLink => _s('removeIssueLink');
  String removeIssueLinkConfirm(String issueKey) =>
      (_strings['removeIssueLinkConfirm'] ?? _localizedValues['en']!['removeIssueLinkConfirm']!).replaceAll('%s', issueKey);
  String get issueLinkRemoved => _s('issueLinkRemoved');
  String issueLinkRemoveFailed(String error) =>
      (_strings['issueLinkRemoveFailed'] ?? _localizedValues['en']!['issueLinkRemoveFailed']!).replaceAll('%s', error);
  String get noLinkTypesAvailable => _s('noLinkTypesAvailable');

  String get management => _s('management');
  String get sentry => _s('sentry');
  String get sentryLinkHint => _s('sentryLinkHint');
  String get viewSentryIssue => _s('viewSentryIssue');
  String get viewInSentry => _s('viewInSentry');
  String get invalidSentryLink => _s('invalidSentryLink');
  String get sentryApiToken => _s('sentryApiToken');
  String get sentryApiTokenHint => _s('sentryApiTokenHint');

  String showMoreFrames(int count) =>
      (_strings['showMoreFrames'] ?? _localizedValues['en']!['showMoreFrames']!).replaceAll('%s', count.toString());

  String viewMoreBreadcrumbs(int count) =>
      (_strings['viewMoreBreadcrumbs'] ?? _localizedValues['en']!['viewMoreBreadcrumbs']!).replaceAll('%s', count.toString());

  String eventCount(String count) =>
      (_strings['eventCount'] ?? _localizedValues['en']!['eventCount']!).replaceAll('%s', count);

  String get contexts => _s('contexts');
  String get additionalData => _s('additionalData');
  String get formatted => _s('formatted');
  String get raw => _s('raw');

  String deleteSprintConfirm(String sprintName) =>
      (_strings['deleteSprintConfirm'] ?? _localizedValues['en']!['deleteSprintConfirm']!).replaceAll('%s', sprintName);
  String failedToCreateSprint(String msg) =>
      (_strings['failedToCreateSprint'] ?? _localizedValues['en']!['failedToCreateSprint']!).replaceAll('%s', msg);
  String errorCreatingSprint(String msg) =>
      (_strings['errorCreatingSprint'] ?? _localizedValues['en']!['errorCreatingSprint']!).replaceAll('%s', msg);
  String failedToUpdateSprint(String msg) =>
      (_strings['failedToUpdateSprint'] ?? _localizedValues['en']!['failedToUpdateSprint']!).replaceAll('%s', msg);
  String errorUpdatingSprint(String msg) =>
      (_strings['errorUpdatingSprint'] ?? _localizedValues['en']!['errorUpdatingSprint']!).replaceAll('%s', msg);
  String failedToDeleteSprint(String msg) =>
      (_strings['failedToDeleteSprint'] ?? _localizedValues['en']!['failedToDeleteSprint']!).replaceAll('%s', msg);
  String errorDeletingSprint(String msg) =>
      (_strings['errorDeletingSprint'] ?? _localizedValues['en']!['errorDeletingSprint']!).replaceAll('%s', msg);
  String errorCompletingSprint(String msg) =>
      (_strings['errorCompletingSprint'] ?? _localizedValues['en']!['errorCompletingSprint']!).replaceAll('%s', msg);
  String errorStartingSprint(String msg) =>
      (_strings['errorStartingSprint'] ?? _localizedValues['en']!['errorStartingSprint']!).replaceAll('%s', msg);
  String failedToSave(String msg) =>
      (_strings['failedToSave'] ?? _localizedValues['en']!['failedToSave']!).replaceAll('%s', msg);

  /// Translates timeline group key (e.g. 'Overdue', 'Today') to current locale.
  String timelineGroupLabel(String key) {
    switch (key) {
      case 'Overdue': return overdue;
      case 'Today': return today;
      case 'This week': return thisWeek;
      case 'Next week': return nextWeek;
      case 'Later': return later;
      case 'No due date': return noDueDate;
      default: return key;
    }
  }
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'vi';

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
