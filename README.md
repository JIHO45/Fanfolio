# Fanfolio

An iOS app for keeping sports tickets, cultural event tickets, and attendance records in one place.
Organize your memories into folders, explore fan stats such as your in-person win rate and visited stadiums, and follow live scores.

## Features

- **Sports attendance records**: Save games, ticket photos, and QR codes; organize them into folders and track fan stats, including your in-person win rate.
- **Live scores**: Follow KBO and ESPN league scoreboards with Live Activity and widget support.
- **Standings and players**: Browse league standings and team rosters, and save favorite players.
- **Stadium map**: Explore visited stadiums on a Mapbox-powered map and revisit away-game highlights.
- **Cultural event records**: Keep tickets and attendance stats for performances and exhibitions.
- **Ticket gallery and sharing**: Generate and share ticket card images.
- **Sync**: Automatically sync across devices with SwiftData and CloudKit, with local storage when iCloud is unavailable.
- **Sign-in and subscriptions**: Sign in with Apple or use guest mode, with a StoreKit-based Pro subscription.

## Tech Stack

| Category | Technologies |
| --- | --- |
| App | Swift, SwiftUI, SwiftData, CloudKit, ActivityKit, WidgetKit, StoreKit |
| Packages (SPM) | Firebase iOS SDK, Mapbox Maps iOS, Kingfisher |
| Data sources | API-Sports (KBO), ESPN API |
| Backend | Firebase Cloud Functions, Firestore |

## Project Structure

```
Fanfolio/                  # Main app
├── Data/                  # Static data (ESPN team information)
├── DesignSystem/          # Shared themes and components
├── LiveActivity/          # Live Activity management
├── Model/                 # Domain models
├── Service/               # APIs, authentication, subscriptions, and storage
├── View/                  # Screens (Sports, Culture, TicketGallery, Settings, etc.)
└── Localizable.xcstrings  # Localized strings
FanfolioLiveScoreWidget/   # Live score widget and Live Activity target
FanfolioTests/             # Unit tests
FanfolioUITests/           # UI tests
functions/                 # Firebase Cloud Functions (sync KBO data to Firestore)
scripts/localization/      # String Catalog translation helpers
docs/                      # Development documentation
```

## Getting Started

### Requirements

- Xcode 26 or later
- iOS 26.1 or later

### Setup

1. Clone the repository.

   ```bash
   git clone https://github.com/JIHO45/Fanfolio.git
   cd Fanfolio
   ```

2. Create the API key configuration file and fill in your values.

   ```bash
   cp APIKeys.xcconfig.example APIKeys.xcconfig
   ```

   | Key | Description |
   | --- | --- |
   | `API_SPORTS_KEY` | API-Sports API key |
   | `MAPBOX_ACCESS_TOKEN` | Mapbox public token (starts with `pk.`) |
   | `FIREBASE_PROJECT_ID` | Firebase project ID |
   | `FIREBASE_WEB_API_KEY` | Firebase web API key |
   | `PRIVACY_POLICY_URL` | Optional privacy policy URL |

   > `APIKeys.xcconfig` and `DeveloperSettings.xcconfig` are listed in `.gitignore` and should not be committed.

3. Open `Fanfolio.xcodeproj`, select the `Fanfolio` scheme, and build and run the app.

### Cloud Functions

`functions/index.js` periodically fetches KBO game and standings data from API-Sports and syncs it to Firestore. The API key is stored as a Firebase secret (`API_SPORTS_KEY`).

```bash
firebase functions:secrets:set API_SPORTS_KEY
firebase deploy --only functions
```

## Testing

Run tests in Xcode with `⌘U`, or use the terminal:

```bash
xcodebuild test -project Fanfolio.xcodeproj -scheme Fanfolio -destination 'platform=iOS Simulator,name=iPhone 17'
```

Replace `iPhone 17` with an available simulator name if needed.
