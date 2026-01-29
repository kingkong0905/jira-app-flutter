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

- **Email**: Your Jira account email (the one you use to log in to Jira)
- **Jira URL**: e.g. `https://your-domain.atlassian.net` (no trailing slash; Jira Cloud only)
- **API Token**: From [Atlassian API tokens](https://id.atlassian.com/manage-profile/security/api-tokens)

### If you see "Unable to connect" or "Cannot reach Jira"

The app shows a specific error when connection fails. For **"Cannot reach Jira"** (network-level failure):

1. **Open the Jira URL in the device browser** (Safari or Chrome). If it doesn’t load there, the app can’t reach it either. Fix network or URL first.
2. **Use the exact Jira Cloud URL**: `https://your-site.atlassian.net` (replace `your-site` with your instance name). No trailing slash, no path (e.g. no `/jira`).
3. **Wi‑Fi vs mobile data** – Try the other if one fails (e.g. corporate Wi‑Fi may block external APIs).
4. **VPN** – If you’re on a VPN, try disconnecting or using another network; some VPNs block or alter HTTPS to Jira.
5. **Jira Server/Data Center** – The app is aimed at **Jira Cloud** (`*.atlassian.net`). For Server/DC, the instance must be reachable from the internet over HTTPS; the app tries both `/rest/api/3` and `/rest/api/2`.

Other errors:

- **Invalid email or API token** – Same email as Jira login; create a token at [id.atlassian.com/manage-profile/security/api-tokens](https://id.atlassian.com/manage-profile/security/api-tokens).
- **403 / timeout** – Check permissions and that the site opens in a browser.

### "Operation not permitted" (errno = 1) when connecting

If you see `SocketException: Connection failed (OS Error: Operation not permitted, errno = 1)` when running on **macOS** (desktop), the app sandbox was blocking outgoing network. The project includes the **Outgoing Connections (Client)** entitlement (`com.apple.security.network.client`) in `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`.

**You must do a full clean rebuild** — hot reload does **not** apply entitlement changes:

1. **Stop the app** (quit completely; do not use hot reload).
2. Run:
   ```bash
   ./scripts/run_macos.sh
   ```
   Or manually:
   ```bash
   flutter clean
   flutter pub get
   flutter run -d macos
   ```
3. Try connecting to Jira again.

If you run on **iOS Simulator** and see the same error, the simulator can exhibit similar restrictions. Use **macOS** (`flutter run -d macos`) or a **physical iOS device** (`flutter run -d <device-id>`) instead.

### Storage

Configuration (email, Jira URL, API token, default board) is stored in a **local SQLite database** in the app's application support directory. No keychain or secure storage is used, so the app builds and runs on macOS without provisioning profiles or keychain entitlements.

**Build fails with "requires a provisioning profile"**: The macOS project uses **Manual signing** with **Sign to Run Locally**. Run `./scripts/run_macos.sh` again after pulling the latest changes.

**Run Script warning**: The "Run script build phase will be run during every build..." warning comes from the Flutter Assemble script and is harmless; you can ignore it.

### Debug logs when connection fails

When you try to connect, the app prints detailed logs to the **run console** (where you ran `flutter run` or the Xcode/Android Studio debug console). Look for lines starting with `[JiraAPI]`:

- **baseUrl** – The exact URL used (after normalization).
- **GET** – Each URL tried (`/rest/api/3/myself` and `/rest/api/2/myself`).
- **response** – HTTP status code and URL.
- **response body** – First 300 chars of the response (on non-200).
- **exception** / **stack** – Full exception and stack trace if the request throws.

To turn off these logs, set `JiraApiService.debugLog = false` in your code (e.g. in `main.dart`).

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

# macOS: if you see "Operation not permitted" when connecting to Jira, do a clean rebuild (entitlements)
./scripts/run_macos.sh
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
