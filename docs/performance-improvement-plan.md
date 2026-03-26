# 메모리·성능 개선 계획 (정제본)

적용 순서: **1 → 2 → 3 → 4**

---

## 1. 사진 파일 경로 저장 + 다운샘플링 (OOM 방지)

### 목표
- 사진은 Document 디렉터리 **파일**로 저장, 모델에는 **경로만** 저장.
- 저장 시 가로 1024px 다운샘플 + JPEG 0.8.

### ⚠️ 상대 경로 저장 필수
**iOS는 앱 업데이트마다 샌드박스 폴더 경로(UUID)가 바뀝니다.**  
절대 경로(`file:///var/mobile/Containers/.../Document/...`)를 DB에 저장하면 업데이트 후 이미지가 깨집니다.

- **DB 저장값:** `"MatchPhotos/UUID.jpg"` 형태의 **상대 경로(또는 파일명)** 만 저장.
- **로드 시:** 현재 런타임의 Document 경로를 앞에 붙여서 로드.  
  → **TicketImageStore**의 `url(forRelativePath:)` + `documentsDirectoryURL()` 패턴을 그대로 유지.

### 구현 요약
- Store: `MatchPhotos/`, `CulturePhotos/` 등 상대 경로 기반. `savePhoto` → 상대 경로 반환.
- 모델: `photosData: [Data]?` → `photoPaths: [String]?` (상대 경로 배열).
- 뷰: 저장 시 Store 사용, 표시 시 Store.loadImage(상대 경로) 사용.

---

## 2. 통계 비동기 처리 (메인 스레드 부담 감소)

### 목표
- FanStatsView / TeamInfoDetailView 등에서 `folder.matches` 기반 계산을 백그라운드에서 수행.
- 결과만 `@State`로 보관해 UI에 바인딩.

### ⚠️ SwiftData 스레드 안전성
**SwiftData의 @Model 객체는 생성된 컨텍스트(MainActor)에 묶여 있습니다.**  
`folder.matches`를 그대로 백그라운드 Task에 넘기면 런타임 크래시 가능.

**해결:** 메인 스레드에서 **통계에 필요한 최소 데이터만 순수 구조체(DTO)로 매핑**한 뒤, 그 DTO만 백그라운드로 전달.

```swift
// 예: 순수 값 타입으로 매핑 후 백그라운드로 전달
let statsData = folder.matches.map { m in
    MatchStatDTO(
        result: m.matchResult,
        date: m.date,
        isHomeGame: m.isHomeGame
        // photosData 등 불필요 필드는 제외
    )
}
Task.detached(priority: .userInitiated) {
    let result = FanStatsCalculator(data: statsData).compute()
    await MainActor.run { self.statsResult = result }
}
```

- `FanStatsCalculator`: `[SportsModel]` 대신 `[MatchStatDTO]` (또는 동일한 값 타입)를 받는 오버로드 추가.
- 메인 스레드: `folder.matches` → DTO 배열 생성 후, 해당 배열만 Task에 전달.

---

## 3. MatchTicketCardView .drawingGroup()

### 목표
- 티켓 카드 루트 ZStack에 `.drawingGroup()` 적용해 스크롤 시 렌더링 부하 감소.

### ⚠️ 실기기 시각 검증
`.drawingGroup()`은 Metal 텍스처로 래스터화하기 때문에, **바깥쪽 .shadow가 잘리거나 블렌드가 미세하게 달라질 수 있습니다.**  
반드시 **시뮬레이터가 아닌 실기기**에서 그림자·모서리 둥글기 깨짐 여부를 눈으로 확인할 것.

---

## 4. 라이브 스코어 30초 폴링

### 목표
- 실시간 스코어 섹션이 보일 때 30초마다 해당 리그 스코어 재요청.

### 권장 구현: Task + Task.sleep (Timer 대신)
`Timer.publish`는 `onDisappear`에서 수동으로 cancellable 해제가 필요합니다.  
Swift Concurrency를 쓰면 뷰가 사라질 때 **Task가 자동 취소**되어 코드가 단순해집니다.

```swift
.task {
    await loadLiveFixtures()
    while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 30_000_000_000) // 30초
        await loadLiveFixtures()
    }
}
```

- 실시간 스코어 섹션을 보여주는 뷰(예: SportsView의 해당 블록 또는 자식)에 `.task`로 위 로직 부착.
- 뷰가 사라지면 Task 취소 → 루프 종료, 별도 타이머 해제 불필요.

---

## 체크리스트 (구현 시)

| # | 항목 | 확인 |
|---|------|------|
| 1 | 사진 저장 경로가 **상대 경로**만 DB에 저장되는가 | |
| 1 | 로드 시 Document 기준 URL 조합(TicketImageStore 패턴) 사용하는가 | |
| 2 | 통계 계산에 **DTO 매핑** 후 백그라운드 전달하는가 (folder.matches 직접 전달 금지) | |
| 3 | .drawingGroup() 적용 후 **실기기**에서 그림자/모서리 확인했는가 | |
| 4 | 라이브 폴링이 **Task + Task.sleep**으로 구현되고, 뷰 이탈 시 자동 취소되는가 | |
