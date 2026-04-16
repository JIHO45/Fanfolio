#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "Fanfolio" / "Localizable.xcstrings"

NEW: dict[str, tuple[str, str]] = {
    "fanstats.computing": ("Computing stats…", "통계 계산 중…"),
    "fanstats.empty.noCompleted": ("No completed games", "완료된 경기가 없습니다"),
    "fanstats.navigation.title": ("Fan stats", "팬 통계"),
    "stats.maxWinStreakFormat": ("Best win streak: %lld wins", "최다 연승: %lld연승"),
    "stats.record.wldFull": ("%1$lldW %2$lldL %3$lldD", "%1$lld승 %2$lld패 %3$lld무"),
    "stats.gamesLabelShort": ("Games", "경기"),
    "cultureStats.navigation.title": ("Visit stats", "관람 통계"),
    "cultureStats.empty.noCompleted": ("No completed records", "완료된 기록이 없습니다"),
    "cultureStats.monthSuffix": ("%lld", "%lld월"),
    "cultureStats.milestone.section": ("Visit milestones", "관람 마일스톤"),
    "culture.report.share": ("Share visit report", "관람 리포트 공유하기"),
    "milestone.sports.first.title": ("First game", "첫 직관"),
    "milestone.sports.first.desc": ("First game logged", "첫 경기 기록"),
    "milestone.sports.ten.title": ("10 games", "10회 직관"),
    "milestone.sports.ten.desc": ("10 games logged", "10경기 기록 달성"),
    "milestone.sports.twentyfive.title": ("25 games", "25회 직관"),
    "milestone.sports.twentyfive.desc": ("25 games logged", "25경기 기록 달성"),
    "milestone.sports.fifty.title": ("50 games", "50회 직관"),
    "milestone.sports.fifty.desc": ("50 games logged", "50경기 기록 달성"),
    "milestone.sports.hundred.title": ("100 games", "100회 직관"),
    "milestone.sports.hundred.desc": ("100 games logged", "100경기 기록 달성"),
    "milestone.sports.away.title": ("First road game", "첫 원정"),
    "milestone.sports.away.desc": ("Logged an away game", "원정 경기 기록"),
    "milestone.sports.streak3.title": ("Saw a 3-win streak", "3연승 목격"),
    "milestone.sports.streak3.desc": ("Three wins in a row", "연속 3승 달성"),
    "milestone.sports.streak5.title": ("Saw a 5-win streak", "5연승 목격"),
    "milestone.sports.streak5.desc": ("Five wins in a row", "연속 5승 달성"),
    "milestone.sports.shutout.title": ("Shutout win", "완봉승 목격"),
    "milestone.sports.shutout.desc": ("Win without conceding", "상대 무득점 승리"),
    "milestone.sports.rival.title": ("Rival buff", "라이벌 마니아"),
    "milestone.sports.rival.desc": ("Same opponent 5+ times", "같은 상대 5경기 이상"),
    "milestone.sports.home10.title": ("Home protector", "홈 지킴이"),
    "milestone.sports.home10.desc": ("10+ home wins", "홈경기 10승 이상"),
    "milestone.sports.road5.title": ("Road warrior", "원정 전사"),
    "milestone.sports.road5.desc": ("5+ away games", "원정 5경기 이상"),
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
