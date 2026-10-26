# Fanfolio

스포츠 경기와 문화 공연의 티켓·관람 기록을 한곳에 모아 관리하는 iOS 앱입니다.
직관 기록을 폴더별로 정리하고, 승률·방문 구장 같은 팬 통계와 실시간 스코어를 함께 확인할 수 있습니다.

## 주요 기능

- **스포츠 직관 기록**: 경기·티켓 사진·QR 코드 저장, 폴더별 정리, 팬 통계(직관 승률 등)
- **실시간 스코어**: KBO·ESPN 리그 라이브 스코어보드, Live Activity 및 위젯 지원
- **리그 순위·선수 정보**: 리그별 순위표, 팀 로스터, 즐겨찾기 선수
- **구장 지도**: Mapbox 기반 방문 구장 지도 및 원정 하이라이트
- **문화 공연 기록**: 공연·전시 티켓 기록과 통계
- **티켓 갤러리·공유**: 티켓 카드 이미지 생성 및 공유
- **동기화**: SwiftData + CloudKit으로 기기 간 자동 동기화 (iCloud 미사용 시 로컬 저장)
- **로그인·구독**: Sign in with Apple / 게스트 모드, StoreKit 기반 Pro 구독

## 기술 스택

| 구분 | 내용 |
| --- | --- |
| 앱 | Swift, SwiftUI, SwiftData, CloudKit, ActivityKit, WidgetKit, StoreKit |
| 패키지 (SPM) | Firebase iOS SDK, Mapbox Maps iOS, Kingfisher |
| 데이터 소스 | API-Sports (KBO), ESPN API |
| 백엔드 | Firebase Cloud Functions, Firestore |

## 프로젝트 구조

```
Fanfolio/                  # 메인 앱
├── Data/                  # 정적 데이터 (ESPN 팀 정보)
├── DesignSystem/          # 공통 테마·컴포넌트
├── LiveActivity/          # Live Activity 관리
├── Model/                 # 도메인 모델
├── Service/               # API, 인증, 구독, 저장소 등 서비스 계층
├── View/                  # 화면 (Sports, Culture, TicketGallery, Settings 등)
└── Localizable.xcstrings  # 다국어 문자열
FanfolioLiveScoreWidget/   # 라이브 스코어 위젯·Live Activity 타깃
FanfolioTests/             # 단위 테스트
FanfolioUITests/           # UI 테스트
functions/                 # Firebase Cloud Functions (KBO 데이터 Firestore 동기화)
scripts/localization/      # String Catalog 번역 보조 스크립트
docs/                      # 개발 문서
```

## 시작하기

### 요구 사항

- Xcode 26 이상
- iOS 26.1 이상

### 설정

1. 저장소를 클론합니다.

   ```bash
   git clone https://github.com/JIHO45/Fanfolio.git
   cd Fanfolio
   ```

2. API 키 설정 파일을 만들고 실제 값을 입력합니다.

   ```bash
   cp APIKeys.xcconfig.example APIKeys.xcconfig
   ```

   | 키 | 설명 |
   | --- | --- |
   | `API_SPORTS_KEY` | API-Sports 키 |
   | `MAPBOX_ACCESS_TOKEN` | Mapbox Public 토큰 (`pk.`로 시작) |
   | `FIREBASE_PROJECT_ID` | Firebase 프로젝트 ID |
   | `FIREBASE_WEB_API_KEY` | Firebase 웹 API 키 |
   | `PRIVACY_POLICY_URL` | (선택) 개인정보 처리방침 URL |

   > `APIKeys.xcconfig`와 `DeveloperSettings.xcconfig`는 `.gitignore`에 포함되어 있으며 커밋하지 않습니다.

3. `Fanfolio.xcodeproj`를 열고 `Fanfolio` 스킴으로 빌드·실행합니다.

### Cloud Functions

`functions/index.js`는 API-Sports에서 KBO 경기·순위 데이터를 가져와 Firestore에 주기적으로 동기화합니다. API 키는 Firebase Secret(`API_SPORTS_KEY`)으로 관리합니다.

```bash
firebase functions:secrets:set API_SPORTS_KEY
firebase deploy --only functions
```

## 테스트

Xcode에서 `⌘U`로 실행하거나 터미널에서 실행합니다.

```bash
xcodebuild test -project Fanfolio.xcodeproj -scheme Fanfolio -destination 'platform=iOS Simulator,name=iPhone 17'
```
