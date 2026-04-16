#!/usr/bin/env python3
"""Fill missing en/ko entries in Localizable.xcstrings and InfoPlist.xcstrings."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SU = {"state": "translated"}


def unit(value: str) -> dict:
    return {"stringUnit": {**SU, "value": value}}


def add_pair(obj: dict, en: str, ko: str) -> None:
    loc = obj.setdefault("localizations", {})
    loc["en"] = unit(en)
    loc["ko"] = unit(ko)


# Keys that had only `ko` — add English (format strings: same pattern).
KO_ONLY_EN: dict[str, str] = {
    "%@ %@": "%1$@ %2$@",
    "%@ vs %@": "%1$@ vs %2$@",
    "%lld - %lld": "%1$lld - %2$lld",
    "%lld : %lld · %@": "%1$lld : %2$lld · %3$@",
    "%lld %@": "%1$lld %2$@",
    "%lld-%lld-%lld": "%1$lld-%2$lld-%3$lld",
    "%lld/%lld": "%1$lld/%2$lld",
    "culture.ticket.caption": "Caption",
    "fanstats.map.roadTrip.snapshot.totalKm": "Total %lld km",
    "fanstats.map.roadTrip.snapshot.venues": "%d venues",
    "fanstats.map.roadTrip.snapshot.winRate": "Win rate %@",
    "fanstats.map.roadTrip.summary.share.preparing": "Creating image…",
    "inning.extra.label": "Extra",
    "kbo.firestore.error.httpErrorFormat": (
        "Firestore error (HTTP %d). Check security rules and your API key."
    ),
    "kbo.firestore.error.invalidURL": "The Firestore URL is invalid.",
    "kbo.firestore.error.notConfigured": (
        "Firebase project ID is not set. Add FIREBASE_PROJECT_ID to APIKeys.xcconfig."
    ),
    "kbo.firestore.error.parseErrorFormat": "Failed to parse Firestore data: %@",
    "matchImport.footer.showMore": "Show more games (%d)",
    "matchImport.section.recentResultsCount": "Recent results (%1$d/%2$d games)",
    "matchImport.section.upcomingScheduleCount": "Upcoming schedule (%1$d/%2$d games)",
    "sports.folder.kbo.noTeams": (
        "No KBO team data.\nIt may be preseason or Firebase sync may not be finished yet."
    ),
    "standings.kbo.error.notConfigured": (
        "Firebase setup required. Add FIREBASE_PROJECT_ID to APIKeys.xcconfig."
    ),
    "standings.kbo.sectionTitle": "KBO standings (%d)",
}

# Empty `localizations` — add en + ko (ko matches current UI where key is Korean).
EMPTY_PAIRS: dict[str, tuple[str, str]] = {
    "": ("", ""),
    " / 5": (" / 5", " / 5"),
    "-": ("-", "-"),
    "—": ("—", "—"),
    ":": (":", ":"),
    "·": ("·", "·"),
    "· ": ("· ", "· "),
    "· %@": ("· %@", "· %@"),
    "#": ("#", "#"),
    "#%@": ("#%@", "#%@"),
    "%": ("%", "%"),
    "%@": ("%@", "%@"),
    "%lld": ("%lld", "%lld"),
    "%lld%%": ("%lld%%", "%lld%%"),
    "%lld회": ("%lld times", "%lld회"),
    "⚔️": ("⚔️", "⚔️"),
    "💧": ("💧", "💧"),
    "🔥": ("🔥", "🔥"),
    "AWAY": ("Away", "원정"),
    "D": ("D", "무"),
    "Fanfolio": ("Fanfolio", "Fanfolio"),
    "FANFOLIO": ("FANFOLIO", "FANFOLIO"),
    "HOME": ("Home", "홈"),
    "L": ("L", "패"),
    "LIVE": ("LIVE", "LIVE"),
    "UPCOMING": ("Upcoming", "예정"),
    "VS": ("vs", "vs"),
    "W": ("W", "승"),
    "감상평, 하이라이트, 셋리스트 등": (
        "Reviews, highlights, set lists, and more",
        "감상평, 하이라이트, 셋리스트 등",
    ),
    "관람 기록": ("Visit history", "관람 기록"),
    "괜찮았어요": ("It was OK", "괜찮았어요"),
    "국적": ("Nationality", "국적"),
    "기본": ("Default", "기본"),
    "나이": ("Age", "나이"),
    "날짜": ("Date", "날짜"),
    "날짜 · 장소": ("Date · Place", "날짜 · 장소"),
    "내 갤러리에 저장": ("Save to my gallery", "내 갤러리에 저장"),
    "내 글": ("My writing", "내 글"),
    "닫기": ("Close", "닫기"),
    "등번호": ("Jersey #", "등번호"),
    "메모": ("Notes", "메모"),
    "상태": ("Status", "상태"),
    "세로": ("Vertical", "세로"),
    "소속팀": ("Team", "소속팀"),
    "시간": ("Time", "시간"),
    "시간 설정": ("Set time", "시간 설정"),
    "아쉬웠어요": ("Disappointing", "아쉬웠어요"),
    "아티스트 / 출연진": ("Artist / performers", "아티스트 / 출연진"),
    "아티스트 / 출연진 (선택)": ("Artist / performers (optional)", "아티스트 / 출연진 (선택)"),
    "예: LG 트윈스, FC서울": ("e.g. LG Twins, FC Seoul", "예: LG 트윈스, FC서울"),
    "예: 테니스 직관, 복싱 경기": ("e.g. tennis match, boxing", "예: 테니스 직관, 복싱 경기"),
    "오류": ("Error", "오류"),
    "저장": ("Save", "저장"),
    "저장 실패": ("Save failed", "저장 실패"),
    "저장 중...": ("Saving…", "저장 중..."),
    "제목": ("Title", "제목"),
    "제목 (예: 위키드 첫 관람)": ("Title (e.g. first Wicked visit)", "제목 (예: 위키드 첫 관람)"),
    "직관 한마디를 적어보세요": ("Write a short game-day note", "직관 한마디를 적어보세요"),
    "최고의 경험!": ("Amazing!", "최고의 경험!"),
    "취소": ("Cancel", "취소"),
    "키워드": ("Keywords", "키워드"),
    "편집": ("Edit", "편집"),
    "평가": ("Rating", "평가"),
    "포지션": ("Position", "포지션"),
    "확인": ("OK", "확인"),
    "별로였어요": ("Not great", "별로였어요"),
    "매우 좋았어요": ("Loved it", "매우 좋았어요"),
    "별점을 선택하세요": ("Select a star rating", "별점을 선택하세요"),
    "소감을 적어보세요": ("Write your thoughts", "소감을 적어보세요"),
    "선수 정보": ("Player info", "선수 정보"),
    "사진 앱에 저장": ("Save to Photos", "사진 앱에 저장"),
    "현장 사진 추가": ("Add venue photos", "현장 사진 추가"),
    "티켓 이미지 공유": ("Share ticket image", "티켓 이미지 공유"),
    "장소 (선택)": ("Venue (optional)", "장소 (선택)"),
    "좌석 정보 (선택)": ("Seat info (optional)", "좌석 정보 (선택)"),
    "사진 추가 (%lld/10)": ("Add photos (%1$lld/10)", "사진 추가 (%1$lld/10)"),
    "이름": ("Name", "이름"),
}


def patch_localizable() -> int:
    path = ROOT / "Fanfolio" / "Localizable.xcstrings"
    data = json.loads(path.read_text(encoding="utf-8"))
    strings = data["strings"]
    changed = 0

    for key, en in KO_ONLY_EN.items():
        if key not in strings:
            continue
        entry = strings[key]
        loc = entry.setdefault("localizations", {})
        if "en" in loc:
            continue
        if "ko" not in loc:
            continue
        ko_val = loc["ko"]["stringUnit"]["value"]
        loc["en"] = unit(en)
        # keep ko as-is
        if ko_val != loc["ko"]["stringUnit"]["value"]:
            pass
        changed += 1

    for key, (en, ko) in EMPTY_PAIRS.items():
        if key not in strings:
            continue
        entry = strings[key]
        if entry.get("localizations"):
            continue
        entry["localizations"] = {"en": unit(en), "ko": unit(ko)}
        changed += 1

    # Any remaining empty: add en = ko = key for ASCII-like keys
    for key, entry in strings.items():
        if entry.get("localizations"):
            continue
        if key in EMPTY_PAIRS or key in KO_ONLY_EN:
            continue
        entry["localizations"] = {"en": unit(key), "ko": unit(key)}
        changed += 1

    # Ensure every localization block has both en and ko when partially filled
    for key, entry in strings.items():
        loc = entry.get("localizations")
        if not loc:
            continue
        has_en = "en" in loc
        has_ko = "ko" in loc
        if has_en and has_ko:
            continue
        if has_en and not has_ko:
            loc["ko"] = unit(loc["en"]["stringUnit"]["value"])
            changed += 1
        elif has_ko and not has_en:
            loc["en"] = unit(loc["ko"]["stringUnit"]["value"])
            changed += 1

    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return changed


def patch_infoplist() -> None:
    path = ROOT / "Fanfolio" / "InfoPlist.xcstrings"
    data = json.loads(path.read_text(encoding="utf-8"))
    bundle = data["strings"]["CFBundleName"]
    loc = bundle.setdefault("localizations", {})
    loc.setdefault(
        "en",
        {"stringUnit": {"state": "translated", "value": "Fanfolio"}},
    )
    loc.setdefault(
        "ko",
        {"stringUnit": {"state": "translated", "value": "Fanfolio"}},
    )
    for lang in ("en", "ko"):
        loc[lang]["stringUnit"]["state"] = "translated"
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def patch_pbx_known_regions() -> None:
    pbx = ROOT / "Fanfolio.xcodeproj" / "project.pbxproj"
    text = pbx.read_text(encoding="utf-8")
    old = "\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);"
    new = "\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tko,\n\t\t\t\tBase,\n\t\t\t);"
    if old not in text:
        if "ko" in text and "knownRegions" in text:
            return
        raise SystemExit("project.pbxproj knownRegions block not found; update manually")
    pbx.write_text(text.replace(old, new, 1), encoding="utf-8")


def main() -> None:
    n = patch_localizable()
    patch_infoplist()
    patch_pbx_known_regions()
    print(f"Localizable.xcstrings updates applied ({n} entries touched in first pass + merges).")
    print("InfoPlist.xcstrings CFBundleName: en + ko.")
    print("project.pbxproj: added ko to knownRegions.")


if __name__ == "__main__":
    main()
