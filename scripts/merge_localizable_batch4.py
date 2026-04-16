#!/usr/bin/env python3
"""Culture stats fan titles, culture milestones, add folder, add match form."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "Fanfolio" / "Localizable.xcstrings"

NEW: dict[str, tuple[str, str]] = {
    # CultureStatsView — fan tier
    "cultureStats.fan.tier100.title": ("Culture royalty", "문화계의 왕"),
    "cultureStats.fan.tier100.subtitle": ("100+ visits—you’re a culture master!", "100회 이상 관람, 진정한 문화 마스터!"),
    "cultureStats.fan.tier50.title": ("Culture fanatic", "문화 마니아"),
    "cultureStats.fan.tier50.subtitle": ("You’re a regular at the show!", "당신은 공연의 단골!"),
    "cultureStats.fan.tier30.title": ("Passionate audience", "열정적인 관객"),
    "cultureStats.fan.tier30.subtitle": ("Love your steady visit streak!", "꾸준한 관람 기록이 멋져요!"),
    "cultureStats.fan.tier15.title": ("Culture lover", "문화 애호가"),
    "cultureStats.fan.tier15.subtitle": ("You’re discovering the fun of culture!", "문화 생활의 재미를 알아가고 있어요!"),
    "cultureStats.fan.tier5.title": ("Culture newcomer", "문화 입문자"),
    "cultureStats.fan.tier5.subtitle": ("Great start—keep exploring!", "좋은 시작이에요! 더 많이 즐겨보세요!"),
    "cultureStats.fan.tier0.title": ("Culture sprout", "문화 새싹"),
    "cultureStats.fan.tier0.subtitle": ("You took the first step!", "첫 걸음을 내딛었어요!"),
    # Culture milestones
    "milestone.culture.first.title": ("First visit", "첫 관람"),
    "milestone.culture.first.desc": ("First record", "첫 기록 달성"),
    "milestone.culture.ten.title": ("10 visits", "10회 관람"),
    "milestone.culture.ten.desc": ("10 records", "10회 기록 달성"),
    "milestone.culture.twentyfive.title": ("25 visits", "25회 관람"),
    "milestone.culture.twentyfive.desc": ("25 records", "25회 기록 달성"),
    "milestone.culture.fifty.title": ("50 visits", "50회 관람"),
    "milestone.culture.fifty.desc": ("50 records", "50회 기록 달성"),
    "milestone.culture.hundred.title": ("100 visits", "100회 관람"),
    "milestone.culture.hundred.desc": ("100 records", "100회 기록 달성"),
    "milestone.culture.perfect.title": ("Perfect show", "완벽한 공연"),
    "milestone.culture.perfect.desc": ("A 5-star rating", "별점 5점 기록"),
    "milestone.culture.diverse.title": ("Eclectic taste", "다양한 취향"),
    "milestone.culture.diverse.desc": ("5+ different artists", "5명 이상 아티스트 관람"),
    "milestone.culture.photographer.title": ("Photographer", "포토그래퍼"),
    "milestone.culture.photographer.desc": ("Logged with photos", "사진과 함께 기록"),
    "milestone.culture.collector.title": ("Ticket collector", "티켓 수집가"),
    "milestone.culture.collector.desc": ("QR or ticket image", "QR/티켓 사진 첨부"),
    "milestone.culture.explorer.title": ("Explorer", "탐험가"),
    "milestone.culture.explorer.desc": ("5+ venues", "5곳 이상 장소 방문"),
    "milestone.culture.superfan.title": ("Superfan", "슈퍼팬"),
    "milestone.culture.superfan.desc": ("Same artist 3+ times", "같은 아티스트 3회 이상"),
    "milestone.culture.critic.title": ("Critic", "평론가"),
    "milestone.culture.critic.desc": ("10+ star ratings", "10개 이상 별점 평가"),
    "cultureStats.artistVisitCount": ("%lld visits", "%lld회"),
    # Add culture folder
    "addFolder.section.category": ("Choose category", "카테고리 선택"),
    "addFolder.textField.placeholder": ("e.g. BTS, Wicked, movie at CGV", "예: BTS, 위키드, CGV 영화"),
    "addFolder.nav.new": ("New folder", "새 폴더"),
    "addFolder.nav.edit": ("Edit folder", "폴더 편집"),
    # Add sports match
    "addMatch.navigationTitle": ("Log game", "경기 기록"),
    "addMatch.picker.matchStatus": ("Match status", "경기 상태"),
    "addMatch.label.opponent": ("Opponent", "상대 팀"),
    "addMatch.label.team1": ("Team 1", "팀 1"),
    "addMatch.label.team2": ("Team 2", "팀 2"),
    "addMatch.footer.sameLeague": ("Tap a team from the same league.", "같은 리그 팀을 탭하여 선택하세요."),
    "addMatch.footer.pickTwo": ("Tap each team to select.", "경기한 두 팀을 각각 탭하여 선택하세요."),
    "addMatch.toggle.homeGame": ("Home game", "홈 경기"),
    "addMatch.section.score": ("Score", "스코어"),
    "addMatch.picker.result": ("Result", "결과"),
    "addMatch.section.dateLocation": ("Date & place", "날짜 · 장소"),
    "addMatch.field.date": ("Date", "날짜"),
    "addMatch.toggle.setTime": ("Set time", "시간 설정"),
    "addMatch.field.time": ("Time", "시간"),
    "addMatch.field.locationOptional": ("Venue (optional)", "장소 (선택)"),
    "addMatch.photos.add": ("Add game photos", "직관 사진 추가"),
    "addMatch.photos.addCount": ("Add photos (%lld/10)", "사진 추가 (%lld/10)"),
    "addMatch.section.memo": ("Notes", "메모"),
    "addMatch.memo.placeholder": ("Thoughts, highlights…", "경기 감상, 하이라이트 등"),
    "addMatch.noOpponent.placeholder": ("e.g. tennis outing, marathon finish", "예: 테니스 직관, 마라톤 완주"),
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
    print(f"Merged {len(NEW)} keys")


if __name__ == "__main__":
    main()
