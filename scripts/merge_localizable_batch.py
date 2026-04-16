#!/usr/bin/env python3
"""Merge new localization keys into Fanfolio/Localizable.xcstrings (en + ko)."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "Fanfolio" / "Localizable.xcstrings"

# key -> (en, ko)
NEW: dict[str, tuple[str, str]] = {
    "common.section.completed": ("Completed", "완료"),
    "culture.list.emptyTitle": ("No records yet", "기록이 없습니다"),
    "culture.list.emptyDescription": (
        "Tap + to add your first visit.",
        "+ 버튼을 눌러 첫 관람을 기록해보세요!",
    ),
    "culture.stats.average": ("Average", "평균"),
    "culture.stats.visitsCount": ("%lld visits", "%lld회 관람"),
    "culture.rating.distribution.excellent": ("Top", "최고"),
    "culture.rating.distribution.good": ("Good", "좋음"),
    "culture.fanTitle.king": ("Culture royalty", "문화계의 왕"),
    "culture.fanTitle.maniac": ("Culture fanatic", "문화 마니아"),
    "culture.fanTitle.passionate": ("Passionate audience", "열정적인 관객"),
    "culture.fanTitle.lover": ("Culture lover", "문화 애호가"),
    "culture.fanTitle.beginner": ("Culture newcomer", "문화 입문자"),
    "culture.deleteRecord.title": ("Delete record", "기록 삭제"),
    "record.deleteConfirm": (
        "Delete '%@'? This can't be undone.",
        "‘%@’ 기록을 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.",
    ),
    "sports.list.emptyTitle": ("No games recorded", "경기 기록이 없습니다"),
    "sports.list.emptyDescription": (
        "Tap + to add your first game.",
        "+ 버튼을 눌러 첫 경기를 기록해보세요!",
    ),
    "sports.menu.manualEntry": ("Enter manually", "직접 입력"),
    "sports.menu.importSchedule": ("Import schedule", "경기 불러오기"),
    "sports.live.loading": ("Loading live scores…", "실시간 스코어 로딩 중…"),
    "sports.live.header.live": ("Live scores", "실시간 스코어"),
    "sports.live.header.games": ("Scores", "경기 스코어"),
    "sports.live.pullRefresh": ("· Pull down to refresh", "· 아래로 당겨서 새로고침"),
    "sports.live.apiKey.title": ("Live scores not set up", "실시간 스코어 미설정"),
    "sports.live.apiKey.message": (
        "Add API_SPORTS_KEY in APIKeys.xcconfig to enable live scores. Copy from the example file.",
        "APIKeys.xcconfig에 API_SPORTS_KEY를 설정하면 실시간 스코어를 이용할 수 있습니다. example 파일을 복사해 사용하세요.",
    ),
    "sports.live.api.callsRemaining": ("%lld left", "%lld회 남음"),
    "sports.live.api.todayRemaining": ("Today's API quota", "오늘 API 잔여"),
    "sports.teamBanner.title": ("Team info", "팀 정보"),
    "sports.teamBanner.roster": ("Roster", "팀 선수단"),
    "sports.teamBanner.favoriteCount": ("%lld favorites", "최애 %lld명"),
    "sports.deleteMatch.title": ("Delete game", "경기 기록 삭제"),
    "ticket.detail.qrRow": ("Ticket · QR code", "티켓 · QR코드"),
    "ticket.detail.tapToEnlarge": ("Tap to enlarge", "탭하여 확대"),
    "ticket.section.attendancePhotos": ("Game-day photos", "직관 사진"),
    "ticket.section.venuePhotos": ("Venue photos", "현장 사진"),
    "ticket.section.memo": ("Notes", "메모"),
    "ticket.photoCount": ("%lld photos", "%lld장"),
    "ticket.brand.name": ("Fanfolio", "Fanfolio"),
    "sports.detail.editBanner.hint": (
        "Tap Edit to enter the final score.",
        "편집 버튼을 눌러 경기 결과를 입력하세요",
    ),
    "sports.detail.playerHighlights.loading": ("Player highlights", "선수 하이라이트"),
    "sports.detail.vip.headline": ("Favorite players", "최애 선수 활약"),
    "sports.detail.vip.badge": ("V.I.P.", "V.I.P."),
    "sports.detail.lineup.title": ("Team lineup", "팀 라인업"),
    "sports.detail.shareTicketImage": ("Share ticket image", "티켓 이미지 공유하기"),
    "sports.detail.savedTickets": ("Saved tickets", "저장한 티켓"),
    "culture.detail.status.upcomingLabel": ("Upcoming", "예정"),
    "culture.detail.editBanner.rating": (
        "Tap Edit to add your rating after you attend.",
        "편집 버튼을 눌러 관람 후 평가를 남겨보세요",
    ),
    "culture.rating.word.5": ("Amazing!", "최고!"),
    "culture.rating.word.4": ("Loved it", "좋았어요"),
    "culture.rating.word.3": ("It was OK", "괜찮았어요"),
    "culture.rating.word.2": ("Disappointing", "아쉬워요"),
    "culture.rating.word.1": ("Not for me", "별로"),
    "qr.zoom.hint": ("Scan this QR at entry.", "입장 시 이 QR을 스캔하세요"),
    "share.preview.navigationTitle": ("Share preview", "공유 미리보기"),
    "share.preview.styleSegment": ("Style", "스타일"),
    "share.preview.generating": ("Generating image…", "이미지 생성 중…"),
    "share.preview.shareButton": ("Share", "공유하기"),
    "teamInfo.header.stats": ("Team stats", "팀 스탯"),
    "teamInfo.gamesPlayed": ("%lld games", "%lld경기"),
    "teamInfo.winRate": ("Win rate", "승률"),
    "teamInfo.home": ("Home", "홈"),
    "teamInfo.away": ("Away", "원정"),
    "teamInfo.record.wl": ("%1$lldW %2$lldL", "%1$lld승 %2$lld패"),
    "teamInfo.gamesShort": ("%lld games", "%lld경기"),
    "teamInfo.streak.win": ("Win streak", "연승"),
    "teamInfo.streak.loss": ("Loss streak", "연패"),
    "teamInfo.streak.count": ("%lld in a row", "%lld연속"),
    "teamInfo.navTitle": ("Team info", "팀 정보"),
    "teamInfo.favoritePlayers": ("Favorite players", "최애 선수"),
    "teamInfo.favoriteCount": ("%lld players", "%lld명"),
    "teamInfo.roster": ("Roster", "팀 선수단"),
    "teamInfo.rosterUnavailable": ("Roster unavailable.", "선수단 정보를 찾을 수 없습니다"),
    "scoreboard.total": ("Total", "합계"),
    "scoreboard.side.home": ("Home", "홈"),
    "match.status.scheduledShort": ("Scheduled", "경기 예정"),
    "stats.empty.completeGames": (
        "Stats appear after you mark games as completed.",
        "경기를 완료로 기록하면 통계가 나타납니다.",
    ),
    "cultureStats.empty.completeVisits": (
        "Stats appear after you mark visits as completed.",
        "관람을 완료로 기록하면 통계가 나타납니다.",
    ),
    "stats.summary.title": ("Record summary", "전적 요약"),
    "stats.opponent.title": ("Head-to-head", "상대별 전적"),
    "stats.monthly.title": ("Monthly games", "월별 기록"),
    "stats.months.recent": ("Last 12 months", "최근 12개월"),
    "stats.heatmap.less": ("Less", "적음"),
    "stats.heatmap.more": ("More", "많음"),
    "stats.milestones.title": ("Attendance milestones", "직관 마일스톤"),
    "stats.share.seasonReport": ("Share season report", "시즌 리포트 공유하기"),
    "stats.report.title": ("My season report", "나의 시즌 리포트"),
    "stats.report.top": ("Top", "상위"),
    "stats.report.fanPercentile": ("Fan percentile", "팬 퍼센타일"),
    "stats.report.winRate": ("Win rate", "승률"),
    "stats.streak.maxWins": ("%lld-win streak", "%lld연승"),
    "stats.streak.none": ("No streak", "기록 없음"),
    "stats.streak.longest": ("Longest streak", "최다 연승"),
    "stats.highlight.season": ("Season highlights", "시즌 하이라이트"),
    "stats.badges.unlocked": ("Badges earned", "달성 뱃지"),
    "stats.opponent.mostPlayed": ("Most played opponent", "최다 대결"),
    "cultureStats.starDistribution": ("Rating breakdown", "별점 분포"),
    "cultureStats.ratedCount": ("%lld rated", "%lld개 평가"),
    "cultureStats.artistSection": ("By artist", "아티스트별 관람"),
    "cultureStats.noArtistData": (
        "No records with artist info.",
        "아티스트 정보가 있는 기록이 없습니다.",
    ),
    "cultureStats.avgRating": ("Avg. rating", "평균 별점"),
    "matchImport.vsPrefix": ("vs %@", "vs %@"),
    "match.row.live": ("LIVE", "LIVE"),
    "ticket.share.design": ("Design", "디자인"),
    "ticket.share.win": ("WIN", "WIN"),
    "ticket.share.action": ("Share", "공유"),
    "ticket.share.saveFailedTitle": ("Couldn't save", "저장 실패"),
    "addFolder.artistName": ("Artist / folder name", "아티스트 / 폴더 이름"),
    "addFolder.artistHint": (
        "Enter an artist, show, or interest.",
        "좋아하는 아티스트, 작품, 또는 관심사 이름을 입력하세요.",
    ),
    "addMatch.titleLabel": ("Title", "제목"),
    "addMatch.titleHint": (
        "Name this game or event.",
        "기록할 경기나 이벤트 이름을 입력하세요.",
    ),
    "addMatch.statusHint": (
        "Choose upcoming before the game, or completed after.",
        "경기 전이면 '경기 예정', 이미 끝난 경기를 기록하면 '완료'를 선택하세요.",
    ),
    "addMatch.myTeam": ("My team", "내 팀"),
    "addMatch.matchInfo": ("Game details", "경기 정보"),
    "addMatch.photosSection": ("Game-day photos", "직관 사진"),
    "addMatch.photosHint": (
        "Stadium shots, selfies, food — save the memory. (Max 10)",
        "경기장 사진, 셀카, 음식 등 직관 추억을 기록하세요. (최대 10장)",
    ),
    "addCulture.statusHint": (
        "Choose upcoming before, or completed after you attend.",
        "관람 전이면 '예정', 이미 본 공연/영화를 기록하면 '완료'를 선택하세요.",
    ),
    "addCulture.folderLabel": ("Folder", "폴더"),
    "addCulture.eventInfo": ("Event details", "이벤트 정보"),
    "addCulture.photosSection": ("Venue photos", "현장 사진"),
    "addCulture.photosHint": (
        "Venue shots, selfies, photocards — save the memory. (Max 10)",
        "공연장 사진, 셀카, 포토카드 등 추억을 기록하세요. (최대 10장)",
    ),
    "editCulture.statusHint": (
        "Use upcoming before you go, completed after.",
        "관람 전에는 '예정', 관람 후에는 '완료'로 변경하세요.",
    ),
    "editCulture.folderLabel": ("Folder", "폴더"),
    "editCulture.eventInfo": ("Event details", "이벤트 정보"),
    "editCulture.photosSection": ("Venue photos", "현장 사진"),
    "editCulture.photosHint": (
        "Venue shots, selfies, photocards — save the memory. (Max 10)",
        "공연장 사진, 셀카, 포토카드 등 추억을 기록하세요. (최대 10장)",
    ),
    "playerDetail.favorite": ("Favorite player", "최애 선수"),
    "matchTicket.brand": ("FANFOLIO", "FANFOLIO"),
}


def entry(en: str, ko: str) -> dict:
    return {
        "localizations": {
            "en": {"stringUnit": {"state": "translated", "value": en}},
            "ko": {"stringUnit": {"state": "translated", "value": ko}},
        }
    }


def main() -> None:
    data = json.loads(ROOT.read_text(encoding="utf-8"))
    strings: dict = data["strings"]
    for key, (en, ko) in NEW.items():
        strings[key] = entry(en, ko)
    ROOT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Merged {len(NEW)} keys into {ROOT}")


if __name__ == "__main__":
    main()
