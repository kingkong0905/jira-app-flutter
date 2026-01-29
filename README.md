# Jira Management – Flutter App

A Flutter app for managing Jira boards and viewing tickets, with **the same business logic** as the [React Native Jira app](https://github.com/kingkong0905/jira-app).

## Features

- **Secure setup**: Email, Jira URL, and API token with validation and connection test
- **Board management**: List boards, search, select default board, load board issues
- **Board / Backlog tabs**: For Scrum boards – active sprint (Board) and backlog; Kanban shows all issues
- **Issue cards**: Key, status, summary, type, assignee (status colors and priority)
- **Issue detail**: Summary, status, assignee, description, comments
- **Settings**: Update credentials, set default board, logout
- **Storage**: Secure storage for config (same keys as reference app)

## Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (stable, 3.0+)
- iOS Simulator / Xcode (Mac) or Android Emulator / Android Studio

## Configuration

On first launch you need:

- **Email**: Your Jira account email
- **Jira URL**: e.g. `https://your-domain.atlassian.net`
- **API Token**: From [Atlassian API tokens](https://id.atlassian.com/manage-profile/security/api-tokens)

## Getting started

### Option 1: Scripts (recommended)

```bash
# Setup: install Flutter (if missing), deps, and platform folders
# On macOS: uses Homebrew (brew install --cask flutter) or git clone to ~/flutter
# On Linux: git clone to ~/flutter. Set FLUTTER_INSTALL_DIR to use another path.
./scripts/setup.sh

# Install and run on a connected device (phone/emulator)
./scripts/install_device.sh

# Or target a specific device (e.g. first iOS or Android)
./scripts/install_device.sh ios
./scripts/install_device.sh android
```

### Option 2: Manual

```bash
# Install dependencies
flutter pub get

# If platform folders (android/, ios/) are missing, generate them:
flutter create .

# Run on iOS
flutter run -d ios

# Run on Android
flutter run -d android
```

## Project structure

```
lib/
├── main.dart                 # App entry, providers
├── models/
│   └── jira_models.dart      # JiraConfig, JiraBoard, JiraIssue, JiraSprint, etc.
├── services/
│   ├── storage_service.dart  # Secure config storage (same keys as reference app)
│   └── jira_api_service.dart  # Jira REST client (same endpoints & auth)
├── screens/
│   ├── app_shell.dart        # Config check, Setup vs Home
│   ├── setup_screen.dart     # Step 1: API token, Step 2: Email + URL
│   ├── home_screen.dart      # Boards, Board/Backlog, issues list
│   ├── settings_screen.dart  # Credentials, default board, logout
│   └── issue_detail_screen.dart
└── widgets/
    ├── logo.dart
    └── issue_card.dart
```

## API alignment with reference app

- **Auth**: Basic auth `email:apiToken` (base64)
- **Endpoints**: `/rest/api/3/myself`, `/rest/agile/1.0/board`, `/rest/agile/1.0/board/{id}/issue`, `/rest/agile/1.0/board/{id}/sprint`, `/rest/agile/1.0/board/{id}/backlog`, `/rest/api/3/issue/{key}`, `/rest/api/3/issue/{key}/comment`, etc.
- **Caching**: Boards 5 min, board issues 1 min, issue details 2 min
- **Storage keys**: `jira_email`, `jira_url`, `jira_api_token`, `jira_is_configured`, `jira_default_board_id`

## License

See [LICENSE](LICENSE).
